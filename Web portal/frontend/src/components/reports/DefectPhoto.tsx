import { Camera, ImageOff, Loader2, ScanSearch, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import { ApiError } from '@/lib/api'
import { fetchDefectPhoto } from '@/lib/defects'
import type { PhotoCheck } from '@/types'

// The photo a traveller took with the mobile app when reporting this defect.
// Used by both slide-overs (Reports' ReportDetailsPanel and Map's
// HazardDetailsPanel) so officers can see the evidence before deciding.
//
// - Loads the JPEG through axios (the endpoint needs the login cookie) and
//   shows it from an object URL, which is released again on close.
// - Click the thumbnail to see it full-screen; click anywhere or press Esc
//   to close.
// - Defects with no photo (sensor detections, portal entries) just say so.
// - If the AI photo model has checked the photo, its verdict is shown under
//   the photo and the potholes it found are outlined on it. That is advice
//   for the officer, not a decision: the model misses about half of potholes.
type PhotoState =
  | { kind: 'loading' }
  | { kind: 'ready'; url: string }
  | { kind: 'error'; message: string }

export function DefectPhoto({
  defectId,
  hasPhoto,
  photoCheck,
}: {
  defectId: string
  hasPhoto: boolean
  photoCheck?: PhotoCheck
}) {
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
  return <LoadedPhoto key={defectId} defectId={defectId} photoCheck={photoCheck} />
}

function LoadedPhoto({ defectId, photoCheck }: { defectId: string; photoCheck?: PhotoCheck }) {
  // Boxes to draw: only when the check worked and found something.
  const boxes = photoCheck && photoCheck.status !== 'failed' ? photoCheck.boxes : []
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
            className="block w-full overflow-hidden rounded-lg border border-border-light bg-surface focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
            aria-label="Enlarge photo"
          >
            {/* The whole photo is shown (not cropped) so the AI boxes line up with it. */}
            <BoxedImage
              url={state.url}
              alt={`Photo reported for ${defectId}`}
              boxes={boxes}
              imgClassName="max-h-56"
            />
          </button>
          <PhotoCheckVerdict check={photoCheck} />
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
          <BoxedImage
            url={state.url}
            alt={`Photo reported for ${defectId}`}
            boxes={boxes}
            imgClassName="max-h-[90vh] max-w-[90vw] rounded-lg"
          />
        </div>
      )}
    </div>
  )
}

// The photo with the AI model's pothole boxes drawn over it. The wrapper is
// exactly the size of the image, so the boxes' 0-1 fractions become
// percentages of the photo at whatever size it is shown.
function BoxedImage({
  url,
  alt,
  boxes,
  imgClassName,
}: {
  url: string
  alt: string
  boxes: [number, number, number, number, number][]
  imgClassName: string
}) {
  return (
    <span className="relative mx-auto block w-fit">
      <img src={url} alt={alt} className={`block max-w-full ${imgClassName}`} />
      {boxes.map(([x1, y1, x2, y2, conf], i) => (
        <span
          key={i}
          className="pointer-events-none absolute rounded-sm border-2 border-severity-high"
          style={{
            left: `${x1 * 100}%`,
            top: `${y1 * 100}%`,
            width: `${(x2 - x1) * 100}%`,
            height: `${(y2 - y1) * 100}%`,
          }}
        >
          <span className="absolute left-0 top-0 bg-severity-high px-1 text-[10px] font-semibold leading-4 text-white">
            {Math.round(conf * 100)}%
          </span>
        </span>
      ))}
    </span>
  )
}

// One line saying what the AI photo model made of the photo.
function PhotoCheckVerdict({ check }: { check?: PhotoCheck }) {
  let text: string
  let tone = 'text-text-secondary'
  if (!check) {
    text = 'AI photo check: not run yet.'
  } else if (check.status === 'failed') {
    text = 'AI photo check: could not be run on this photo.'
  } else if (check.status === 'pothole_found') {
    const count = check.boxes.length
    text = `AI photo check: ${count} pothole${count === 1 ? '' : 's'} outlined (up to ${Math.round(check.confidence * 100)}% sure).`
    tone = 'text-severity-high'
  } else {
    text = 'AI photo check: no pothole recognised. The model often misses them, so judge the photo yourself.'
  }
  return (
    <p className={`flex items-start gap-1.5 text-xs font-medium ${tone}`}>
      <ScanSearch size={13} className="mt-0.5 shrink-0" />
      <span>{text}</span>
    </p>
  )
}
