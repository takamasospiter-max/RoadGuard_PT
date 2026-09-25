import { apiGet, apiPatch, apiPost } from '@/lib/api'
import type { PortalUser } from '@/types'

// Matches new-backend/roadguard/serializers.py's PortalUserSerializer
// field-for-field (snake_case, as DRF sends it) before mapping to the
// frontend's camelCase PortalUser shape below.
interface PortalUserOutResponse {
  id: string
  name: string
  email: string
  phone: string | null
  role: PortalUser['role']
  authority: string
  status: PortalUser['status']
  last_active_at: string
  created_at: string
}

function toPortalUser(res: PortalUserOutResponse): PortalUser {
  return {
    id: res.id,
    name: res.name,
    email: res.email,
    phone: res.phone ?? undefined,
    role: res.role,
    authority: res.authority,
    status: res.status,
    lastActiveAt: res.last_active_at,
    createdAt: res.created_at,
  }
}

// Creates the account (status starts "Inactive") and emails the invitee an
// activation link — see PortalUserInviteView in new-backend/roadguard/views.py.
// There's no password field here because the Admin never sets one
// (SRS FR-USR-2); the invitee does, via the /activate link, see
// src/pages/ActivateAccountPage.tsx.
export async function inviteUser(input: {
  name: string
  email: string
  phone?: string
  role: PortalUser['role']
  authority: string
}): Promise<PortalUser> {
  const res = await apiPost<PortalUserOutResponse>('/users/invite/', input)
  return toPortalUser(res)
}

export async function listUsers(): Promise<PortalUser[]> {
  const res = await apiGet<PortalUserOutResponse[]>('/users/')
  return res.map(toPortalUser)
}

// Partial update — only the fields present in `patch` are sent, and only
// those get changed server-side (DRF partial update — see DetailView.patch
// in new-backend/roadguard/views.py). Covers both UserPanel's edit
// form and the deactivate/reactivate toggle, which just sends `{ status }`.
export async function updateUser(
  id: string,
  patch: Partial<Pick<PortalUser, 'name' | 'email' | 'phone' | 'role' | 'authority' | 'status'>>,
): Promise<PortalUser> {
  const res = await apiPatch<PortalUserOutResponse>(`/users/${id}/`, patch)
  return toPortalUser(res)
}
