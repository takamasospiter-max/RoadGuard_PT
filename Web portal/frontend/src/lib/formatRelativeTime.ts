// "Just now" / "5 min ago" / "3 hr ago" / "2d ago" style formatting for a
// past Date, relative to right now. Used by Header's "Last updated" label
// — deliberately coarse-grained (no seconds) since sub-minute precision
// isn't meaningful for "when did this data last change".
export function formatRelativeTime(date: Date): string {
  const diffSec = Math.round((Date.now() - date.getTime()) / 1000)

  if (diffSec < 30) return 'Just now'

  const diffMin = Math.round(diffSec / 60)
  if (diffMin < 60) return `${diffMin} min ago`

  const diffHr = Math.round(diffMin / 60)
  if (diffHr < 24) return `${diffHr} hr ago`

  const diffDay = Math.round(diffHr / 24)
  return `${diffDay}d ago`
}
