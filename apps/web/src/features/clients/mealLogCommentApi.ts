import { WebSessionError } from '../auth/webSessionApi'
import { isUuid } from '../relationships/relationshipApi'
import type { PagedResponse } from '../relationships/relationshipApi'

export type MealLogComment = { id: string; mealLogId: string; authorUserId: string; text: string; createdAt: string; parentCommentId: string | null }
const invalid = () => new WebSessionError(500, 'Yorum yanıtı doğrulanamadı. Kayıtları yenileyip kontrol edin.')
export const validCommentText = (text: string) => text.trim().length > 0 && !text.includes('\0') && [...text.trim()].length <= 2000
function comment(value: unknown, mealLogId: string): MealLogComment {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).sort().join(',') !== 'authorUserId,createdAt,id,mealLogId,parentCommentId,text') throw invalid()
  const row = value as Record<string, unknown>
  if (!isUuid(row.id) || row.mealLogId !== mealLogId || !isUuid(row.authorUserId) ||
    typeof row.text !== 'string' || !validCommentText(row.text) || row.text !== row.text.trim() ||
    typeof row.createdAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$/.test(row.createdAt) || !Number.isFinite(Date.parse(row.createdAt)) ||
    !(row.parentCommentId === null || (isUuid(row.parentCommentId) && row.parentCommentId !== row.id))) throw invalid()
  return row as MealLogComment
}
async function request(mealLogId: string, signal: AbortSignal, page?: number, text?: string, token?: string) {
  if (!isUuid(mealLogId)) throw new WebSessionError(404, 'Öğün bulunamadı.')
  const writing = text !== undefined
  const query = writing ? '' : `?${new URLSearchParams({ page: String(page), pageSize: '10' })}`
  let response: Response
  try {
    response = await fetch(`/api/v1/meal-logs/${mealLogId}/comments${query}`, {
      method: writing ? 'POST' : 'GET', signal, credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { 'X-Profile-Context': 'dietitian', ...(writing ? { 'X-CSRF-TOKEN': token!, 'Content-Type': 'application/json' } : {}) },
      ...(writing ? { body: JSON.stringify({ text }) } : {}),
    })
  } catch { throw new WebSessionError(0, writing ? 'Gönderim sonucu doğrulanamadı. Yorumları yenileyip kontrol edin.' : 'Yorumlar için sunucuya ulaşılamadı. Yeniden deneyin.') }
  if (response.status !== (writing ? 201 : 200)) {
    throw new WebSessionError(response.status, response.status === 403 ? 'Öğün paylaşımı kapalı veya yorum erişim yetkiniz bulunmuyor.'
      : response.status === 404 ? 'Öğün bulunamadı veya aktif danışan bağlantınız sona erdi.'
        : response.status === 401 ? 'Oturumunuz sona erdi. Yeniden giriş yapın.'
          : response.status === 422 ? 'Yorum boş olamaz ve en fazla 2000 karakter içerebilir.'
            : response.status === 400 ? 'İstek doğrulanamadı. Oturumunuzu ve yorumları yeniden kontrol edin.'
              : writing ? 'Gönderim sonucu doğrulanamadı. Yorumları yenileyip kontrol edin.' : 'Yorumlar okunamadı. Yeniden deneyin.')
  }
  try { return await response.json() as unknown } catch { throw invalid() }
}
export async function getMealLogComments(mealLogId: string, page: number, signal: AbortSignal): Promise<PagedResponse<MealLogComment>> {
  if (!Number.isInteger(page) || page < 1 || (page - 1) * 10 > 2147483647) throw new WebSessionError(400, 'Yorum sayfası geçersiz.')
  const value = await request(mealLogId, signal, page)
  if (!value || typeof value !== 'object' || Object.keys(value).sort().join(',') !== 'items,totalCount') throw invalid()
  const body = value as Record<string, unknown>
  if (!Array.isArray(body.items) || body.items.length > 10 || !Number.isSafeInteger(body.totalCount) || (body.totalCount as number) < 0 ||
    (body.items.length > 0 && (body.totalCount as number) < (page - 1) * 10 + body.items.length)) throw invalid()
  const items = body.items.map(value => comment(value, mealLogId))
  if (new Set(items.map(item => item.id)).size !== items.length || items.some(item => item.parentCommentId !== null && items.some(parent => parent.id === item.parentCommentId && parent.parentCommentId !== null))) throw invalid()
  return { items, totalCount: body.totalCount as number }
}
export async function createMealLogComment(mealLogId: string, text: string, token: string, signal: AbortSignal): Promise<MealLogComment> {
  if (!validCommentText(text)) throw new WebSessionError(422, 'Yorum boş olamaz ve en fazla 2000 karakter içerebilir.')
  if (!token) throw new WebSessionError(400, 'Oturumunuz doğrulanamadı.')
  const trimmed = text.trim()
  const result = comment(await request(mealLogId, signal, undefined, trimmed, token), mealLogId)
  if (result.parentCommentId !== null || result.text !== trimmed) throw invalid()
  return result
}
