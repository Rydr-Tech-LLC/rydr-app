export default function Loading() {
  return (
    <div
      role="status"
      aria-label="Loading workspace"
      className="animate-pulse space-y-6"
    >
      <div className="h-9 w-64 rounded-xl bg-gray-200" />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {[1, 2, 3, 4].map((n) => (
          <div
            key={n}
            className="h-28 rounded-2xl border border-line bg-white"
          />
        ))}
      </div>
      <div className="h-80 rounded-3xl border border-line bg-white" />
      <span className="sr-only">Loading workspace…</span>
    </div>
  );
}
