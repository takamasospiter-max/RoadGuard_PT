import { useQuery } from '@tanstack/react-query'
import { Bell, ChevronDown, LogOut } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/context/AuthContext'
import { listDefects } from '@/lib/defects'
import { formatRelativeTime } from '@/lib/formatRelativeTime'
import { cn } from '@/lib/utils'
import { formatShortDateTime } from '@/lib/format'


type OpenMenu = 'notifications' | 'account' | null

// Top bar shown above every protected page's content. `title` comes from
// DashboardLayout's pageTitles map; `elevated` toggles the hairline
// shadow that appears once the page below has been scrolled.
export function Header({ title, elevated = false }: { title: string; elevated?: boolean }) {
  const { user, logout } = useAuth()
  // Same queryKey as Dashboard/Map/Reports (src/lib/defects.ts) — TanStack
  // Query dedupes identical concurrent queries, so this doesn't fire a
  // second network request on top of whichever page is currently mounted;
  // it just reads the same cached result.
  const { data: defects = [], dataUpdatedAt } = useQuery({ queryKey: ['defects'], queryFn: listDefects })
  const [openMenu, setOpenMenu] = useState<OpenMenu>(null)

  // formatRelativeTime's output ("5 min ago") only changes with the
  // passage of time, not with any state this component owns — so without
  // this, the label would freeze at whatever it read on the render right
  // after the last data change and never advance. Re-rendering once a
  // minute is enough to keep it honest at "min ago" granularity.
  const [, forceTick] = useState(0)
  useEffect(() => {
    const id = setInterval(() => forceTick((t) => t + 1), 60_000)
    return () => clearInterval(id)
  }, [])

  // Newest few "New" reports, used as the notification bell's contents —
  // there's no real notification backend (SRS FR-NOT-1/2 are Could-priority
  // and unbuilt), so this reuses the same `['defects']` query every other
  // page reads from/writes to, rather than showing nothing.
  const recentNotifications = useMemo(
    () =>
      [...defects]
        .filter((d) => d.status === 'New')
        .sort((a, b) => new Date(b.detectedAt).getTime() - new Date(a.detectedAt).getTime())
        .slice(0, 4),
    [defects],
  )
  // The red "unread" dot hides itself once the bell has been opened at
  // least once this session, rather than being permanently static.
  const [notificationsSeen, setNotificationsSeen] = useState(false)

  const toggleMenu = (menu: OpenMenu) => {
    setOpenMenu((current) => (current === menu ? null : menu))
    if (menu === 'notifications') setNotificationsSeen(true)
  }

  return (
    <header
      className={cn(
        'z-10 flex h-16 shrink-0 items-center justify-between border-b bg-surface px-6 transition-shadow duration-200',
        elevated
          ? 'border-border-light shadow-[0_1px_2px_rgba(16,23,38,0.06)]'
          : 'border-transparent',
      )}
    >
      <h1 className="text-lg font-semibold text-text-primary">{title}</h1>

      <div className="flex items-center gap-4">
        {/* TanStack Query's own `dataUpdatedAt` — the real timestamp of the
            last successful fetch/mutation round-trip, not a locally-tracked
            flag. 0 until the first fetch resolves, so nothing renders until
            there's an actual time to show. */}
        {dataUpdatedAt > 0 && (
          <span className="hidden text-xs text-text-secondary sm:inline">
            Last updated: {formatRelativeTime(new Date(dataUpdatedAt))}
          </span>
        )}

        {/* Notification bell — opens a small dropdown of the newest
            "New"-status reports instead of doing nothing on click. */}
        <div className="relative">
          <button
            type="button"
            onClick={() => toggleMenu('notifications')}
            className="relative flex h-9 w-9 items-center justify-center rounded-full text-text-secondary transition-colors duration-150 hover:bg-app-bg active:scale-95"
            aria-label="Notifications"
            aria-expanded={openMenu === 'notifications'}
          >
            <Bell size={18} />
            {!notificationsSeen && recentNotifications.length > 0 && (
              <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-severity-high" />
            )}
          </button>

          {openMenu === 'notifications' && (
            <div className="absolute right-0 top-full z-50 mt-2 w-80 rounded-xl border border-border-light bg-surface shadow-[0_8px_24px_-4px_rgba(16,23,38,0.16)]">
              <p className="border-b border-border-light px-4 py-3 text-sm font-semibold text-text-primary">
                Notifications
              </p>
              {recentNotifications.length === 0 ? (
                <p className="px-4 py-6 text-center text-sm text-text-secondary">
                  You're all caught up — no new reports.
                </p>
              ) : (
                <ul className="max-h-80 overflow-y-auto">
                  {recentNotifications.map((defect) => (
                    <li key={defect.id} className="border-b border-border-light px-4 py-3 last:border-0">
                      <p className="text-sm text-text-primary">
                        New <span className="font-medium">{defect.hazardType.toLowerCase()}</span> reported on{' '}
                        {defect.road}
                      </p>
                      <p className="mt-0.5 text-xs text-text-secondary">{formatShortDateTime(defect.detectedAt)}</p>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </div>

        {/* Account chip — opens a dropdown with the signed-in user's
            details and a logout action. */}
        <div className="relative">
          <button
            type="button"
            onClick={() => toggleMenu('account')}
            className="flex items-center gap-2 rounded-lg py-1.5 pl-1.5 pr-2.5 transition-colors duration-150 hover:bg-app-bg active:scale-[0.98]"
            aria-expanded={openMenu === 'account'}
          >
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-accent text-[11px] font-semibold text-white">
              {user?.name.slice(0, 1).toUpperCase() ?? 'A'}
            </div>
            <span className="text-sm font-medium text-text-primary">{user?.role ?? 'Admin'}</span>
            <ChevronDown size={14} className="text-text-secondary" />
          </button>

          {openMenu === 'account' && (
            <div className="absolute right-0 top-full z-50 mt-2 w-64 rounded-xl border border-border-light bg-surface p-2 shadow-[0_8px_24px_-4px_rgba(16,23,38,0.16)]">
              <div className="px-2.5 py-2">
                <p className="truncate text-sm font-medium text-text-primary">{user?.name}</p>
                <p className="truncate text-xs text-text-secondary">{user?.email}</p>
              </div>
              <div className="my-1 border-t border-border-light" />
              <Button
                type="button"
                variant="ghost"
                className="w-full justify-start px-2.5 text-severity-high hover:bg-severity-high/10"
                onClick={logout}
              >
                <LogOut size={14} />
                Log out
              </Button>
            </div>
          )}
        </div>
      </div>

      {/* Invisible backdrop — clicking anywhere outside an open dropdown
          closes it, same pattern the slide-over panels use elsewhere. */}
      {openMenu && (
        <div className="fixed inset-0 z-40" onClick={() => setOpenMenu(null)} aria-hidden="true" />
      )}
    </header>
  )
}
