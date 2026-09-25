// Shared text formatting for the portal, so every page shows dates and names
// the same way (British English, as used across the app).

// "25 Sep 2026, 14:05" — full date and time (detail panels, popups).
export function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-GB', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

// "25 Sep, 14:05" — without the year, for compact lists (recent reports,
// notifications, detection rows).
export function formatShortDateTime(iso: string) {
  return new Date(iso).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

// "25 Sep 2026" — date only (report table).
export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}

// "Jane Doe" → "JD": the letters shown in user avatars.
export function initials(name: string) {
  return name
    .split(' ')
    .map((part) => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}
