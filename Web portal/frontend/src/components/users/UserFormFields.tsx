import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import type { AccountStatus, UserRole } from '@/types'

// The editable fields of a PortalUser (everything except id/lastActiveAt/
// createdAt, which aren't user-editable). Shared shape used by both
// AddUserDrawer's create form and UserPanel's edit form.
export interface UserFormValues {
  name: string
  email: string
  phone: string
  role: UserRole
  authority: string
  status: AccountStatus
}

interface UserFormFieldsProps {
  values: UserFormValues
  // List of real authority names (e.g. ["TARURA"]) for the authority
  // dropdown's options when role is TARURA Officer.
  authorities: string[]
  onChange: (patch: Partial<UserFormValues>) => void
  // Hidden on AddUserDrawer's create form — a new account's status isn't
  // the Admin's choice, it starts "Inactive" until the invitee activates
  // it themselves (see src/lib/users.ts). Shown (default) on UserPanel's
  // edit form, where deactivating/reactivating an existing user is a real
  // Admin action.
  showStatus?: boolean
}

// Fully controlled form body (no internal state) — reused by both
// AddUserDrawer and UserPanel's edit mode so the two forms can never drift
// out of sync with each other.
export function UserFormFields({ values, authorities, onChange, showStatus = true }: UserFormFieldsProps) {
  return (
    <div className="space-y-4">
      <div className="space-y-1.5">
        <Label htmlFor="user-name">Full name</Label>
        <Input
          id="user-name"
          value={values.name}
          onChange={(e) => onChange({ name: e.target.value })}
          placeholder="e.g. John Michael"
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="user-email">Email</Label>
        <Input
          id="user-email"
          type="email"
          value={values.email}
          onChange={(e) => onChange({ email: e.target.value })}
          placeholder="name@tarura.go.tz"
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="user-role">Role</Label>
        {/* Changing role also fixes up `authority`: Admins are always
            "System" (they're not tied to a road authority), and switching
            *away* from Admin picks the first real authority instead of
            leaving the stale "System" value behind. Switching between
            authorities while already a TARURA Officer keeps whatever was
            selected. */}
        <Select
          id="user-role"
          value={values.role}
          onChange={(e) => {
            const role = e.target.value as UserRole
            onChange({ role, authority: role === 'Admin' ? 'System' : (values.authority === 'System' ? authorities[0] ?? '' : values.authority) })
          }}
        >
          <option value="TARURA Officer">Road Authority Officer</option>
          <option value="Admin">System Administrator</option>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="user-authority">Road authority</Label>
        <Select
          id="user-authority"
          value={values.authority}
          disabled={values.role === 'Admin'}
          onChange={(e) => onChange({ authority: e.target.value })}
        >
          {values.role === 'Admin' ? (
            <option value="System">System</option>
          ) : (
            authorities.map((authority) => (
              <option key={authority} value={authority}>
                {authority}
              </option>
            ))
          )}
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="user-phone">Phone number</Label>
        <Input
          id="user-phone"
          value={values.phone}
          onChange={(e) => onChange({ phone: e.target.value })}
          placeholder="+255 7XX XXX XXX"
        />
      </div>

      {showStatus && (
        <div className="space-y-1.5">
          <Label htmlFor="user-status">Status</Label>
          <Select
            id="user-status"
            value={values.status}
            onChange={(e) => onChange({ status: e.target.value as AccountStatus })}
          >
            <option value="Active">Active</option>
            <option value="Inactive">Inactive</option>
          </Select>
        </div>
      )}
    </div>
  )
}
