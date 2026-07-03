import NewVehicleForm from "./NewVehicleForm";

export default function NewVehicleLibraryEntryPage() {
  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Add Vehicle</h1>
        <p className="mt-1 text-sm text-muted">
          Create the matching record Mission Control will use when a driver adds this vehicle during onboarding.
          Images are uploaded after the entry is created.
        </p>
      </div>
      <NewVehicleForm />
    </div>
  );
}
