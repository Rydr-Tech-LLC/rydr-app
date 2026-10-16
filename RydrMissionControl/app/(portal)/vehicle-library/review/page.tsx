import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { buildVehicleId } from "@/lib/vehicleLibrary";
import ReviewActions from "./ReviewActions";
export const dynamic = "force-dynamic";

function safeUrl(value: unknown, host: string | string[]): string | undefined {
  try { const url = new URL(String(value)); return url.protocol === "https:" && (Array.isArray(host) ? host.includes(url.hostname) : url.hostname === host) ? url.href : undefined; }
  catch { return undefined; }
}
export default async function VehicleImageReviewPage() {
  if (!(await getAdminSession())) redirect("/login");
  const snapshot = await (await getWorkspaceDb()).collection("vehicleImageJobs").where("status", "==", "needs_review").limit(100).get();
  return <div className="space-y-6">
    <Link href="/vehicle-library" className="text-sm underline">Back to vehicle library</Link>
    <div><h1 className="text-xl font-semibold text-ink">Vehicle image issues</h1>
      <p className="mt-1 text-sm text-muted">Images are imported automatically. Only missing, uncertain, or failed matches appear here. Up to 100 unresolved issues are shown.</p></div>
    {snapshot.empty && <p className="text-sm text-muted">No vehicle image issues need review.</p>}
    {snapshot.docs.map(doc => {
      const job = doc.data(); const q = job.query;
      const vehicleId = buildVehicleId(q.make, q.model, q.year, q.year, q.trim);
      return <section key={doc.id} className="space-y-4 rounded-xl border bg-white p-5">
        <div><h2 className="font-semibold">{q.year} {q.make} {q.model} {q.trim} · {q.color}</h2>
          <p className="mt-1 text-sm text-muted">{job.reason}</p></div>
        <div className="grid gap-4 sm:grid-cols-3">
          {(job.candidates ?? []).map((candidate: any, i: number) => {
            const imageUrl = safeUrl(candidate.imageUrl, ["upload.wikimedia.org", "thumb.wikimedia.org"]);
            const sourceUrl = safeUrl(candidate.sourceUrl, "commons.wikimedia.org");
            return <div key={i} className="space-y-2 rounded border p-3">
              {imageUrl && <img src={imageUrl} alt={candidate.title} className="h-36 w-full object-contain" />}
              <p className="text-xs">{candidate.title}</p>
              <p className="text-xs text-muted">{candidate.license} · {candidate.author}</p>
              <p className="text-xs">{candidate.issue ?? candidate.assessment?.reason}</p>
              {sourceUrl && <a href={sourceUrl} target="_blank" rel="noreferrer" className="text-xs underline">View source and license</a>}
            </div>;
          })}
        </div>
        <p className="text-sm text-muted">To replace an image, upload an image you have permission to use into this vehicle&apos;s color slot, then choose “Use uploaded library image.”</p>
        <div className="flex gap-4 text-sm underline">
          <Link href={`/vehicle-library/${encodeURIComponent(vehicleId)}`}>Open vehicle entry</Link>
          <Link href="/vehicle-library/new">Create entry if missing</Link>
        </div>
        <ReviewActions jobId={doc.id} />
      </section>;
    })}
  </div>;
}
