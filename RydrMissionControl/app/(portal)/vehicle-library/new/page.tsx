import NewVehicleForm from "./NewVehicleForm";

export default function NewVehicleLibraryEntryPage() {
  return (
    <div className="max-w-lg space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Add Vehicle</h1>
        <p className="mt-1 text-sm text-muted">
          Create a new make/model/year entry in the Vehicle Library. You'll upload images on the next screen.
        </p>
      </div>
      <NewVehicleForm />
    </div>
  );
}
