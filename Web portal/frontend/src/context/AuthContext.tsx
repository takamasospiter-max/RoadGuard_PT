import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { fetchCurrentUser, logout as logoutRequest } from '@/lib/auth'
import type { AuthUser } from '@/types'

// Real authentication: the session lives server-side (an httpOnly cookie
// the backend set after /auth/verify-mfa succeeded — see
// new-backend/roadguard/auth_views.py), not in sessionStorage. This file no longer
// decides whether anyone is logged in; it just reflects what the backend
// says. LoginPage owns the actual login/verify-mfa calls (via
// src/lib/auth.ts) and hands the resulting user to `login()` below once
// the backend has confirmed it.
interface AuthContextValue {
  user: AuthUser | null
  // True only while the initial /auth/me check (below) is in flight — lets
  // ProtectedRoute wait for the answer instead of redirecting to /login on
  // every refresh before that request has had a chance to come back.
  loading: boolean
  login: (user: AuthUser) => void
  logout: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [loading, setLoading] = useState(true)

  // On first load (including a page refresh), ask the backend whether the
  // session cookie already on hand is still valid — the frontend has no
  // way to know that on its own, since it can't read an httpOnly cookie.
  useEffect(() => {
    fetchCurrentUser()
      .then(setUser)
      .finally(() => setLoading(false))
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      loading,
      login: setUser,
      logout: () => {
        // Clear local state immediately rather than waiting on the
        // network — logging out should feel instant, and there's nothing
        // useful to do differently in the UI if the request happens to
        // fail (the cookie will simply expire on its own regardless).
        setUser(null)
        void logoutRequest()
      },
    }),
    [user, loading],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// Convenience hook every component uses instead of importing AuthContext
// directly. Throws if called outside AuthProvider so a missing provider
// fails loudly at the call site instead of silently returning undefined.
export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider')
  return ctx
}
