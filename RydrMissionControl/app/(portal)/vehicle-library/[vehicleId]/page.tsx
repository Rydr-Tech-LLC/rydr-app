import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import { notFound } from "next/navigation";
import { getVehicleLibraryEntry } from "@/lib/vehicleLibrary";
import VehicleImageManager from "./VehicleImageManager";
import VehicleEntryActions from "./VehicleEntryActions";
import VehicleMetadataEditor from "./VehicleMetadataEditor";

export const dynamic = "force-dynamic";

export default async function VehicleLibraryEntryPage(props: { params: Promise<{ vehicleId: string }> }) {
  const params = await props.params;
  const entry = await getVehicleLibraryEntry(params.vehicleId);
  if (!entry) notFound();

  return (
    <div className="space-y-6">
      <Link href="/vehicle-library" className="text-sm font-medium text-fuchsia-700">← Vehicle Library</Link>
      <div className="flex flex-col gap-3 rounded-3xl bg-gradient-to-br from-red-500 via-fuchsia-700 to-blue-700 p-7 text-white shadow-lg sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="text-3xl font-semibold">
            {entry.make} {entry.model}
          </h1>
          <p className="mt-2 text-sm text-white/85">
            {entry.yearStart === entry.yearEnd ? entry.yearStart : `${entry.yearStart}–${entry.yearEnd}`}
            {entry.trim ? ` · ${entry.trim}` : ""} · {entry.bodyStyle} · {entry.vehicleId}
          </p>
        </div>
        <VehicleEntryActions vehicleId={entry.vehicleId} />
      </div>

      <nav aria-label="Vehicle sections" className="flex gap-3"><a href="#vehicle-metadata" className="rounded-full border border-line bg-white px-5 py-2 text-sm font-semibold text-ink">Specifications & eligibility</a><a href="#vehicle-images" className="rounded-full border border-line bg-white px-5 py-2 text-sm font-semibold text-ink">Images & colors</a></nav>
      <VehicleMetadataEditor entry={entry} />
      <VehicleImageManager entry={entry} />
    </div>
  );
}
