import { apiGet, apiPost } from '@/lib/api'
import type { AuthUser } from '@/types'

// The backend's CurrentUser also includes `id`, which AuthUser (the
// frontend's existing shape, used everywhere `useAuth().user` is read)
// doesn't have — dropped here rather than widening AuthUser for a value
// nothing currently reads.
interface CurrentUserResponse {
  id: string
  name: string
  email: string
  role: AuthUser['role']
}

function toAuthUser(res: CurrentUserResponse): AuthUser {
  return { name: res.name, email: res.email, role: res.role }
}

// `pendingToken` proves the password step already passed, without granting
// any access on its own — see new-backend/roadguard/security.py for why it's a
// signed, stateless, 5-minute token rather than a database row.
export async function login(email: string, password: string): Promise<{ pendingToken: string }> {
  const res = await apiPost<{ mfa_required: boolean; pending_token: string }>('/auth/login/', {
    email,
    password,
  })
  return { pendingToken: res.pending_token }
}

export async function verifyMfa(pendingToken: string, code: string): Promise<AuthUser> {
  const res = await apiPost<CurrentUserResponse>('/auth/verify-mfa/', {
    pending_token: pendingToken,
    code,
  })
  return toAuthUser(res)
}

// Called once on app load (see AuthContext) to check whether the session
// cookie from a previous visit is still valid — replaces the old
// sessionStorage read, since the session now lives server-side.
export async function fetchCurrentUser(): Promise<AuthUser | null> {
  try {
    const res = await apiGet<CurrentUserResponse>('/auth/me/')
    return toAuthUser(res)
  } catch {
    return null
  }
}

export async function logout(): Promise<void> {
  await apiPost('/auth/logout/')
}

interface AcceptInviteResponse {
  email: string
  mfa_setup_key: string
  qr_code_data_uri: string
}

// Sets the invitee's own password and generates their MFA secret — the
// Admin who created the account (src/lib/users.ts's inviteUser) never
// touches either. Returns what ActivateAccountPage needs to show the
// enrollment step (QR + manual-entry fallback), same pair the backend's
// scripts/create_admin.py prints for the admin-bootstrapped path.
export async function acceptInvite(
  token: string,
  password: string,
): Promise<{ email: string; mfaSetupKey: string; qrCodeDataUri: string }> {
  const res = await apiPost<AcceptInviteResponse>('/auth/accept-invite/', { token, password })
  return { email: res.email, mfaSetupKey: res.mfa_setup_key, qrCodeDataUri: res.qr_code_data_uri }
}
