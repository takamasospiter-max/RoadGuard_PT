import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'

// Auth gate: renders its children only if someone is logged in (per
// AuthContext), otherwise redirects to /login. Wraps DashboardLayout in
// App.tsx so all four main pages are protected in one place.
export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()

  // AuthContext's initial /auth/me check is still in flight — render
  // nothing rather than redirecting, otherwise every page refresh would
  // briefly bounce a logged-in user to /login before the request resolves.
  if (loading) {
    return null
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  return <>{children}</>
}
