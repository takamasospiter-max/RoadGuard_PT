// One "label ........ value" line inside a <dl>, as used by the Reports and
// Map detail panels and the Users panel.
export function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-text-secondary">{label}</dt>
      <dd className="text-right font-medium text-text-primary">{value}</dd>
    </div>
  )
}
