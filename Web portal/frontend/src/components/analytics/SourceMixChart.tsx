import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardHeader, CardTitle } from '@/components/ui/card'
import { useCountUp } from '@/lib/useCountUp'
import type { Defect } from '@/types'
import { sourceShortLabel } from '@/lib/sourceLabels'

const colorBySource: Record<Defect['source'], string> = {
  device: '#1490E8',
  manual: '#F59E0B',
}

// Shared wording (src/lib/sourceLabels.ts): "Sensors (AI)" / "Traveller".
const labelBySource = sourceShortLabel

// Donut chart of Device vs Manual report counts — the same visual pattern
// as Dashboard's StatusSummaryChart (donut + centered total number). Used
// to be a Pothole-vs-Road-Crack "hazard mix" chart, but the project only
// tracks potholes now, so that split would always be a full circle;
// grouping by source instead keeps this slot genuinely informative.
export function SourceMixChart({ defects }: { defects: Defect[] }) {
  const data = (['device', 'manual'] as const).map((source) => ({
    source,
    count: defects.filter((d) => d.source === source).length,
  }))
  const total = defects.length
  const animatedTotal = useCountUp(total)

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Reports by source</CardTitle>
      </CardHeader>
      <div className="flex items-center gap-6 px-5 pb-5">
        <div className="relative h-40 w-40 shrink-0">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={data}
                dataKey="count"
                nameKey="source"
                innerRadius={48}
                outerRadius={72}
                paddingAngle={2}
                stroke="none"
                animationDuration={800}
                animationEasing="ease-out"
              >
                {data.map((item) => (
                  <Cell key={item.source} fill={colorBySource[item.source]} />
                ))}
              </Pie>
              <Tooltip
                formatter={(value, name) => [`${value} reports`, name]}
                contentStyle={{ borderRadius: 8, borderColor: '#C9CDD3', fontSize: 13 }}
              />
            </PieChart>
          </ResponsiveContainer>
          <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
            <span className="text-2xl font-bold text-text-primary">{animatedTotal}</span>
            <span className="text-[11px] text-text-secondary">reports</span>
          </div>
        </div>

        <ul className="flex-1 space-y-2.5">
          {data.map((item) => (
            <li key={item.source} className="flex items-center justify-between gap-3 text-sm">
              <span className="flex items-center gap-2 text-text-primary">
                <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: colorBySource[item.source] }} />
                {labelBySource[item.source]}
              </span>
              <span className="font-medium tabular-nums text-text-secondary">{item.count}</span>
            </li>
          ))}
        </ul>
      </div>
    </Card>
  )
}
