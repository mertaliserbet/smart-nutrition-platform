export function LegalLinks({ contact = false, className = '' }: { contact?: boolean; className?: string }) {
  return <div className={`legal-links ${className}`}>
    <details><summary>Gizlilik</summary><p>Danışan verileri aktif bağlantı ve kategori paylaşım izinleriyle görüntülenir. Yayımlanmış gizlilik metni bu sürümde sunulmuyor.</p></details>
    <details><summary>Kullanım koşulları</summary><p>Yayımlanmış kullanım koşulları bu sürümde sunulmuyor.</p></details>
    {contact && <details><summary>İletişim</summary><p>Destek iletişim bilgisi bu sürümde tanımlanmamış.</p></details>}
  </div>
}
