import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { AuthoritiesTab } from '@/components/authorities/AuthoritiesTab'
import { UsersTab } from '@/components/users/UsersTab'
import { SegmentedTabs } from '@/components/ui/segmented-tabs'
import { listAuthorities } from '@/lib/authorities'
import { listUsers } from '@/lib/users'

type Tab = 'users' | 'authorities'

// The "/users" route ("Users & Authorities" in the sidebar). Owns which
// tab is active. Reads/writes the real backend via TanStack Query, same
// as Dashboard/Map/Reports now do for defects (see new-backend/roadguard/views.py,
// PortalUserListView and AuthorityListView).
export function UsersPage() {
  const [tab, setTab] = useState<Tab>('users')
  const queryClient = useQueryClient()

  const usersQuery = useQuery({ queryKey: ['users'], queryFn: listUsers })
  const authoritiesQuery = useQuery({ queryKey: ['authorities'], queryFn: listAuthorities })

  if (usersQuery.isPending || authoritiesQuery.isPending) {
    return <p className="p-6 text-sm text-text-secondary">Loading…</p>
  }

  if (usersQuery.isError || authoritiesQuery.isError) {
    return (
      <p className="p-6 text-sm text-severity-high">
        Couldn't load users &amp; authorities. Try refreshing the page.
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-4">
      <SegmentedTabs
        value={tab}
        onChange={setTab}
        options={[
          { value: 'users', label: 'Users' },
          { value: 'authorities', label: 'Authorities' },
        ]}
      />

      {tab === 'users' ? (
        <UsersTab
          users={usersQuery.data}
          authorities={authoritiesQuery.data}
          onRefetch={() => queryClient.invalidateQueries({ queryKey: ['users'] })}
        />
      ) : (
        <AuthoritiesTab
          authorities={authoritiesQuery.data}
          users={usersQuery.data}
          onRefetch={() => queryClient.invalidateQueries({ queryKey: ['authorities'] })}
        />
      )}
    </div>
  )
}
