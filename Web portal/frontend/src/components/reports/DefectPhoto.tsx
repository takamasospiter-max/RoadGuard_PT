import { Camera, ImageOff, Loader2, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { ApiError } from '@/lib/api'
import { fetchDefectPhoto } from '@/lib/defects'

// The photo a traveller took with the mobile app when reporting this defect.
// Used by both slide-overs (Reports' ReportDetailsPanel and Map's
// HazardDetailsPanel) so officers can see the evidence before deciding.
//
// - Loads the JPEG through axios (the endpoint needs the login cookie) and
//   shows it from an object URL, which is released again on close.
// - Click the thumbnail to see it full-screen; click anywhere or press Esc
//   to close.
// - Defects with no photo (sensor detections, portal entries) just say so.
type PhotoState =
  | { kind: 'loading' }
  | { kind: 'ready'; url: string }
  | { kind: 'error'; message: string }

export function DefectPhoto({ defectId, hasPhoto }: { defectId: string; hasPhoto: boolean }) {
  if (!hasPhoto) {
    return (
      <p className="flex items-center gap-1.5 text-xs font-medium text-text-secondary">
        <ImageOff size={13} />
        Camera evidence: No photo attached
      </p>
    )
  }
  // Keyed by id: a different defect starts a fresh load instead of briefly
  // showing the previous defect's photo.
  return <LoadedPhoto key={defectId} defectId={defectId} />
}

function LoadedPhoto({ defectId }: { defectId: string }) {
  const [state, setState] = useState<PhotoState>({ kind: 'loading' })
  const [enlarged, setEnlarged] = useState(false)

  // Fetch the photo once per defect; free the object URL when unmounted.
  useEffect(() => {
    let url: string | null = null
    let cancelled = false
    fetchDefectPhoto(defectId)
      .then((blob) => {
        if (cancelled) return
        url = URL.createObjectURL(blob)
        setState({ kind: 'ready', url })
      })
      .catch((err: unknown) => {
        if (cancelled) return
        // 404 = the record says "has photo" but none is stored (e.g. sample data).
        let message = 'The photo could not be loaded.'
        if (err instanceof ApiError && err.status === 404) message = 'The photo is no longer stored on the server.'
        if (err instanceof ApiError && err.status === 0) message = 'Could not reach the server to load the photo.'
        setState({ kind: 'error', message })
      })
    return () => {
      cancelled = true
      if (url) URL.revokeObjectURL(url)
    }
  }, [defectId])

  // Esc closes the full-screen view.
  useEffect(() => {
    if (!enlarged) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setEnlarged(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [enlarged])

  return (
    <div className="space-y-2">
      <p className="flex items-center gap-1.5 text-xs font-medium text-text-secondary">
        <Camera size={13} />
        Camera evidence: traveller&apos;s photo
      </p>

      {state.kind === 'loading' && (
        <div className="flex h-40 items-center justify-center rounded-lg border border-border-light bg-surface text-xs text-text-secondary">
          <Loader2 size={16} className="mr-2 animate-spin" />
          Loading photo...
        </div>
      )}

      {state.kind === 'error' && (
        <p className="rounded-lg border border-border-light bg-surface p-3 text-xs text-text-secondary">
          {state.message}
        </p>
      )}

      {state.kind === 'ready' && (
        <>
          <button
            type="button"
            onClick={() => setEnlarged(true)}
            className="block w-full overflow-hidden rounded-lg border border-border-light focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            aria-label="Enlarge photo"
          >
            <img
              src={state.url}
              alt={`Photo reported for ${defectId}`}
              className="max-h-56 w-full object-cover transition-transform duration-200 hover:scale-[1.02]"
            />
          </button>
          <p className="text-[11px] text-text-secondary">
            Click to enlarge. Location data was removed from the photo when it was uploaded.
          </p>
        </>
      )}

      {/* Full-screen view, above the slide-over (z-1300). */}
      {enlarged && state.kind === 'ready' && (
        <div
          className="fixed inset-0 z-[1400] flex items-center justify-center bg-black/80 p-4"
          onClick={() => setEnlarged(false)}
          role="dialog"
          aria-modal="true"
          aria-label={`Photo for ${defectId}`}
        >
          <button
            type="button"
            onClick={() => setEnlarged(false)}
            className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-white/15 text-white hover:bg-white/25"
            aria-label="Close photo"
          >
            <X size={20} />
          </button>
          <img
            src={state.url}
            alt={`Photo reported for ${defectId}`}
            className="max-h-full max-w-full rounded-lg object-contain"
          />
        </div>
      )}
    </div>
  )
}
