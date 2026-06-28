"use client";

import { useRef, useState } from "react";
import type { VehicleLibraryEntry } from "@/lib/vehicleLibrary";

const VEHICLE_COLORS = ["Black", "White", "Silver", "Gray", "Blue", "Red", "Green", "Brown", "Gold", "Yellow", "Orange"] as const;

export default function VehicleImageManager({ entry: initialEntry }: { entry: VehicleLibraryEntry }) {
  const [entry, setEntry] = useState(initialEntry);
  const [busySlot, setBusySlot] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
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
    <div className="space-y-3">
      {error && <p className="text-xs text-rydr-red">{error}</p>}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
        {slots.map((slot) => (
          <div key={slot.key} className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
            <div className="flex h-28 items-center justify-center bg-grouped">
              {slot.url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={slot.url} alt={slot.label} className="h-full w-full object-cover" />
              ) : (
                <p className="px-2 text-center text-[11px] text-muted/70">Vehicle image not yet available.</p>
              )}
            </div>
            <div className="p-2">
              <p className="truncate text-xs font-medium text-ink">{slot.label}</p>
              <div className="mt-1.5 flex gap-1.5">
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
                  className="flex-1 rounded-md bg-ink py-1 text-[11px] font-semibold text-white disabled:opacity-40"
                >
                  {busySlot === slot.key ? "…" : slot.url ? "Replace" : "Upload"}
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
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
