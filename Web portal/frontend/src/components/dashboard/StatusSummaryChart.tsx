import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { statusColor as colorByStatus } from '@/lib/statusColors'
import { useCountUp } from '@/lib/useCountUp'
import type { StatusSummaryItem } from '@/types'

// Dashboard's donut chart: how many reports are in each status. `data`
// comes from countByStatus() (src/lib/reportStats.ts) — an array of
// {status, count}, one per ReportStatus, so it's always in a fixed order.
// This is the twin of Analytics' LifecycleBreakdown, which shows the same
// underlying counts as horizontal bars instead of a donut.
export function StatusSummaryChart({ data }: { data: StatusSummaryItem[] }) {
  const total = data.reduce((sum, item) => sum + item.count, 0)
  const animatedTotal = useCountUp(total)

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Report Status Summary</CardTitle>
      </CardHeader>
      <CardContent className="flex items-center gap-6 pt-0">
        {/* The chart and the centered "total" label are stacked via
            `relative`/`absolute` — Recharts draws the ring, and the total
            count is a plain overlay positioned in its empty middle. */}
        <div className="relative h-40 w-40 shrink-0">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={data}
                dataKey="count"
                nameKey="status"
                innerRadius={48}
                outerRadius={72}
                paddingAngle={2}
                stroke="none"
                animationDuration={800}
                animationEasing="ease-out"
              >
                {/* One <Cell> per slice so each status gets its own fixed
                    color from statusColors.ts instead of Recharts' default
                    auto-generated palette. */}
                {data.map((item) => (
                  <Cell key={item.status} fill={colorByStatus[item.status]} />
                ))}
              </Pie>
              <Tooltip
                formatter={(value, name) => [`${value} reports`, name]}
                contentStyle={{
                  borderRadius: 8,
                  borderColor: '#C9CDD3',
                  fontSize: 13,
                }}
              />
            </PieChart>
          </ResponsiveContainer>
          <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
            <span className="text-2xl font-bold text-text-primary">{animatedTotal}</span>
            <span className="text-[11px] text-text-secondary">total</span>
          </div>
        </div>

        <ul className="flex-1 space-y-2.5">
          {data.map((item) => (
            <li key={item.status} className="flex items-center justify-between gap-3 text-sm">
              <span className="flex items-center gap-2 text-text-primary">
                <span
                  className="h-2.5 w-2.5 rounded-full"
                  style={{ backgroundColor: colorByStatus[item.status] }}
                />
                {item.status}
              </span>
              <span className="font-medium tabular-nums text-text-secondary">{item.count}</span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}
