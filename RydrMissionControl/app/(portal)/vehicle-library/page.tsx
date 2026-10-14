import Link from "next/link";
import { adminDb } from "@/lib/firebaseAdmin";
import { listVehicleLibrary, searchVehicleLibrary } from "@/lib/vehicleLibrary";
import VehicleLibraryClient from "./VehicleLibraryClient";

export const dynamic = "force-dynamic";

export default async function VehicleLibraryPage(
  props: {
    searchParams: Promise<{ make?: string; model?: string }>;
  }
) {
  const searchParams = await props.searchParams;
  const make = searchParams?.make;
  const model = searchParams?.model;
  const entries = make || model ? await searchVehicleLibrary({ make, model }) : await listVehicleLibrary();

  const issues = await adminDb.collection("vehicleImageJobs").where("status", "==", "needs_review").count().get();

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

      <Link href="/vehicle-library/review" className="inline-block rounded-lg border px-4 py-2 text-sm">
        Image automation · {issues.data().count} issues to review
      </Link>

      <VehicleLibraryClient initialEntries={entries} initialMake={make ?? ""} initialModel={model ?? ""} />
    </div>
  );
}
