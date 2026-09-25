import { apiGet } from '@/lib/api'

// The AI engine at a glance, for the Dashboard card.
// GET /api/ai-engine/ (new-backend/detection/views.py, AIEngineOverviewView).
// Any logged-in portal user can read it; it never loads the model itself.
export interface AIEngineOverview {
  engine: string              // engine class name, e.g. "PotholeEngine"
  modelVersion: string        // version of the configured model
  isPlaceholder: boolean      // true while the placeholder "NullEngine" is configured
  inlineProcessing: boolean   // batches analysed as soon as they arrive
  // Sensor batches by state: waiting, being analysed, finished, failed.
  batches: { pending: number; processing: number; done: number; failed: number }
  lastProcessedAt: string | null
  detections: { total: number; last24h: number; simulated: number }
  lastDetection: { detectedAt: string; modelVersion: string } | null
  lastError: { at: string | null; message: string } | null
}

export async function fetchAIEngineOverview(): Promise<AIEngineOverview> {
  return apiGet<AIEngineOverview>('/ai-engine/')
}
