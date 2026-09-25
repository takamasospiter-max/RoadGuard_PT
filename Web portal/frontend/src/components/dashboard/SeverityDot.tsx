import { cn } from '@/lib/utils'
import type { Severity } from '@/types'

const colorBySeverity: Record<Severity, string> = {
  high: 'bg-severity-high',
  medium: 'bg-severity-medium',
  low: 'bg-severity-low',
}

export function SeverityDot({ severity, className }: { severity: Severity; className?: string }) {
  return <span className={cn('inline-block h-2 w-2 rounded-full', colorBySeverity[severity], className)} />
}
