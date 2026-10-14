"use client";
import { vehicleImageSearchUrl } from "@/lib/vehicleImageSearch";

import { useRef, useState } from "react";
import type { VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const VEHICLE_COLORS = ["Black", "White", "Silver", "Gray", "Blue", "Red", "Green", "Brown", "Gold", "Yellow", "Orange"] as const;

export default function VehicleImageManager({ entry: initialEntry }: { entry: VehicleLibraryEntry }) {
  const [entry, setEntry] = useState(initialEntry);
  const [busySlot, setBusySlot] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editSlot, setEditSlot] = useState<{ key: string; color?: string; url: string } | null>(null);
  const [editPrompt, setEditPrompt] = useState("Remove the existing background and place the vehicle on a clean, pure white studio background with a subtle natural ground shadow.");
  const [previewFile, setPreviewFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  async function generatePreview() {
    if (!editSlot) return;
    setEditing(true); setError(null);
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl(null); setPreviewFile(null);
    try {
      const response = await fetch(`/api/vehicle-library/${entry.vehicleId}/edit-background`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ color: editSlot.color, prompt: editPrompt }) });
      if (!response.ok) { const body = await response.json(); setError(body.error ?? "Could not edit background."); return; }
      const blob = await response.blob(); const file = new File([blob], "vehicle-white-background.jpg", { type: "image/jpeg" });
      setPreviewFile(file); setPreviewUrl(URL.createObjectURL(file));
    } catch { setError("Image editing is unavailable. Your image has not changed."); }
    finally { setEditing(false); }
  }
  const fileInputs = useRef<Record<string, HTMLInputElement | null>>({});

  async function upload(slot: string, color: string | undefined, file: File) {
    setBusySlot(slot);
    setError(null);
    try {
      const form = new FormData();
      form.append("file", file);
      if (color) form.append("color", color);
      const res = await fetch(`/api/vehicle-library/${entry.vehicleId}/image`, { method: "POST", body: form });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Upload failed.");
        return;
      }
      setEntry(body.entry);
    } finally {
      setBusySlot(null);
    }
  }

  async function remove(slot: string, color: string | undefined) {
    setBusySlot(slot);
    setError(null);
    try {
      const query = color ? `?color=${encodeURIComponent(color)}` : "";
      const res = await fetch(`/api/vehicle-library/${entry.vehicleId}/image${query}`, { method: "DELETE" });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Delete failed.");
        return;
      }
      setEntry(body.entry);
    } finally {
      setBusySlot(null);
    }
  }

  const slots: { key: string; label: string; color?: (typeof VEHICLE_COLORS)[number]; url: string | null | undefined }[] = [
    { key: "default", label: "Default / Fallback", url: entry.defaultImageUrl },
    ...VEHICLE_COLORS.map((color) => ({ key: color, label: color, color, url: entry.colorImageUrls?.[color] }))
  ];

  return (
    <section id="vehicle-images" className="space-y-4 rounded-3xl border border-line bg-white p-6 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-ink">Image Coverage</h2>
          <p className="mt-1 text-xs text-muted">
            Upload a default image first, then add color-specific images as they become available.
          </p>
        </div>
        <a
          href={vehicleImageSearchUrl(entry)}
          target="_blank"
          rel="noreferrer"
          className="rounded-md border border-rydr-burgundy px-3 py-1.5 text-xs font-semibold text-rydr-burgundy hover:bg-red-50"
        >
          Search Google Images
        </a>
      </div>
      {editSlot && <div role="dialog" aria-label="Edit vehicle image background" className="rounded-lg border border-line bg-grouped p-4 space-y-3">
        <h3 className="text-sm font-semibold">Edit {editSlot.color ?? "default"} image background</h3>
        <p className="text-xs text-muted">Background changes preserve the vehicle and its exterior color. Review the preview before replacing the image. Uses your OpenAI API credits.</p>
        <textarea aria-label="Image editing prompt" maxLength={1500} value={editPrompt} onChange={event => setEditPrompt(event.target.value)} className="w-full rounded border border-line p-2 text-xs" />
        <div className="grid grid-cols-2 gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={editSlot.url} alt="Original vehicle" className="max-h-56 w-full object-contain" />
          {previewUrl && <img src={previewUrl} alt="Edited vehicle preview" className="max-h-56 w-full object-contain" />}
        </div>
        <div className="flex gap-2"><button disabled={editing} onClick={generatePreview} className="rounded bg-ink px-3 py-2 text-xs text-white disabled:opacity-40">{editing ? "Editing…" : "Generate preview"}</button>
          {previewFile && <button disabled={editing || busySlot !== null} onClick={async () => { await upload(editSlot.key, editSlot.color, previewFile); }} className="rounded bg-rydr-burgundy px-3 py-2 text-xs text-white disabled:opacity-40">Use edited image</button>}
          <button disabled={editing} onClick={() => { if (previewUrl) URL.revokeObjectURL(previewUrl); setEditSlot(null); setPreviewFile(null); setPreviewUrl(null); }} className="rounded border border-line px-3 py-2 text-xs">Close</button></div>
      </div>}
      {error && <p className="text-xs text-rydr-red">{error}</p>}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6">
        {slots.map((slot) => (
          <div key={slot.key} className="overflow-hidden rounded-2xl border border-line bg-white">
            <div className="flex h-32 items-center justify-center bg-grouped">
              {slot.url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={slot.url} alt={slot.label} className="h-full w-full object-contain" />
              ) : (
                <p className="px-2 text-center text-[11px] text-muted/70">Vehicle image not yet available.</p>
              )}
            </div>
            <div className="p-2">
              <div className="flex items-center justify-between gap-2">
                <p className="truncate text-xs font-medium text-ink">{slot.label}</p>
                <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${slot.url ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>
                  {slot.url ? "Ready" : "Needed"}
                </span>
              </div>
              <div className="mt-2 flex gap-1.5">
                <input
                  ref={(el) => {
                    fileInputs.current[slot.key] = el;
                  }}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) upload(slot.key, slot.color, file);
                    e.target.value = "";
                  }}
                />
                <button
                  onClick={() => fileInputs.current[slot.key]?.click()}
                  disabled={busySlot === slot.key}
                  className="flex-1 rounded-xl bg-gradient-to-r from-red-500 via-fuchsia-600 to-blue-600 py-1 text-[11px] font-semibold text-white disabled:opacity-40"
                >
                  {busySlot === slot.key ? "Saving" : slot.url ? "Replace" : "Upload"}
                </button>
                {slot.url && (
                  <button
                    onClick={() => remove(slot.key, slot.color)}
                    disabled={busySlot === slot.key}
                    className="rounded-md border border-line px-2 text-[11px] font-medium text-muted disabled:opacity-40"
                  >
                    ✕
                  </button>
                )}
              </div>
              {slot.url && <button onClick={() => { if (previewUrl) URL.revokeObjectURL(previewUrl); setPreviewFile(null); setPreviewUrl(null); setEditSlot({ key: slot.key, color: slot.color, url: slot.url! }); }} className="mt-1.5 w-full rounded-md border border-line py-1 text-center text-[11px] font-medium text-muted hover:bg-grouped">Edit background / prompt</button>}
              {!slot.url && (
                <a
                  href={vehicleImageSearchUrl(entry, slot.color)}
                  target="_blank"
                  rel="noreferrer"
                  className="mt-1.5 block rounded-md border border-line py-1 text-center text-[11px] font-medium text-muted hover:bg-grouped"
                >
                  Search Google Images
                </a>
              )}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
