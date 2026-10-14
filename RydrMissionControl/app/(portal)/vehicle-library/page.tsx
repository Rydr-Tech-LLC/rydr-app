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
      <div className="flex flex-wrap items-center justify-between gap-5 rounded-3xl bg-gradient-to-br from-red-500 via-fuchsia-700 to-blue-700 p-7 text-white shadow-lg">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight">Vehicle Library</h1>
          <p className="mt-2 max-w-2xl text-sm text-white/85">
            Find the right vehicle, verify its seats and ride eligibility, and build a matching image collection.
            {" "}{entries.length} {make || model ? "matching entries" : "entries"}.
          </p>
        </div>
        <Link href="/vehicle-library/new" className="rounded-xl bg-white px-5 py-3 text-sm font-semibold text-fuchsia-800 shadow-sm hover:bg-red-50">+ Add vehicle</Link>
      </div>

      <Link href="/vehicle-library/review" className="inline-flex items-center rounded-xl border border-fuchsia-100 bg-fuchsia-50 px-4 py-3 text-sm font-medium text-fuchsia-800 hover:bg-fuchsia-100">
        Image automation · {issues.data().count} issues to review
      </Link>

      <VehicleLibraryClient initialEntries={entries} initialMake={make ?? ""} initialModel={model ?? ""} />
    </div>
  );
}
