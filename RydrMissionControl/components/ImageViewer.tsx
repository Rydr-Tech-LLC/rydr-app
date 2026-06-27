"use client";

import { useState } from "react";

/**
 * Thumbnail + full-screen zoomable/downloadable preview for driver
 * documents (license, insurance, registration). Renders a clean
 * "not uploaded yet" placeholder when no URL exists — true today for
 * every driver until the upload pipeline is wired up (see beta
 * readiness audit P0 #10), so this should not look broken in the
 * meantime.
 */
export default function ImageViewer({ label, url }: { label: string; url?: string | null }) {
  const [open, setOpen] = useState(false);
  const [zoom, setZoom] = useState(1);

  if (!url) {
    return (
      <div className="flex h-32 flex-col items-center justify-center rounded-md border border-dashed border-line bg-grouped text-center">
        <p className="text-xs font-medium text-muted">{label}</p>
        <p className="mt-1 text-[11px] text-muted/70">Not uploaded yet</p>
      </div>
    );
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="group relative block h-32 w-full overflow-hidden rounded-md border border-line bg-grouped"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={url} alt={label} className="h-full w-full object-cover transition group-hover:opacity-90" />
        <span className="absolute bottom-1 left-1 rounded bg-black/60 px-1.5 py-0.5 text-[10px] text-white">
          {label}
        </span>
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/85 p-6"
          onClick={() => setOpen(false)}
        >
          <div className="mb-4 flex items-center gap-3" onClick={(e) => e.stopPropagation()}>
            <span className="text-sm text-white/80">{label}</span>
            <button
              onClick={() => setZoom((z) => Math.max(1, z - 0.25))}
              className="rounded bg-white/10 px-2 py-1 text-xs text-white"
            >
              −
            </button>
            <button
              onClick={() => setZoom((z) => Math.min(3, z + 0.25))}
              className="rounded bg-white/10 px-2 py-1 text-xs text-white"
            >
              +
            </button>
            <a
              href={url}
              download
              className="rounded bg-white/10 px-2 py-1 text-xs text-white"
              onClick={(e) => e.stopPropagation()}
            >
              Download
            </a>
            <button
              onClick={() => setOpen(false)}
              className="rounded bg-white/10 px-2 py-1 text-xs text-white"
            >
              Close
            </button>
          </div>
          <div className="max-h-[80vh] max-w-[90vw] overflow-auto" onClick={(e) => e.stopPropagation()}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={url}
              alt={label}
              style={{ transform: `scale(${zoom})`, transformOrigin: "center" }}
              className="transition-transform"
            />
          </div>
        </div>
      )}
    </>
  );
}
