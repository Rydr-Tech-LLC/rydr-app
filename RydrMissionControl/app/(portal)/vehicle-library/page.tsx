import { listVehicleLibrary, searchVehicleLibrary } from "@/lib/vehicleLibrary";
import VehicleLibraryClient from "./VehicleLibraryClient";

export const dynamic = "force-dynamic";

export default async function VehicleLibraryPage({
  searchParams
}: {
  searchParams: { make?: string; model?: string };
}) {
  const make = searchParams?.make;
  const model = searchParams?.model;
  const entries = make || model ? await searchVehicleLibrary({ make, model }) : await listVehicleLibrary();

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-xl font-semibold text-ink">Vehicle Library</h1>
          <p className="mt-1 text-sm text-muted">
            Generic factory-style vehicle images shown to drivers and riders in place of uploaded vehicle photos.
            {" "}{entries.length} {make || model ? "matching entries" : "entries"}.
          </p>
        </div>
      </div>

      <VehicleLibraryClient initialEntries={entries} initialMake={make ?? ""} initialModel={model ?? ""} />
    </div>
  );
}
