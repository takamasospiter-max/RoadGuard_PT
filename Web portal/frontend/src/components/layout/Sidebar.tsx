import { BarChart3, LayoutGrid, LogOut, Map, PanelLeftClose, PanelLeftOpen, Users } from 'lucide-react'
import { useState } from 'react'
import { NavLink } from 'react-router-dom'
import { useAuth } from '@/context/AuthContext'
import { cn } from '@/lib/utils'
import { initials } from '@/lib/format'

// The four top-level pages. "Users" is flagged adminOnly because, per the
// SRS, only Admins manage portal users/authorities — TARURA Officers never
// see it in the nav (though the route itself isn't guarded, see App.tsx).
const navItems = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutGrid },
  { to: '/map', label: 'Map', icon: Map },
  { to: '/reports', label: 'Report & Analysis', icon: BarChart3 },
  { to: '/users', label: 'Users', icon: Users, adminOnly: true },
]

// "System Administrator" -> "SA", used for the avatar circles.

// Fixed dark-navy left sidebar: branding, nav links, and the signed-in
// user's card + logout at the bottom. Can collapse to icon-only width.
export function Sidebar() {
  const { user, logout } = useAuth()
  const [collapsed, setCollapsed] = useState(false)

  // Hide the Users link entirely for non-Admins rather than disabling it.
  const visibleItems = navItems.filter((item) => !item.adminOnly || user?.role === 'Admin')

  return (
    <aside
      className={cn(
        'flex h-screen flex-col bg-navy text-white transition-[width] duration-200',
        collapsed ? 'w-[76px]' : 'w-64',
      )}
    >
      <div className="flex items-center justify-between gap-2 px-5 py-6">
        {!collapsed && (
          <div className="min-w-0">
            <p className="truncate text-[17px] font-semibold leading-tight">RoadGuard AI</p>
            <p className="truncate text-xs text-white/50">Admin portal</p>
          </div>
        )}
        <button
          type="button"
          onClick={() => setCollapsed((v) => !v)}
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-white/60 transition-colors duration-150 hover:bg-white/10 hover:text-white active:scale-[0.95]"
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          {collapsed ? <PanelLeftOpen size={18} /> : <PanelLeftClose size={18} />}
        </button>
      </div>

      {/* px-3 on the nav container is what makes the active item read as an
          inset "pill" (like macOS Mail/Notes sidebars) rather than a
          full-bleed bar — each link's background never reaches the edges. */}
      <nav className="flex-1 space-y-1 px-3">
        {visibleItems.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            className={({ isActive }) =>
              cn(
                'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-white/70 transition-[background-color,color,transform] duration-150 hover:bg-white/10 hover:text-white active:scale-[0.98]',
                isActive && 'bg-accent text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.16)] hover:bg-accent',
                collapsed && 'justify-center',
              )
            }
          >
            <Icon size={18} className="shrink-0" />
            {!collapsed && <span className="truncate">{label}</span>}
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-white/10 p-3">
        <div className={cn('flex items-center gap-3 rounded-lg px-2 py-2', collapsed && 'justify-center')}>
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent text-xs font-semibold">
            {user ? initials(user.name) : '—'}
          </div>
          {!collapsed && (
            <div className="min-w-0">
              <p className="truncate text-sm font-medium text-white">{user?.name}</p>
              <p className="truncate text-xs text-white/50">{user?.email}</p>
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={logout}
          className={cn(
            'mt-1 flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-white/60 transition-[background-color,color,transform] duration-150 hover:bg-white/10 hover:text-white active:scale-[0.98]',
            collapsed && 'justify-center',
          )}
        >
          <LogOut size={18} className="shrink-0" />
          {!collapsed && <span>Logout</span>}
        </button>
      </div>
    </aside>
  )
}
