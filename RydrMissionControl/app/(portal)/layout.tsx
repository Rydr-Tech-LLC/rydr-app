import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";
import Sidebar from "@/components/Sidebar";

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const session = await getAdminSession();
  if (!session) redirect("/login");

  return (
    <div className="flex min-h-screen bg-grouped">
      <Sidebar email={session.email} />
      <main className="scrollbar-thin flex-1 overflow-y-auto">
        <div className="mx-auto max-w-6xl px-8 py-8">{children}</div>
      </main>
    </div>
  );
}
