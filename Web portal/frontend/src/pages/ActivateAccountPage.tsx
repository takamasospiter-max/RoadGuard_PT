import { zodResolver } from '@hookform/resolvers/zod'
import { Eye, EyeOff, ShieldCheck } from 'lucide-react'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { FadeIn } from '@/components/ui/fade-in'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ApiError } from '@/lib/api'
import { acceptInvite } from '@/lib/auth'
import roadHero from '@/images/roadHero.png'

const passwordSchema = z
  .object({
    password: z.string().min(8, 'Use at least 8 characters'),
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Passwords don't match",
    path: ['confirmPassword'],
  })

type PasswordForm = z.infer<typeof passwordSchema>

// The "/activate" route — where an Admin-invited account lands from its
// emailed link (see PortalUserInviteView in new-backend/roadguard/views.py). Public, unlike every
// other page: whoever's here hasn't logged in yet, that's the whole point.
// Two steps: set a password (this is the one and only time this account's
// password is chosen — the Admin who created it never sees it), then
// enroll MFA by scanning the QR the backend hands back.
export function ActivateAccountPage() {
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token')
  const navigate = useNavigate()
  const [step, setStep] = useState<'password' | 'enroll'>('password')
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [enrollment, setEnrollment] = useState<{
    email: string
    mfaSetupKey: string
    qrCodeDataUri: string
  } | null>(null)
  const [showPassword, setShowPassword] = useState(false)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<PasswordForm>({ resolver: zodResolver(passwordSchema) })

  const onSubmit = async (data: PasswordForm) => {
    if (!token) return
    setSubmitError(null)
    try {
      const result = await acceptInvite(token, data.password)
      setEnrollment(result)
      setStep('enroll')
    } catch (err) {
      setSubmitError(err instanceof ApiError ? err.message : 'Something went wrong')
    }
  }

  return (
    <div className="flex min-h-screen w-full">
      <div className="relative hidden w-[38%] shrink-0 overflow-hidden lg:block">
        <img src={roadHero} alt="" className="absolute inset-0 h-full w-full object-cover" />
        <div className="absolute inset-x-0 top-0 h-3/5 bg-linear-to-b from-navy via-navy/70 to-transparent" />
        <FadeIn className="relative flex h-full flex-col items-center px-12 pt-20 text-center">
          <h1 className="text-4xl font-bold text-white">RoadGuard AI</h1>
          <p className="mx-auto mt-4 max-w-xs text-lg text-white/85">
            Admin Portal — AI-Powered Road Condition Monitoring &amp; Traveler Safety Platform
          </p>
        </FadeIn>
      </div>

      <div className="flex flex-1 items-center justify-center bg-surface px-4 py-12">
        <div className="w-full max-w-100">
          <FadeIn>
            <Card className="p-8">
              {!token ? (
                <>
                  <h2 className="mb-1 text-xl font-semibold text-text-primary">Invalid link</h2>
                  <p className="text-sm text-text-secondary">
                    This activation link is missing its token. Ask whoever invited you to send a
                    new one.
                  </p>
                </>
              ) : step === 'password' ? (
                <>
                  <h2 className="mb-1 text-xl font-semibold text-text-primary">Activate your account</h2>
                  <p className="mb-6 text-sm text-text-secondary">Choose a password to get started.</p>

                  <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    <div className="space-y-1.5">
                      <Label htmlFor="password">Password</Label>
                      <div className="relative">
                        <Input
                          id="password"
                          type={showPassword ? 'text' : 'password'}
                          autoComplete="new-password"
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

                    <div className="space-y-1.5">
                      <Label htmlFor="confirm-password">Confirm password</Label>
                      <Input
                        id="confirm-password"
                        type={showPassword ? 'text' : 'password'}
                        autoComplete="new-password"
                        placeholder="••••••••"
                        {...register('confirmPassword')}
                      />
                      {errors.confirmPassword && (
                        <p className="text-xs text-severity-high">{errors.confirmPassword.message}</p>
                      )}
                    </div>

                    {submitError && <p className="text-xs text-severity-high">{submitError}</p>}

                    <Button type="submit" className="w-full" disabled={isSubmitting}>
                      Continue
                    </Button>
                  </form>
                </>
              ) : (
                enrollment && (
                  <>
                    <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-full bg-accent/10 text-accent">
                      <ShieldCheck size={22} />
                    </div>
                    <h2 className="mb-1 text-xl font-semibold text-text-primary">Set up two-factor login</h2>
                    <p className="mb-4 text-sm text-text-secondary">
                      Scan this with an authenticator app (or enter the key manually), then sign in
                      as <span className="font-medium text-text-primary">{enrollment.email}</span>.
                    </p>

                    <img
                      src={enrollment.qrCodeDataUri}
                      alt="MFA setup QR code"
                      className="mx-auto mb-4 h-48 w-48 rounded-lg border border-border-light"
                    />

                    <p className="mb-6 break-all rounded-lg bg-app-bg/60 px-3 py-2.5 text-center font-mono text-xs text-text-secondary">
                      {enrollment.mfaSetupKey}
                    </p>

                    <Button type="button" className="w-full" onClick={() => navigate('/login', { replace: true })}>
                      Continue to sign in
                    </Button>
                  </>
                )
              )}
            </Card>
          </FadeIn>
        </div>
      </div>
    </div>
  )
}
