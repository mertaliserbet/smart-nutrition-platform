import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { AuthLayout } from '../auth/AuthLayout'
import { WebSessionError } from '../auth/webSessionApi'
import { applyDietitian } from './dietitianApi'
import type { DietitianApplicationRequest } from './dietitianApi'
import './dietitians.css'

const initial: DietitianApplicationRequest = { displayName: '', email: '', password: '', licenseInfo: '' }
export function DietitianApplicationPage() {
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
    {submitted ? <p className="form-message" role="status">Başvurunuz kaydedildi. E-postanızı doğrulayın; ardından giriş yaparak Admin onay durumunu takip edebilirsiniz.</p> :
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
