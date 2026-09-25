import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { buildTrendSeries } from '@/components/analytics/trendData'
import { Card, CardHeader, CardTitle } from '@/components/ui/card'
import type { Defect } from '@/types'

// Area chart of "how many reports were detected each day" for the
// Analytics tab. `days` is whichever period the "Last 7/30 days" selector
// is set to; all the actual day-bucketing math lives in trendData.ts.
export function TrendChart({ defects, days }: { defects: Defect[]; days: number }) {
  const data = buildTrendSeries(defects, days)

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Road-condition reporting trend</CardTitle>
      </CardHeader>
      <div className="h-55 px-2 pb-4">
        <ResponsiveContainer width="100%" height="100%">
          {/* key={days} forces the chart to fully remount (and replay its
              entrance animation) when the period selector changes, instead
              of just morphing the existing line into the new shape. */}
          <AreaChart key={days} data={data} margin={{ top: 4, right: 24, left: -12, bottom: 0 }}>
            {/* Fades the area fill from semi-transparent blue at the line
                down to fully transparent, instead of a flat block of color. */}
            <defs>
              <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#1490E8" stopOpacity={0.25} />
                <stop offset="100%" stopColor="#1490E8" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#C9CDD3" vertical={false} />
            <XAxis
              dataKey="label"
              tick={{ fontSize: 11, fill: '#666666' }}
              tickLine={false}
              axisLine={{ stroke: '#C9CDD3' }}
              // At 30 days, showing every single date label would be too
              // cramped — skip most of them (roughly one per week) once
              // the window is longer than ~2 weeks.
              interval={days > 14 ? Math.ceil(days / 7) : 0}
            />
            <YAxis
              allowDecimals={false}
              tick={{ fontSize: 11, fill: '#666666' }}
              tickLine={false}
              axisLine={false}
              width={28}
            />
            <Tooltip
              formatter={(value) => [`${value} reports`, 'Detected']}
              contentStyle={{ borderRadius: 8, borderColor: '#C9CDD3', fontSize: 13 }}
            />
            <Area
              type="monotone"
              dataKey="count"
              stroke="#1490E8"
              strokeWidth={2}
              fill="url(#trendFill)"
              animationDuration={800}
              animationEasing="ease-out"
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </Card>
  )
}
