import type { ReportSource } from '@/types'

// One place for how a defect's source is named across the portal, so every
// page says the same thing:
// - "device": found by the AI in phones' sensor data (crowd sensing);
// - "manual": a traveller's photo report from the mobile app.
export const sourceLabel: Record<ReportSource, string> = {
  device: 'Phone sensors (AI)',
  manual: 'Traveller report',
}

// Shorter form for tight spaces (table cells, chart legends, summary chips).
export const sourceShortLabel: Record<ReportSource, string> = {
  device: 'Sensors (AI)',
  manual: 'Traveller',
}
