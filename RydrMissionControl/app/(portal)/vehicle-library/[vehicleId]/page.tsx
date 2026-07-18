import { notFound } from "next/navigation";
import { getVehicleLibraryEntry } from "@/lib/vehicleLibrary";
import VehicleImageManager from "./VehicleImageManager";
import VehicleEntryActions from "./VehicleEntryActions";
import VehicleMetadataEditor from "./VehicleMetadataEditor";

export const dynamic = "force-dynamic";

export default async function VehicleLibraryEntryPage({ params }: { params: { vehicleId: string } }) {
  const entry = await getVehicleLibraryEntry(params.vehicleId);
  if (!entry) notFound();

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold text-ink">
            {entry.make} {entry.model}
          </h1>
          <p className="mt-1 text-sm text-muted">
            {entry.yearStart === entry.yearEnd ? entry.yearStart : `${entry.yearStart}–${entry.yearEnd}`}
            {entry.trim ? ` · ${entry.trim}` : ""} · {entry.bodyStyle} · {entry.vehicleId}
          </p>
        </div>
        <VehicleEntryActions vehicleId={entry.vehicleId} />
      </div>

      <VehicleMetadataEditor entry={entry} />
      <VehicleImageManager entry={entry} />
    </div>
  );
}
