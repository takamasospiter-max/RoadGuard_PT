import type { HTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

interface FadeInProps extends HTMLAttributes<HTMLDivElement> {
  delay?: number
}

// Lightweight entrance animation (no framer-motion dependency) driven by the
// fade-in-up keyframes in index.css. `delay` (ms) lets a group of siblings
// stagger in rather than popping in all at once.
export function FadeIn({ delay = 0, className, style, ...props }: FadeInProps) {
  return (
    <div
      className={cn('animate-[fade-in-up_0.5s_ease-out_both]', className)}
      style={{ animationDelay: `${delay}ms`, ...style }}
      {...props}
    />
  )
}
