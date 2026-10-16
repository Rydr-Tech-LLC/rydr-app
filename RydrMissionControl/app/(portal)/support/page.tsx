import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { toDateSafe } from "@/lib/format";
import SupportInbox from "@/components/SupportInbox";
export const dynamic = "force-dynamic";
export default async function SupportPage() {
  const snap = await (await getWorkspaceDb())
    .collection("supportTickets")
    .orderBy("updatedAt", "desc")
    .limit(200)
    .get()
    .catch(() => null);
  return (
    <SupportInbox
      failed={!snap}
      tickets={
        snap?.docs.map((doc) => {
          const t = doc.data();
          return {
            id: doc.id,
            subject: String(t.subject ?? "Support request"),
            status: String(t.status ?? "open"),
            role: String(t.userRole ?? "user"),
            category: String(t.category ?? ""),
            userId: String(t.userId ?? ""),
            updated: (() => {
              const date = toDateSafe(t.updatedAt) ?? toDateSafe(t.createdAt);
              return date
                ? date.toLocaleString("en-US", {
                    timeZone: "America/New_York",
                  }) + " ET"
                : "";
            })(),
          };
        }) ?? []
      }
    />
  );
}
