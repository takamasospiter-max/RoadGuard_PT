import { cn } from '@/lib/utils'

// Generic over T so callers get type-checked values — e.g. ReportsPage uses
// SegmentedTabs<'reports' | 'analytics'>, UsersPage uses
// SegmentedTabs<'users' | 'authorities'>. This component is intentionally
// dumb: it just renders buttons and calls onChange — the parent owns the
// selected `value` state and decides what to render for each tab.
interface SegmentedTabsProps<T extends string> {
  value: T
  options: { value: T; label: string }[]
  onChange: (value: T) => void
}

// macOS-style segmented control (gray pill container, white "chip" behind
// whichever option is selected). Used for the Reports/Analytics and
// Users/Authorities tab switchers.
export function SegmentedTabs<T extends string>({ value, options, onChange }: SegmentedTabsProps<T>) {
  return (
    <div className="inline-flex items-center gap-1 rounded-lg border border-border-light bg-app-bg p-1">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
          className={cn(
            'rounded-md px-3.5 py-1.5 text-sm font-medium transition-all duration-200 active:scale-[0.97]',
            value === option.value
              ? 'bg-surface text-text-primary shadow-[0_1px_2px_rgba(16,23,38,0.08)]'
              : 'text-text-secondary hover:text-text-primary',
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  )
}
