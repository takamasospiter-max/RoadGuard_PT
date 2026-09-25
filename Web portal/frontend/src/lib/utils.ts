import { type ClassValue, clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

// Standard shadcn/ui-style helper: `clsx` lets you pass conditional class
// names (arrays, objects, `false && '...'`), and `twMerge` then resolves
// any conflicting Tailwind classes (e.g. two different `px-*` values) so
// the later one wins instead of both being applied. Used by every
// component that accepts a `className` prop to override.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
