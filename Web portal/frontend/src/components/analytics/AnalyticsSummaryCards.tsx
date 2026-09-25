import { StatCard } from '@/components/dashboard/StatCard'
import { FadeIn } from '@/components/ui/fade-in'
import type { Defect } from '@/types'

// The four cards at the top of the Analytics tab (reusing Dashboard's
// StatCard for visual consistency between the two pages). Each one fades
// in with a slightly later delay than the last (index * 60ms), producing
// the left-to-right "stagger" effect.
//
// Split by source (Device/Manual) rather than hazard type — the project
// only tracks potholes now, so a "Potholes" card would just repeat "Total
// Reports" and a "Road Cracks" card would always read 0.
export function AnalyticsSummaryCards({ defects }: { defects: Defect[] }) {
  const device = defects.filter((d) => d.source === 'device').length
  const manual = defects.filter((d) => d.source === 'manual').length
  const unresolved = defects.filter((d) => d.status !== 'Resolved').length

  const cards = [
    { label: 'Total Reports', value: defects.length, accent: true },
    { label: 'Device Reports', value: device, accent: false },
    { label: 'Manual Reports', value: manual, accent: false },
    { label: 'Unresolved', value: unresolved, accent: false },
  ]

  return (
    <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
      {cards.map((card, index) => (
        <FadeIn key={card.label} delay={index * 60}>
          <StatCard label={card.label} value={card.value} accent={card.accent} />
        </FadeIn>
      ))}
    </div>
  )
}
