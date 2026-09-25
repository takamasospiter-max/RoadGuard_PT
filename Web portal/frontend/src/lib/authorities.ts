import { apiGet, apiPatch, apiPost } from '@/lib/api'
import type { Authority } from '@/types'

// Matches new-backend/roadguard/serializers.py's AuthoritySerializer field-for-field.
interface AuthorityOutResponse {
  id: string
  name: string
  coverage_area: string
  contact: string
  status: Authority['status']
}

function toAuthority(res: AuthorityOutResponse): Authority {
  return { id: res.id, name: res.name, coverageArea: res.coverage_area, contact: res.contact, status: res.status }
}

export async function listAuthorities(): Promise<Authority[]> {
  const res = await apiGet<AuthorityOutResponse[]>('/authorities/')
  return res.map(toAuthority)
}

export async function createAuthority(input: {
  name: string
  coverageArea: string
  contact: string
}): Promise<Authority> {
  const res = await apiPost<AuthorityOutResponse>('/authorities/', {
    name: input.name,
    coverage_area: input.coverageArea,
    contact: input.contact,
  })
  return toAuthority(res)
}

export async function updateAuthority(
  id: string,
  patch: Partial<{ name: string; coverageArea: string; contact: string; status: Authority['status'] }>,
): Promise<Authority> {
  const res = await apiPatch<AuthorityOutResponse>(`/authorities/${id}/`, {
    ...(patch.name !== undefined && { name: patch.name }),
    ...(patch.coverageArea !== undefined && { coverage_area: patch.coverageArea }),
    ...(patch.contact !== undefined && { contact: patch.contact }),
    ...(patch.status !== undefined && { status: patch.status }),
  })
  return toAuthority(res)
}
