import { useEffect, useRef, useState } from 'react'

// Standard "ease-out" curve: starts fast, slows down toward the end.
// t goes from 0 (start) to 1 (end); returns the eased progress, also 0-1.
function easeOutQuad(t: number) {
  return 1 - (1 - t) * (1 - t)
}

// Animates a displayed number from its previous value to `target` whenever
// `target` changes (including the initial mount, animating up from 0).
// Used by StatCard so every big number in the app (Dashboard cards,
// Analytics summary cards, donut-chart totals) counts up instead of
// snapping straight to its final value.
export function useCountUp(target: number, duration = 700) {
  // `value` is what gets rendered each frame; `fromRef` remembers where the
  // last animation left off, so a second change (e.g. filters narrowing the
  // count from 14 to 5) animates from 14, not from 0 again.
  const [value, setValue] = useState(0)
  const fromRef = useRef(0)

  useEffect(() => {
    const from = fromRef.current
    const delta = target - from
    if (delta === 0) return // nothing to animate

    let frame: number
    const start = performance.now()

    // requestAnimationFrame loop: each browser repaint, work out how far
    // through the animation we are (0-1), ease it, and set the in-between
    // value. Keeps scheduling itself until progress reaches 1.
    const tick = (now: number) => {
      const elapsed = now - start
      const progress = Math.min(1, elapsed / duration)
      const eased = easeOutQuad(progress)
      setValue(Math.round(from + delta * eased))

      if (progress < 1) {
        frame = requestAnimationFrame(tick)
      } else {
        fromRef.current = target // remember the resting value for next time
      }
    }

    frame = requestAnimationFrame(tick)
    // Cleanup: if `target` changes again (or the component unmounts) before
    // the animation finishes, cancel the in-flight frame so it doesn't keep
    // ticking against a stale `from`/`delta`.
    return () => cancelAnimationFrame(frame)
  }, [target, duration])

  return value
}
