import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import NewVehicleForm from "./NewVehicleForm";

export default function NewVehicleLibraryEntryPage() {
  return (
    <div className="max-w-3xl space-y-6">
      <Link href="/vehicle-library" className="text-sm font-medium text-fuchsia-700">← Vehicle Library</Link>
      <div className="rounded-3xl bg-gradient-to-br from-red-500 via-fuchsia-700 to-blue-700 p-7 text-white shadow-lg">
        <h1 className="text-3xl font-semibold">Add Vehicle</h1>
        <p className="mt-2 text-sm text-white/85">
          Create the matching record Mission Control will use when a driver adds this vehicle during onboarding.
          Images are uploaded after the entry is created.
        </p>
      </div>
      <NewVehicleForm />
    </div>
  );
}
