"use client";
import { CircleAlert, RefreshCw } from "lucide-react";
export default function ErrorPage({ retry }: { retry: () => void }) {
  return (
    <section className="mc-panel mx-auto max-w-xl py-14 text-center">
      <CircleAlert className="mx-auto text-rydr-red" size={36} />
      <h1 className="mt-5 text-2xl font-semibold">
        This workspace couldn’t load
      </h1>
      <p className="mx-auto mt-3 max-w-sm text-sm text-muted">
        Your data has not been changed. Try again, or return to another
        workspace using the navigation.
      </p>
      <button
        onClick={retry}
        className="mx-auto mt-6 flex items-center gap-2 rounded-xl bg-rydr-red px-5 py-3 text-sm font-semibold text-white"
      >
        <RefreshCw size={16} />
        Try again
      </button>
    </section>
  );
}
