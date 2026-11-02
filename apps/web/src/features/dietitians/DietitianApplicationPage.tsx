import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { AuthLayout } from '../auth/AuthLayout'
import { WebSessionError } from '../auth/webSessionApi'
import { applyDietitian, applyExistingDietitian, getDietitianStatus } from './dietitianApi'
import type { DietitianApplicationRequest, DietitianStatusResponse } from './dietitianApi'
import { getAccount, getCsrf } from '../auth/webSessionApi'
import './dietitians.css'

const initial: DietitianApplicationRequest = { displayName: '', email: '', password: '', licenseInfo: '' }
export function DietitianApplicationPage() {
  const [existing, setExisting] = useState(false)
  const [form, setForm] = useState(initial)
  const [showPassword, setShowPassword] = useState(false)
  const [errors, setErrors] = useState<Partial<Record<keyof DietitianApplicationRequest, string>>>({})
  const [message, setMessage] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [pending, setPending] = useState(false)
  const operation = useRef<AbortController | null>(null)
  useEffect(() => () => operation.current?.abort(), [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current || submitted) return
    const errors: Partial<Record<keyof DietitianApplicationRequest, string>> = {}
    if (!form.displayName.trim() || Array.from(form.displayName.trim()).length > 120) errors.displayName = 'Ad ve soyad 1–120 karakter olmalı.'
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) errors.email = 'Geçerli bir e-posta adresi girin.'
    if (Array.from(form.password).length < 8 || Array.from(form.password).length > 128) errors.password = 'Şifre 8–128 karakter olmalı.'
    if (!form.licenseInfo.trim() || Array.from(form.licenseInfo.trim()).length > 2000) errors.licenseInfo = 'Mesleki kayıt açıklaması 1–2000 karakter olmalı.'
    setErrors(errors); setMessage('')
    const first = Object.keys(errors)[0]
    if (first) { event.currentTarget.querySelector<HTMLElement>(`[name="${first}"]`)?.focus(); return }
    const controller = new AbortController(); operation.current = controller
    const body = { ...form, displayName: form.displayName.trim(), email: form.email.trim(), licenseInfo: form.licenseInfo.trim() }
    setForm(current => ({ ...current, password: '' })); setShowPassword(false); setPending(true)
    try {
      await applyDietitian(body, controller.signal)
      if (!controller.signal.aborted) { setSubmitted(true); setForm(initial) }
    } catch (error) {
      if (!controller.signal.aborted) setMessage(error instanceof WebSessionError ? error.message : 'Başvuru tamamlanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }

  function field(name: keyof DietitianApplicationRequest, label: string, multiline = false) {
    const props = { id: `expert-${name}`, name, value: form[name], disabled: pending, required: true,
      'aria-invalid': Boolean(errors[name]), 'aria-describedby': errors[name] ? `expert-${name}-error` : undefined,
      onChange: (event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
        setForm(current => ({ ...current, [name]: event.target.value })); setErrors(current => ({ ...current, [name]: undefined })); setMessage('')
      } }
    return <div className="form-field"><label htmlFor={props.id}>{label}</label>
      {multiline ? <textarea {...props} rows={5} /> : <input {...props} type={name === 'password' ? (showPassword ? 'text' : 'password') : name === 'email' ? 'email' : 'text'}
        autoComplete={name === 'password' ? 'new-password' : name === 'email' ? 'email' : 'name'} />}
      {errors[name] && <p className="field-error" id={`expert-${name}-error`} role="alert">{errors[name]}</p>}
    </div>
  }

  return <AuthLayout title="Diyetisyen başvurusu" badge="Uzman başvurusu" description="Mesleki bilgilerinizi iletin. Danışan erişimi, Admin onayı ve danışanın paylaşım izinleriyle açılır.">
    <button className="button button-secondary" disabled={pending} onClick={() => setExisting(value => !value)}>{existing ? 'Yeni hesapla başvur' : 'Mevcut hesabımla başvur'}</button>
    {existing ? <ExistingAccountApplication /> : submitted ? <p className="form-message" role="status">Başvurunuz kaydedildi. E-postanızı doğrulayın; ardından giriş yaparak Admin onay durumunu takip edebilirsiniz.</p> :
      <form noValidate aria-label="Diyetisyen başvuru formu" aria-busy={pending} onSubmit={event => { void submit(event) }}>
        {field('displayName', 'Ad ve soyad')}{field('email', 'E-posta adresi')}{field('password', 'Şifre')}
        <button className="text-link" type="button" disabled={pending} aria-pressed={showPassword} onClick={() => setShowPassword(!showPassword)}>{showPassword ? 'Şifreyi gizle' : 'Şifreyi göster'}</button>
        <p className="auth-description">Şifre 8–128 karakterdir; boşluk kullanabilirsiniz.</p>
        {field('licenseInfo', 'Mesleki kayıt / belge açıklaması', true)}
        <p className="auth-description">Hasta veya danışan bilgisi paylaşmayın. Açıklama yalnız yetkili Admin incelemesi içindir.</p>
        {message && <p className="form-message error-message" role="alert">{message}</p>}
        <button className="button button-primary form-submit" disabled={pending} type="submit">{pending ? 'Başvuru iletiliyor…' : 'Başvuruyu gönder'}</button>
      </form>}
    <Link className="preview-link" to="/eposta-dogrulama">E-postamı doğrula</Link>
    <Link className="preview-link" to="/giris">Giriş yap</Link>
  </AuthLayout>
}

function ExistingAccountApplication() {
  const [ready, setReady] = useState(false)
  const [profile, setProfile] = useState<DietitianStatusResponse>()
  const [name, setName] = useState('')
  const [license, setLicense] = useState('')
  const [message, setMessage] = useState('')
  const [pending, setPending] = useState(false)
  const operation = useRef<AbortController | null>(null)
  const csrf = useRef<string | null>(null)
  const invalidate = () => { csrf.current = null; setReady(false); setProfile(undefined) }
  async function load() {
    if (operation.current) return
    const controller = new AbortController(); operation.current = controller
    invalidate(); setPending(true); setMessage('')
    try {
      const token = await getCsrf(controller.signal)
      const account = await getAccount(controller.signal)
      if (account.role === 'admin') throw new WebSessionError(403, 'Yönetici hesabıyla diyetisyen başvurusu yapılamaz.')
      let current: DietitianStatusResponse | undefined
      try { current = await getDietitianStatus(controller.signal) }
      catch (error) { if (!(error instanceof WebSessionError && error.status === 404)) throw error }
      if (!controller.signal.aborted) {
        csrf.current = token; setName(account.displayName ?? ''); setProfile(current); setReady(true)
      }
    } catch (error) {
      if (!controller.signal.aborted) setMessage(error instanceof WebSessionError ? error.message : 'Hesap doğrulanamadı.')
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }
  useEffect(() => {
    void load()
    return () => { operation.current?.abort(); operation.current = null; csrf.current = null }
    // Read only on entry or an explicit retry; never keep a session alive by polling.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (operation.current || !csrf.current || !ready || profile) return
    if (!name.trim() || Array.from(name.trim()).length > 120 || !license.trim() || Array.from(license.trim()).length > 2000) {
      setMessage('Ad ve soyad 1–120, mesleki kayıt açıklaması 1–2000 karakter olmalı.'); return
    }
    const controller = new AbortController(); operation.current = controller; setPending(true); setMessage('')
    try {
      const result = await applyExistingDietitian({ displayName: name.trim(), licenseInfo: license.trim() }, csrf.current, controller.signal)
      if (!controller.signal.aborted) { setProfile(result); setLicense('') }
    } catch (error) {
      if (!controller.signal.aborted) {
        if (error instanceof WebSessionError && [400, 401, 403, 409].includes(error.status)) invalidate()
        setMessage(error instanceof WebSessionError ? error.message : 'Başvuru sonucu doğrulanamadı.')
      }
    } finally { if (!controller.signal.aborted) { operation.current = null; setPending(false) } }
  }
  return <section aria-label="Mevcut hesapla diyetisyen başvurusu">
    <p>Mevcut doğrulanmış hesabınız kullanılır. Danışan profiliniz, kayıtlarınız ve ilişkileriniz korunur.</p>
    {pending && <p role="status">Hesap ve başvuru kontrol ediliyor…</p>}
    {message && <p role="alert" className="form-message error-message">{message}</p>}
    {profile && <><p role="status">{profile.isVerified ? 'Diyetisyen başvurunuz onaylanmış. Danışan özellikleriniz de kullanılabilir.' : 'Başvurunuz Admin incelemesini bekliyor. Danışan hesabınızı kullanmaya devam edebilirsiniz.'}</p>
      {profile.isVerified && <Link className="preview-link" to="/calisma-alani">Diyetisyen çalışma alanımı aç</Link>}
      <Link className="preview-link" to="/uzman/basvuru-durumu">Başvuru durumum</Link></>}
    {ready && !profile && <form noValidate aria-label="Mevcut hesap başvuru formu" onSubmit={event => { void submit(event) }}>
      <div className="form-field"><label htmlFor="existing-name">Başvurudaki ad ve soyad</label><input id="existing-name" value={name} disabled={pending} required onChange={event => setName(event.target.value)} /></div>
      <div className="form-field"><label htmlFor="existing-license">Mesleki kayıt açıklamanız</label><textarea id="existing-license" value={license} disabled={pending} required rows={5} onChange={event => setLicense(event.target.value)} /></div>
      <p>Başvuru yetki vermez; diyetisyen işlemleri yalnız Admin onayından sonra açılır. Hasta veya danışan bilgisi paylaşmayın.</p>
      <button className="button button-primary" type="submit" disabled={pending}>Mevcut hesabımla başvuruyu gönder</button>
    </form>}
    {!ready && !pending && <button className="button button-secondary" onClick={() => { void load() }}>Hesap ve başvuruyu yeniden kontrol et</button>}
    <Link className="preview-link" to="/giris">Mevcut hesabımla giriş yap</Link>
  </section>
}
