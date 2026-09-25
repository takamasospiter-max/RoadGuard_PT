import { X } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { cn } from '@/lib/utils'
import type { AccountStatus, Authority } from '@/types'

interface AuthorityFormDrawerProps {
  open: boolean
  // null = "Add Authority" mode; a real Authority = "Edit" mode, pre-filled
  // with its current values.
  authority: Authority | null
  onClose: () => void
  // `id` is optional because a brand-new authority doesn't have one yet —
  // AuthoritiesTab assigns it when `authority.id` is undefined.
  onSave: (authority: Omit<Authority, 'id'> & { id?: string }) => void
}

// One slide-over that handles both creating and editing an Authority — see
// AuthorityForm below for how `authority` being null vs. set changes what
// it renders.
export function AuthorityFormDrawer({ open, authority, onClose, onSave }: AuthorityFormDrawerProps) {
  return (
    <>
      <div
        className={cn(
          'fixed inset-0 z-[1200] bg-black/20 backdrop-blur-[2px] transition-opacity duration-200',
          open ? 'opacity-100' : 'pointer-events-none opacity-0',
        )}
        onClick={onClose}
        aria-hidden="true"
      />
      <aside
        className={cn(
          'fixed right-0 top-0 z-[1300] h-screen w-full max-w-sm overflow-y-auto border-l border-border-light bg-surface shadow-xl transition-transform duration-300 ease-out',
          open ? 'translate-x-0' : 'translate-x-full',
        )}
      >
        {/* Keyed by the authority's id (or 'new') so switching between
            editing different authorities — or from editing to adding —
            remounts the form with fresh field values instead of carrying
            over whatever was previously typed. */}
        {open && (
          <AuthorityForm key={authority?.id ?? 'new'} authority={authority} onClose={onClose} onSave={onSave} />
        )}
      </aside>
    </>
  )
}

function AuthorityForm({
  authority,
  onClose,
  onSave,
}: {
  authority: Authority | null
  onClose: () => void
  onSave: (authority: Omit<Authority, 'id'> & { id?: string }) => void
}) {
  const [name, setName] = useState(authority?.name ?? '')
  const [coverageArea, setCoverageArea] = useState(authority?.coverageArea ?? '')
  const [contact, setContact] = useState(authority?.contact ?? '')
  const [status, setStatus] = useState<AccountStatus>(authority?.status ?? 'Active')

  const canSubmit = name.trim() !== ''

  return (
    <div className="flex flex-col gap-5 p-6">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Access Management</p>
          <h2 className="mt-1 text-lg font-semibold text-text-primary">
            {authority ? 'Edit Authority' : 'Add Authority'}
          </h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="flex h-8 w-8 items-center justify-center rounded-lg text-text-secondary transition-colors duration-150 hover:bg-app-bg active:scale-90"
          aria-label="Close"
        >
          <X size={18} />
        </button>
      </div>

      <div className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="authority-name">Authority name</Label>
          <Input id="authority-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. TARURA" />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="authority-area">Coverage area</Label>
          <Input
            id="authority-area"
            value={coverageArea}
            onChange={(e) => setCoverageArea(e.target.value)}
            placeholder="e.g. Arusha Region"
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="authority-contact">Contact information</Label>
          <Input
            id="authority-contact"
            value={contact}
            onChange={(e) => setContact(e.target.value)}
            placeholder="ops@authority.go.tz"
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="authority-status">Status</Label>
          <Select id="authority-status" value={status} onChange={(e) => setStatus(e.target.value as AccountStatus)}>
            <option value="Active">Active</option>
            <option value="Inactive">Inactive</option>
          </Select>
        </div>
      </div>

      <div className="flex gap-2 border-t border-border-light pt-4">
        <Button type="button" variant="outline" className="flex-1" onClick={onClose}>
          Cancel
        </Button>
        <Button
          type="button"
          className="flex-1"
          disabled={!canSubmit}
          onClick={() => {
            onSave({ id: authority?.id, name: name.trim(), coverageArea: coverageArea.trim(), contact: contact.trim(), status })
            onClose()
          }}
        >
          {authority ? 'Save Changes' : 'Create Authority'}
        </Button>
      </div>
    </div>
  )
}
