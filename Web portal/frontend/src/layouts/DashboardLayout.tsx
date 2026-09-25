import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import { Header } from '@/components/layout/Header'
import { Sidebar } from '@/components/layout/Sidebar'

// Each protected route's Header title, keyed by path. The sidebar nav
// label and this title are deliberately different in places (e.g. sidebar
// says "Report & Analysis", this says the same — but Map's sidebar label
// is just "Map" while the header shows the fuller "Road Condition Map").
const pageTitles: Record<string, string> = {
  '/dashboard': 'Road Condition Overview',
  '/map': 'Road Condition Map',
  '/reports': 'Report & Analysis',
  '/users': 'Users & Authorities',
}

// The shared shell every protected page renders inside: fixed Sidebar on
// the left, Header + scrollable content on the right. `<Outlet />` is
// where React Router drops in whichever page matched (see App.tsx).
export function DashboardLayout() {
  const { pathname } = useLocation()
  const title = pageTitles[pathname] ?? 'RoadGuard AI'

  // The header gains a hairline shadow only once content has scrolled
  // beneath it, rather than always showing one — the same toolbar
  // behavior macOS/iOS apps use.
  const [scrolled, setScrolled] = useState(false)

  return (
    <div className="flex h-screen w-full overflow-hidden bg-app-bg">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Header title={title} elevated={scrolled} />
        <main
          onScroll={(e) => setScrolled(e.currentTarget.scrollTop > 0)}
          className="flex-1 overflow-y-auto p-6 lg:p-8"
        >
          <Outlet />
        </main>
      </div>
    </div>
  )
}
