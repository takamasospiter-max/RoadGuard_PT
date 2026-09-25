import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import { useCountUp } from '@/lib/useCountUp'

// The single "big number in a card" building block reused across the app:
// Dashboard's five overview cards, Analytics' four summary cards, and
// Users' four summary cards all render as a grid of these. `accent` draws
// the blue border used for the "primary" card in each group (Total
// reports / Total Reports / Total Users). The number itself animates via
// useCountUp rather than just displaying `value` directly.
export function StatCard({
  label,
  value,
  accent = false,
  className,
}: {
  label: string
  value: number
  accent?: boolean
  className?: string
}) {
  const animatedValue = useCountUp(value)

  return (
    <Card
      className={cn(
        'flex flex-col items-center justify-center gap-2 px-4 py-6 text-center transition-shadow hover:shadow-md',
        accent && 'border-2 border-accent',
        className,
      )}
    >
      <p className="text-[13px] font-medium text-text-secondary">{label}</p>
      <p className="text-3xl font-bold tabular-nums text-text-primary">{animatedValue}</p>
    </Card>
  )
}
