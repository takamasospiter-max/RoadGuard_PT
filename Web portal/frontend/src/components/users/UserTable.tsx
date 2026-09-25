import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
  type SortingState,
} from '@tanstack/react-table'
import { ArrowDown, ArrowUp, ArrowUpDown, ChevronLeft, ChevronRight } from 'lucide-react'
import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import type { PortalUser } from '@/types'
import { initials } from '@/lib/format'

const columnHelper = createColumnHelper<PortalUser>()

// "Today, 08:10" / "Yesterday" / "20 Sep 2026" depending on how recent the
// timestamp is — more readable than always printing the full date.
function formatLastActive(iso: string) {
  const date = new Date(iso)
  const today = new Date()
  const isToday = date.toDateString() === today.toDateString()
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)
  const isYesterday = date.toDateString() === yesterday.toDateString()

  if (isToday) return `Today, ${date.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}`
  if (isYesterday) return 'Yesterday'
  return date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}


interface UserTableProps {
  users: PortalUser[]
  onView: (user: PortalUser) => void
  onEdit: (user: PortalUser) => void
}

// Sortable, paginated table for the Users tab — built exactly like Reports'
// ReportTable (see that file for detailed comments on how TanStack Table
// is wired up); this is the second use of the same pattern against
// PortalUser instead of Defect. "View" and "Edit" open UserPanel in the
// two different modes it supports.
export function UserTable({ users, onView, onEdit }: UserTableProps) {
  const [sorting, setSorting] = useState<SortingState>([{ id: 'name', desc: false }])

  const columns = [
    columnHelper.accessor('name', {
      header: 'User',
      cell: (info) => (
        <div className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent/10 text-xs font-semibold text-accent">
            {initials(info.getValue())}
          </div>
          <div>
            <p className="font-medium text-text-primary">{info.getValue()}</p>
            <p className="text-xs text-text-secondary">{info.row.original.id}</p>
          </div>
        </div>
      ),
    }),
    columnHelper.accessor('email', { header: 'Email' }),
    columnHelper.accessor('role', {
      header: 'Role',
      cell: (info) => (info.getValue() === 'Admin' ? 'System Administrator' : 'Road Authority Officer'),
    }),
    columnHelper.accessor('authority', { header: 'Authority' }),
    columnHelper.accessor('status', {
      header: 'Status',
      cell: (info) => (
        <Badge variant={info.getValue() === 'Active' ? 'resolved' : 'neutral'}>{info.getValue()}</Badge>
      ),
    }),
    columnHelper.accessor('lastActiveAt', {
      header: 'Last Active',
      cell: (info) => formatLastActive(info.getValue()),
    }),
    columnHelper.display({
      id: 'actions',
      header: '',
      cell: (info) => (
        <div className="flex items-center justify-end gap-1.5">
          <Button variant="outline" size="sm" onClick={() => onView(info.row.original)}>
            View
          </Button>
          <Button variant="outline" size="sm" onClick={() => onEdit(info.row.original)}>
            Edit
          </Button>
        </div>
      ),
    }),
  ]

  const table = useReactTable({
    data: users,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 8 } },
  })

  const { pageIndex, pageSize } = table.getState().pagination
  const total = users.length
  const rangeStart = total === 0 ? 0 : pageIndex * pageSize + 1
  const rangeEnd = Math.min(total, (pageIndex + 1) * pageSize)

  return (
    <div>
      <div className="overflow-x-auto">
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
            {users.length === 0 && (
              <tr>
                <td colSpan={columns.length} className="px-4 py-10 text-center text-sm text-text-secondary">
                  No users found. Try changing your search or filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between border-t border-border-light px-4 py-3 text-xs text-text-secondary">
        <p>{total === 0 ? '0 users' : `${rangeStart}–${rangeEnd} of ${total} users`}</p>
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
