import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, Cpu, PauseCircle } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { fetchAIEngineOverview, type AIEngineOverview } from '@/lib/aiEngine'
import { formatRelativeTime } from '@/lib/formatRelativeTime'

// Dashboard card: is the AI engine running, and is it finding potholes?
// Reads GET /api/ai-engine/ every 30 s. It shows:
// - which model is configured (or that the placeholder is still in place);
// - sensor batches waiting / analysed / failed;
// - AI detections in the last 24 h and in total;
// - the latest failure, so a broken model is noticed quickly.
export function AIEngineCard() {
  const { data, isPending, isError } = useQuery({
    queryKey: ['ai-engine'],
    queryFn: fetchAIEngineOverview,
    refetchInterval: 30_000,
  })

  return (
    <Card className="flex flex-col gap-4 p-5">
      <div className="flex items-center gap-2">
        <Cpu size={18} className="text-accent" />
        <h2 className="text-sm font-semibold text-text-primary">AI engine</h2>
        {data && <EngineState data={data} />}
      </div>

      {isPending && <p className="text-sm text-text-secondary">Loading...</p>}
      {isError && <p className="text-sm text-text-secondary">The AI engine status could not be loaded.</p>}

      {data && (
        <>
          <p className="text-xs text-text-secondary">
            Model: <span className="font-medium text-text-primary">{data.modelVersion}</span>
            {data.lastProcessedAt && (
              <> &middot; last batch analysed {formatRelativeTime(new Date(data.lastProcessedAt))}</>
            )}
          </p>

          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Figure label="Batches waiting" value={data.batches.pending + data.batches.processing} />
            <Figure label="Batches analysed" value={data.batches.done} />
            <Figure label="Detections (24 h)" value={data.detections.last24h} />
            <Figure label="Detections (total)" value={data.detections.total} />
          </dl>

          {data.batches.failed > 0 && data.lastError && (
            <p className="flex items-start gap-1.5 rounded-lg bg-severity-high/10 px-3 py-2 text-xs text-severity-high">
              <AlertTriangle size={14} className="mt-0.5 shrink-0" />
              <span>
                {data.batches.failed} batch{data.batches.failed === 1 ? '' : 'es'} failed. Latest
                {data.lastError.at && <> ({formatRelativeTime(new Date(data.lastError.at))})</>}:{' '}
                {data.lastError.message}
              </span>
            </p>
          )}
          {data.detections.simulated > 0 && (
            <p className="text-[11px] text-text-secondary">
              Plus {data.detections.simulated} simulated test detections, never shown to drivers.
            </p>
          )}
        </>
      )}
    </Card>
  )
}

// A small status label next to the title.
function EngineState({ data }: { data: AIEngineOverview }) {
  if (data.isPlaceholder) {
    return (
      <span className="ml-auto flex items-center gap-1 text-xs font-medium text-text-secondary">
        <PauseCircle size={14} />
        No model connected
      </span>
    )
  }
  if (data.batches.failed > 0 && data.batches.done === 0) {
    return (
      <span className="ml-auto flex items-center gap-1 text-xs font-medium text-severity-high">
        <AlertTriangle size={14} />
        Failing
      </span>
    )
  }
  return (
    <span className="ml-auto flex items-center gap-1 text-xs font-medium text-accent">
      <CheckCircle2 size={14} />
      Running
    </span>
  )
}

function Figure({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-border-light px-3 py-2">
      <dd className="text-xl font-bold tabular-nums text-text-primary">{value}</dd>
      <dt className="text-[11px] text-text-secondary">{label}</dt>
    </div>
  )
}
