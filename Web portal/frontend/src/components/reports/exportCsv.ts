import type { Defect } from '@/types'
import { sourceLabel } from '@/lib/sourceLabels'

// Declares, in order, which CSV column each header maps to and how to pull
// that value out of a Defect. Editing the export format (add/remove/
// reorder a column) only ever needs a change here.
const columns: { header: string; value: (d: Defect) => string | number }[] = [
  { header: 'Report ID', value: (d) => d.id },
  { header: 'Road', value: (d) => d.road },
  { header: 'Region', value: (d) => d.region },
  { header: 'Type', value: (d) => d.hazardType },
  { header: 'Status', value: (d) => d.status },
  { header: 'Severity', value: (d) => d.severity },
  { header: 'Source', value: (d) => sourceLabel[d.source] },
  { header: 'Detected', value: (d) => d.detectedAt },
  { header: 'Confidence (%)', value: (d) => d.confidence },
  { header: 'Observations', value: (d) => d.observationCount },
  { header: 'Phones', value: (d) => d.deviceCount },
  { header: 'Severity score', value: (d) => (d.severityScore !== undefined ? d.severityScore.toFixed(2) : '') },
  { header: 'Shown to drivers', value: (d) => (d.shownToDrivers ? 'yes' : 'no') },
]

// Wraps a value in quotes (doubling any internal quotes) only if it
// contains a comma, quote, or newline — otherwise a plain unquoted value
// is returned, matching standard CSV escaping rules.
function escapeCsvValue(value: string | number) {
  const str = String(value)
  return /[",\n]/.test(str) ? `"${str.replace(/"/g, '""')}"` : str
}

// Builds a CSV string from `defects` (via `columns` above) and triggers a
// browser download — no server involved. The Blob -> object URL -> hidden
// <a click> -> revoke pattern is the standard way to save a file straight
// from client-side JS.
export function exportDefectsToCsv(defects: Defect[], filename = 'roadguard-reports.csv') {
  const header = columns.map((c) => c.header).join(',')
  const rows = defects.map((d) => columns.map((c) => escapeCsvValue(c.value(d))).join(','))
  const csv = [header, ...rows].join('\n')

  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link) // must be in the DOM for .click() to work in all browsers
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url) // free the blob's memory now that the download has started
}
