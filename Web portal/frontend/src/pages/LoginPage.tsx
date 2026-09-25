import { zodResolver } from '@hookform/resolvers/zod'
import { Eye, EyeOff, ShieldCheck } from 'lucide-react'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useNavigate } from 'react-router-dom'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { FadeIn } from '@/components/ui/fade-in'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useAuth } from '@/context/AuthContext'
import roadHero from '@/images/roadHero.png'
import { ApiError } from '@/lib/api'
import { login as loginRequest, verifyMfa } from '@/lib/auth'

// Validation rules for the credentials step, checked by react-hook-form
// via the zodResolver below before onCredentialsSubmit ever runs.
const credentialsSchema = z.object({
  email: z.string().email('Enter a valid email address'),
  password: z.string().min(1, 'Password is required'),
})

// TypeScript type inferred straight from the schema above, so the form's
// fields and the validation rules can never drift out of sync.
type CredentialsForm = z.infer<typeof credentialsSchema>

// The "/login" route — a two-step flow: credentials, then a 6-digit MFA
// code (per SRS FR-AUTH-1/2), both now checked for real by the backend
// (see src/lib/auth.ts). Role is no longer picked here — it's whatever the
// backend says the account's role actually is, returned once MFA succeeds.
export function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [step, setStep] = useState<'credentials' | 'mfa'>('credentials')
  const [email, setEmail] = useState('')
  const [pendingToken, setPendingToken] = useState<string | null>(null)
  const [credentialsError, setCredentialsError] = useState<string | null>(null)
  const [code, setCode] = useState('')
  const [mfaError, setMfaError] = useState<string | null>(null)
  const [showPassword, setShowPassword] = useState(false)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<CredentialsForm>({ resolver: zodResolver(credentialsSchema) })

  const onCredentialsSubmit = async (data: CredentialsForm) => {
    setCredentialsError(null)
    try {
      const { pendingToken: token } = await loginRequest(data.email, data.password)
      setEmail(data.email)
      setPendingToken(token)
      setStep('mfa')
    } catch (err) {
      setCredentialsError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  const onMfaSubmit = async () => {
    if (!/^\d{6}$/.test(code)) {
      setMfaError('Enter the 6-digit code from your authenticator app')
      return
    }
    if (!pendingToken) return

    try {
      const user = await verifyMfa(pendingToken, code)
      login(user)
      navigate('/dashboard', { replace: true })
    } catch (err) {
      setMfaError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  return (
    <div className="flex min-h-screen w-full">
      {/* Branded hero panel — hidden below lg since there's no room for a
          side-by-side split on narrow screens; the form just centers in
          the full viewport width instead. */}
      <div className="relative hidden w-[38%] shrink-0 overflow-hidden lg:block">
        <img src={roadHero} alt="" className="absolute inset-0 h-full w-full object-cover" />
        {/* Fades from solid navy at the top down to the photo, so the
            white brand text stays readable no matter what's underneath. */}
        <div className="absolute inset-x-0 top-0 h-3/5 bg-linear-to-b from-navy via-navy/70 to-transparent" />
        <FadeIn className="relative flex h-full flex-col items-center px-12 pt-20 text-center">
          <h1 className="text-4xl font-bold text-white">RoadGuard AI</h1>
          <p className="mx-auto mt-4 max-w-xs text-lg text-white/85">
            Admin Portal — AI-Powered Road Condition Monitoring &amp; Traveler Safety Platform
          </p>
        </FadeIn>
      </div>

      {/* Sign-in form panel */}
      <div className="flex flex-1 items-center justify-center bg-surface px-4 py-12">
        <div className="w-full max-w-100">
          <FadeIn>
            <Card className="p-8">
              {step === 'credentials' ? (
                <>
                  <h2 className="mb-1 text-xl font-semibold text-text-primary">Sign in</h2>
                  <p className="mb-6 text-sm text-text-secondary">
                    Use your portal account to continue.
                  </p>

                  <form onSubmit={handleSubmit(onCredentialsSubmit)} className="space-y-4">
                    <div className="space-y-1.5">
                      <Label htmlFor="email">Email</Label>
                      <Input
                        id="email"
                        type="email"
                        autoComplete="username"
                        placeholder="you@roadguard.ai"
                        {...register('email')}
                      />
                      {errors.email && (
                        <p className="text-xs text-severity-high">{errors.email.message}</p>
                      )}
                    </div>

                    <div className="space-y-1.5">
                      <Label htmlFor="password">Password</Label>
                      <div className="relative">
                        <Input
                          id="password"
                          type={showPassword ? 'text' : 'password'}
                          autoComplete="current-password"
                          placeholder="••••••••"
                          className="pr-10"
                          {...register('password')}
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword((v) => !v)}
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-text-secondary transition-colors duration-150 hover:text-text-primary"
                          aria-label={showPassword ? 'Hide password' : 'Show password'}
                        >
                          {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                        </button>
                      </div>
                      {errors.password && (
                        <p className="text-xs text-severity-high">{errors.password.message}</p>
                      )}
                    </div>

                    {credentialsError && (
                      <p className="text-xs text-severity-high">{credentialsError}</p>
                    )}

                    <div className="flex items-center justify-between pt-1">
                      <button
                        type="button"
                        className="text-xs font-medium text-accent transition-transform duration-150 hover:underline active:scale-95"
                      >
                        Forgot password?
                      </button>
                    </div>

                    <Button type="submit" className="w-full" disabled={isSubmitting}>
                      Continue
                    </Button>
                  </form>
                </>
              ) : (
                <>
                  <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-full bg-accent/10 text-accent">
                    <ShieldCheck size={22} />
                  </div>
                  <h2 className="mb-1 text-xl font-semibold text-text-primary">
                    Two-factor verification
                  </h2>
                  <p className="mb-6 text-sm text-text-secondary">
                    Enter the 6-digit code from your authenticator app for{' '}
                    <span className="font-medium text-text-primary">{email}</span>.
                  </p>

                  <div className="space-y-4">
                    <div className="space-y-1.5">
                      <Label htmlFor="mfa-code">Authentication code</Label>
                      <Input
                        id="mfa-code"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="123456"
                        value={code}
                        onChange={(e) => {
                          setCode(e.target.value.replace(/\D/g, '').slice(0, 6))
                          setMfaError(null)
                        }}
                        className="tracking-[0.5em] text-center text-lg"
                      />
                      {mfaError && <p className="text-xs text-severity-high">{mfaError}</p>}
                    </div>

                    <Button type="button" className="w-full" onClick={onMfaSubmit}>
                      Verify and sign in
                    </Button>
                    <button
                      type="button"
                      onClick={() => setStep('credentials')}
                      className="w-full text-center text-xs font-medium text-text-secondary transition-colors duration-150 hover:text-text-primary"
                    >
                      Back
                    </button>
                  </div>
                </>
              )}
            </Card>
          </FadeIn>
        </div>
      </div>
    </div>
  )
}
