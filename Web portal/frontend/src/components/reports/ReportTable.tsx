import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
  type SortingState,
} from '@tanstack/react-table'
import { ArrowDown, ArrowUp, ArrowUpDown, ChevronLeft, ChevronRight, Megaphone, Smartphone, User } from 'lucide-react'
import { useState } from 'react'
import { SeverityDot } from '@/components/dashboard/SeverityDot'
import { StatusBadge } from '@/components/dashboard/StatusBadge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { Defect } from '@/types'
import { sourceShortLabel } from '@/lib/sourceLabels'
import { formatDate } from '@/lib/format'

// TanStack Table's typed helper for building column definitions against
// the Defect shape — gives .accessor('someDefectField', ...) type-checking
// and autocomplete below.
const columnHelper = createColumnHelper<Defect>()


interface ReportTableProps {
  defects: Defect[]
  // Fires when "View" is clicked on a row — ReportsTab uses this to open
  // ReportDetailsPanel for that specific defect.
  onSelect: (defect: Defect) => void
}

// Sortable, paginated table for the Reports tab (SRS FR-DEF-1). This is
// the first real use of TanStack Table in the app (Users' UserTable is
// the other, built the same way) — everything below is driven by the
// `table` object it returns: header rendering, row rendering, sorting
// state, and pagination all come from calling its methods rather than
// hand-rolling that logic.
export function ReportTable({ defects, onSelect }: ReportTableProps) {
  // Starts sorted newest-first by detection date.
  const [sorting, setSorting] = useState<SortingState>([{ id: 'detectedAt', desc: true }])

  // One entry per table column. `accessor` columns read a field straight
  // off the Defect object; `cell` overrides how that value renders (e.g.
  // Status renders as a StatusBadge, not the raw string). The final
  // `display` column isn't tied to any field — it's just the "View" button.
  const columns = [
    columnHelper.accessor('id', { header: 'Report ID' }),
    columnHelper.accessor('road', {
      header: 'Road / Location',
      cell: (info) => (
        <div>
          <p className="font-medium text-text-primary">{info.getValue()}</p>
          <p className="text-xs text-text-secondary">{info.row.original.region}</p>
        </div>
      ),
    }),
    columnHelper.accessor('hazardType', { header: 'Type' }),
    columnHelper.accessor('severity', {
      header: 'Severity',
      cell: (info) => (
        <span className="flex items-center gap-1.5 capitalize">
          <SeverityDot severity={info.getValue()} />
          {info.getValue()}
        </span>
      ),
    }),
    columnHelper.accessor('status', {
      header: 'Status',
      cell: (info) => (
        <div className="flex flex-col items-start gap-1">
          <StatusBadge status={info.getValue()} />
          {/* Whether the mobile app is warning drivers about it right now. */}
          {info.row.original.shownToDrivers && (
            <span className="flex items-center gap-1 text-[11px] font-medium text-accent">
              <Megaphone size={11} />
              Drivers alerted
            </span>
          )}
        </div>
      ),
    }),
    columnHelper.accessor('source', {
      header: 'Source',
      cell: (info) => (
        <span className="flex items-center gap-1.5 text-text-secondary">
          {info.getValue() === 'device' ? <Smartphone size={13} /> : <User size={13} />}
          {sourceShortLabel[info.getValue()]}
        </span>
      ),
    }),
    columnHelper.accessor('detectedAt', {
      header: 'Detected',
      cell: (info) => formatDate(info.getValue()),
    }),
    columnHelper.display({
      id: 'action',
      header: '',
      cell: (info) => (
        <Button variant="outline" size="sm" onClick={() => onSelect(info.row.original)}>
          View
        </Button>
      ),
    }),
  ]

  // The three getXRowModel functions are TanStack Table's plugins: core
  // (required baseline), sorted (apply `sorting` state) and pagination
  // (slice into pages). `sorting` is "controlled" (state + onSortingChange)
  // so this component's own useState is the source of truth.
  const table = useReactTable({
    data: defects,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 8 } },
  })

  // Everything below is just for the "1–8 of 14 matching reports" label —
  // derived from the table's own pagination state, not tracked separately.
  const { pageIndex, pageSize } = table.getState().pagination
  const total = defects.length
  const rangeStart = total === 0 ? 0 : pageIndex * pageSize + 1
  const rangeEnd = Math.min(total, (pageIndex + 1) * pageSize)

  return (
    <div>
      <div className="overflow-x-auto">
        {/* flexRender(columnDef.header/cell, context) is TanStack Table's
            way of rendering whatever was passed for that column — a plain
            string, or a custom cell function like the ones above. */}
        <table className="w-full text-sm">
          <thead>
            {table.getHeaderGroups().map((headerGroup) => (
              <tr key={headerGroup.id} className="border-y border-border-light text-left text-xs font-medium text-text-secondary">
                {headerGroup.headers.map((header) => {
                  const sortable = header.column.getCanSort()
                  const sortDir = header.column.getIsSorted()
                  return (
                    <th key={header.id} className="whitespace-nowrap px-4 py-2.5 font-medium">
                      {header.isPlaceholder ? null : sortable ? (
                        <button
                          type="button"
                          onClick={header.column.getToggleSortingHandler()}
                          className="flex items-center gap-1 hover:text-text-primary"
                        >
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {sortDir === 'asc' ? (
                            <ArrowUp size={12} />
                          ) : sortDir === 'desc' ? (
                            <ArrowDown size={12} />
                          ) : (
                            <ArrowUpDown size={12} className="opacity-40" />
                          )}
                        </button>
                      ) : (
                        flexRender(header.column.columnDef.header, header.getContext())
                      )}
                    </th>
                  )
                })}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((row) => (
              <tr key={row.id} className="border-b border-border-light transition-colors duration-150 last:border-0 hover:bg-app-bg/50">
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id} className="whitespace-nowrap px-4 py-3 text-text-primary">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
            {defects.length === 0 && (
              <tr>
                <td colSpan={columns.length} className="px-4 py-10 text-center text-sm text-text-secondary">
                  No road-condition reports found. Try changing the filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between border-t border-border-light px-4 py-3 text-xs text-text-secondary">
        <p>
          {total === 0 ? '0 matching reports' : `${rangeStart}–${rangeEnd} of ${total} matching reports`}
        </p>
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => table.previousPage()}
            disabled={!table.getCanPreviousPage()}
            className={cn(
              'flex h-7 w-7 items-center justify-center rounded-md border border-border-light transition-colors duration-150 hover:bg-app-bg active:scale-95',
              !table.getCanPreviousPage() && 'opacity-40',
            )}
            aria-label="Previous page"
          >
            <ChevronLeft size={14} />
          </button>
          <button
            type="button"
            onClick={() => table.nextPage()}
            disabled={!table.getCanNextPage()}
            className={cn(
              'flex h-7 w-7 items-center justify-center rounded-md border border-border-light transition-colors duration-150 hover:bg-app-bg active:scale-95',
              !table.getCanNextPage() && 'opacity-40',
            )}
            aria-label="Next page"
          >
            <ChevronRight size={14} />
          </button>
        </div>
      </div>
    </div>
  )
}
