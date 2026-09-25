import { forwardRef, type InputHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

// Styled <input>. Accepts every normal input prop (value, onChange, type,
// placeholder, ...) via InputHTMLAttributes, so it's a drop-in replacement
// for a raw <input> everywhere in the app (search boxes, forms, etc.).
const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        ref={ref}
        className={cn(
          'flex h-11 w-full rounded-lg border border-border-light bg-surface px-3.5 text-sm text-text-primary placeholder:text-text-secondary transition-[border-color,box-shadow] duration-150 hover:border-text-secondary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:border-accent disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border-light',
          className,
        )}
        {...props}
      />
    )
  },
)
Input.displayName = 'Input'

export { Input }
