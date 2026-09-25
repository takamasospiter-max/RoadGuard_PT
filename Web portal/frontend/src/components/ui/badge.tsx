import { cva, type VariantProps } from 'class-variance-authority'
import type { HTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

// Small colored pill used for statuses across the app. The variant names
// mostly match ReportStatus values (see StatusBadge, which maps
// ReportStatus -> these variants), but "resolved" (green) and "neutral"
// (gray) also get reused directly for Active/Inactive account badges on
// the Users & Authorities page, since green-for-active reads the same way.
const badgeVariants = cva(
  'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium',
  {
    variants: {
      variant: {
        neutral: 'bg-app-bg text-text-secondary',
        new: 'bg-accent/10 text-accent',
        verified: 'bg-severity-medium/15 text-severity-medium',
        underRepair: 'bg-severity-medium/15 text-severity-medium',
        resolved: 'bg-success/15 text-success',
      },
    },
    defaultVariants: {
      variant: 'neutral',
    },
  },
)

export interface BadgeProps
  extends HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />
}

export { Badge, badgeVariants }
