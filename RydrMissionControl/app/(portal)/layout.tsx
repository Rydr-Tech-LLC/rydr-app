import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { getMissionControlSession } from "@/lib/session";
import { canAccessMissionControlPath, MISSION_CONTROL_PATH_HEADER } from "@/lib/missionControlAccess";
import Sidebar from "@/components/Sidebar";

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const session = await getMissionControlSession();
  if (!session) redirect("/login");

  const pathname = headers().get(MISSION_CONTROL_PATH_HEADER);
  if (session.role === "marketing" && (!pathname || !canAccessMissionControlPath(session.role, pathname))) {
    redirect("/campus-growth");
  }

  return (
    <div className="flex min-h-screen min-w-0 bg-grouped">
      <Sidebar email={session.email} role={session.role} />
      <main className="scrollbar-thin min-w-0 flex-1 overflow-y-auto pt-16 md:pt-0">
        <div className="mx-auto w-full max-w-6xl px-4 py-5 sm:px-6 sm:py-6 lg:px-8 lg:py-8">{children}</div>
      </main>
    </div>
  );
}
