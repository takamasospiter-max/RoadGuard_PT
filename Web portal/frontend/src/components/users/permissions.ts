import type { UserRole } from '@/types'

export interface Permission {
  label: string
  granted: boolean
}

// Mirrors the SRS §2.3 role table: Admin has full access; TARURA Officer
// can operate on road-condition data but not manage users or the system.
export function permissionsForRole(role: UserRole): Permission[] {
  const shared: Permission[] = [
    { label: 'View dashboard', granted: true },
    { label: 'View map', granted: true },
    { label: 'View reports & analytics', granted: true },
    { label: 'Moderate manual reports / review road-condition records', granted: true },
    { label: 'Generate and export maintenance tickets', granted: true },
  ]

  if (role === 'Admin') {
    return [
      ...shared,
      { label: 'Manage portal users', granted: true },
      { label: 'Manage authorities', granted: true },
      { label: 'Suspend contributor accounts', granted: true },
    ]
  }

  return [
    ...shared,
    { label: 'Manage portal users', granted: false },
    { label: 'Manage authorities', granted: false },
    { label: 'Suspend contributor accounts', granted: false },
  ]
}
