import { Link } from 'react-router-dom'
import { StatusBadge } from '@/components/dashboard/StatusBadge'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { Defect } from '@/types'
import { formatShortDateTime } from '@/lib/format'


// Dashboard's compact preview table — the full sortable/filterable/
// paginated version lives on the Report & Analysis page (ReportTable).
// This one just takes the whole `defects` array and does its own
// newest-first sort + top-5 slice, so it always shows the latest reports
// regardless of what order the caller's data happens to be in.
export function RecentReportsTable({ reports }: { reports: Defect[] }) {
  const recent = [...reports] // copy first — .sort() mutates in place
    .sort((a, b) => new Date(b.detectedAt).getTime() - new Date(a.detectedAt).getTime())
    .slice(0, 5)

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <CardTitle className="text-base">Recent Reports</CardTitle>
        <Link to="/reports" className={buttonVariants({ variant: 'outline', size: 'sm' })}>
          View All Reports
        </Link>
      </CardHeader>
      <CardContent className="p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-y border-border-light text-left text-xs font-medium text-text-secondary">
              <th className="px-5 py-2.5 font-medium">Report ID</th>
              <th className="px-5 py-2.5 font-medium">Road</th>
              <th className="px-5 py-2.5 font-medium">Type</th>
              <th className="px-5 py-2.5 font-medium">Status</th>
              <th className="px-5 py-2.5 font-medium">Detected</th>
            </tr>
          </thead>
          <tbody>
            {recent.map((report) => (
              <tr
                key={report.id}
                className="border-b border-border-light transition-colors duration-150 last:border-0 hover:bg-app-bg/50"
              >
                <td className="px-5 py-3 font-medium text-text-primary">{report.id}</td>
                <td className="px-5 py-3 text-text-primary">{report.road}</td>
                <td className="px-5 py-3 text-text-secondary">{report.hazardType}</td>
                <td className="px-5 py-3">
                  <StatusBadge status={report.status} />
                </td>
                <td className="px-5 py-3 text-text-secondary">{formatShortDateTime(report.detectedAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}
