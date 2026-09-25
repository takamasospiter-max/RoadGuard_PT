import { ChevronDown } from 'lucide-react'
import { forwardRef, type SelectHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

// Styled native <select> (not a custom dropdown/listbox component) — using
// the real element keeps keyboard/accessibility behavior for free. The
// wrapping <div> is only there to position the decorative chevron icon;
// `appearance-none` on the <select> hides the browser's own arrow so ours
// doesn't double up. `pointer-events-none` on the chevron lets clicks pass
// through to the <select> underneath it.
const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(
  ({ className, children, ...props }, ref) => {
    return (
      <div className="relative">
        <select
          ref={ref}
          className={cn(
            'flex h-10 w-full appearance-none rounded-lg border border-border-light bg-surface pl-3.5 pr-9 text-sm font-medium text-text-primary transition-[border-color,box-shadow] duration-150 hover:border-text-secondary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:border-accent disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border-light',
            className,
          )}
          {...props}
        >
          {children}
        </select>
        <ChevronDown
          size={14}
          className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-text-secondary"
        />
      </div>
    )
  },
)
Select.displayName = 'Select'

export { Select }
