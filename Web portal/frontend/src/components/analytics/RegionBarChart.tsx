import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Card, CardHeader, CardTitle } from '@/components/ui/card'
import type { Defect } from '@/types'

// Horizontal bar chart showing report counts per region, sorted
// highest-first so the busiest areas are immediately visible at the top.
export function RegionBarChart({ defects }: { defects: Defect[] }) {
  // Tally counts per region by hand (rather than e.g. lodash groupBy) —
  // simple enough with a Map that a dependency isn't worth it.
  const counts = new Map<string, number>()
  for (const defect of defects) {
    counts.set(defect.region, (counts.get(defect.region) ?? 0) + 1)
  }
  const data = Array.from(counts.entries())
    .map(([region, count]) => ({ region, count }))
    .sort((a, b) => b.count - a.count)

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Reports by region</CardTitle>
      </CardHeader>
      <div className="h-55 px-2 pb-4">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} layout="vertical" margin={{ top: 4, right: 20, left: 4, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#C9CDD3" horizontal={false} />
            <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: '#666666' }} tickLine={false} axisLine={{ stroke: '#C9CDD3' }} />
            <YAxis
              type="category"
              dataKey="region"
              tick={{ fontSize: 12, fill: '#111111' }}
              tickLine={false}
              axisLine={false}
              width={80}
            />
            <Tooltip
              formatter={(value) => [`${value} reports`, 'Count']}
              contentStyle={{ borderRadius: 8, borderColor: '#C9CDD3', fontSize: 13 }}
            />
            <Bar
              dataKey="count"
              radius={[0, 6, 6, 0]}
              barSize={18}
              animationDuration={800}
              animationEasing="ease-out"
            >
              {data.map((entry) => (
                <Cell key={entry.region} fill="#1490E8" />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  )
}
