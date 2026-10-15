"use client";
import { useMemo, useState, type ReactNode } from "react";
import {
  Search,
  ArrowUpDown,
  Users,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
export type TableRow = {
  id: string;
  search: string;
  values: (string | number)[];
  cells: ReactNode[];
};
export default function DataTable({
  columns,
  rows,
  label = "records",
}: {
  columns: string[];
  rows: TableRow[];
  label?: string;
}) {
  const [q, setQ] = useState("");
  const [sort, setSort] = useState(-1);
  const [desc, setDesc] = useState(false);
  const [page, setPage] = useState(0);
  const filtered = useMemo(() => {
    const result = rows.filter((r) =>
      r.search.toLowerCase().includes(q.toLowerCase().trim()),
    );
    if (sort >= 0)
      result.sort((a, b) => {
        const x = a.values[sort] ?? "",
          y = b.values[sort] ?? "";
        return (
          (typeof x === "number" && typeof y === "number"
            ? x - y
            : String(x).localeCompare(String(y), undefined, {
                numeric: true,
              })) * (desc ? -1 : 1)
        );
      });
    return result;
  }, [rows, q, sort, desc]);
  const pages = Math.max(1, Math.ceil(filtered.length / 20)),
    current = Math.min(page, pages - 1);
  return (
    <section className="overflow-hidden rounded-lg border border-line bg-white">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line p-4">
        <label className="flex items-center gap-2 rounded-xl border border-line px-3 text-muted">
          <Search size={16} />
          <input
            aria-label={`Search ${label}`}
            placeholder={`Search ${label}…`}
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setPage(0);
            }}
            className="w-56 border-0 bg-transparent text-sm outline-none"
          />
        </label>
        <span className="text-xs text-muted">
          {filtered.length} of {rows.length} {label}
        </span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left">
          <thead>
            <tr>
              {columns.map((col, i) => (
                <th
                  key={i}
                  className="px-4"
                  aria-sort={
                    sort === i ? (desc ? "descending" : "ascending") : "none"
                  }
                >
                  <button
                    className="flex items-center gap-2 whitespace-nowrap"
                    onClick={() => {
                      setSort(i);
                      setDesc(sort === i ? !desc : false);
                      setPage(0);
                    }}
                  >
                    {col}
                    <ArrowUpDown size={12} />
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {filtered.slice(current * 20, current * 20 + 20).map((row) => (
              <tr key={row.id}>
                {row.cells.map((cell, i) => (
                  <td key={i} className="px-4">
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {!filtered.length && (
        <div className="mc-empty">
          <Users size={30} />
          <p className="font-medium text-ink">No matching {label}</p>
          <p className="mt-1 text-sm">
            Try a different name, email, or vehicle.
          </p>
          {q && (
            <button
              className="mt-3 text-sm text-rydr-burgundy"
              onClick={() => setQ("")}
            >
              Clear search
            </button>
          )}
        </div>
      )}
      <div className="flex items-center justify-between border-t border-line px-4 py-3 text-xs text-muted">
        <span>
          Page {current + 1} of {pages}
        </span>
        <div className="flex gap-2">
          <button
            aria-label="Previous page"
            disabled={!current}
            onClick={() => setPage(current - 1)}
            className="rounded-lg border border-line p-2 disabled:opacity-30"
          >
            <ChevronLeft size={15} />
          </button>
          <button
            aria-label="Next page"
            disabled={current >= pages - 1}
            onClick={() => setPage(current + 1)}
            className="rounded-lg border border-line p-2 disabled:opacity-30"
          >
            <ChevronRight size={15} />
          </button>
        </div>
      </div>
    </section>
  );
}
