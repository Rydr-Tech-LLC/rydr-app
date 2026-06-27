import SearchClient from "./SearchClient";

export default function SearchPage() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Search</h1>
        <p className="mt-1 text-sm text-muted">Look up any driver or rider and jump straight into their record.</p>
      </div>
      <SearchClient />
    </div>
  );
}
