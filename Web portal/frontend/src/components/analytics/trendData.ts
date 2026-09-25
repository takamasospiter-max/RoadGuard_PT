import type { Defect } from '@/types'

// One point on the trend chart: a day, its chart-axis label, and how many
// reports were detected that day.
export interface TrendPoint {
  date: string
  label: string
  count: number
}

// Turns the raw defect list into a day-by-day series covering the last
// `days` days (e.g. 7 or 30), including days with zero reports — without
// this, a quiet day would just be missing from the chart instead of
// showing as a dip to 0.
export function buildTrendSeries(defects: Defect[], days: number): TrendPoint[] {
  const today = new Date()
  today.setHours(0, 0, 0, 0) // normalize to midnight so date math below is exact

  // Step 1: seed a bucket for every day in the window, oldest first, all
  // starting at 0. Map keys are 'YYYY-MM-DD' strings.
  const buckets = new Map<string, number>()
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today)
    d.setDate(d.getDate() - i)
    buckets.set(d.toISOString().slice(0, 10), 0)
  }

  // Step 2: walk every defect once and increment its day's bucket, if that
  // day falls inside the window (older detections are simply ignored).
  for (const defect of defects) {
    const key = defect.detectedAt.slice(0, 10) // 'YYYY-MM-DDTHH:mm:ss' -> 'YYYY-MM-DD'
    if (buckets.has(key)) {
      buckets.set(key, (buckets.get(key) ?? 0) + 1)
    }
  }

  // Step 3: turn the map into the array shape Recharts wants, formatting
  // each date into a short display label ("18 Sep") along the way.
  return Array.from(buckets.entries()).map(([date, count]) => ({
    date,
    label: new Date(date).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' }),
    count,
  }))
}
