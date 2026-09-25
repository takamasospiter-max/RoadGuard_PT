import { cva, type VariantProps } from 'class-variance-authority'
import { forwardRef, type ButtonHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

// Hand-rolled shadcn/ui-style Button (no Radix/shadcn CLI — just the same
// pattern: cva() generates the class-name combinations for each
// variant/size pair, forwardRef so the DOM button element is reachable by
// parents that need it, e.g. for focus management).
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-lg text-sm font-medium transition-[color,background-color,box-shadow,transform] duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 active:scale-[0.98] disabled:pointer-events-none disabled:opacity-50 disabled:active:scale-100',
  {
    variants: {
      variant: {
        default:
          'bg-accent text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.16)] hover:bg-accent-hover active:brightness-95',
        outline:
          'border border-border-light bg-surface text-text-primary hover:bg-app-bg active:bg-border-light/40',
        ghost: 'text-text-primary hover:bg-black/5 active:bg-black/10',
        secondary: 'bg-app-bg text-text-primary hover:bg-black/10 active:bg-black/15',
      },
      size: {
        default: 'h-10 px-4 py-2',
        sm: 'h-8 px-3 text-xs',
        lg: 'h-11 px-6',
        icon: 'h-9 w-9',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  },
)

// Combines the normal <button> HTML attributes with the variant/size
// props cva() knows about, so callers get autocomplete + type-checking for
// both e.g. `onClick` and `variant="outline"`.
export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(buttonVariants({ variant, size }), className)}
        {...props}
      />
    )
  },
)
Button.displayName = 'Button'

export { Button, buttonVariants }
