import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import {WorkspaceProvider} from "@/components/WorkspaceContext";
import {currentWorkspace} from "@/lib/workspace";
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { getMissionControlSession } from "@/lib/session";
import {
  canAccessMissionControlPath,
  MISSION_CONTROL_PATH_HEADER,
} from "@/lib/missionControlAccess";
import WorkspaceHeader from "@/components/WorkspaceHeader";
import Sidebar from "@/components/Sidebar";

export default async function PortalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const workspace=await currentWorkspace();
  const session = await getMissionControlSession();
  if (!session) redirect("/login");

  const state = (await (await getWorkspaceDb()).collection("platformConfig").doc("workspace").get()).data();
  const livePaymentsEnabled = state?.livePaymentsEnabled === true;
  const pathname = (await headers()).get(MISSION_CONTROL_PATH_HEADER);
  if (
    session.role === "marketing" &&
    (!pathname || !canAccessMissionControlPath(session.role, pathname))
  ) {
    redirect(`/workspaces/${workspace}/campus-growth`);
  }

  return (
    <WorkspaceProvider workspace={workspace}><div className="mc-workspace flex min-h-screen min-w-0 bg-grouped">
      <Sidebar email={session.email} role={session.role} />
      <main className="scrollbar-thin min-w-0 flex-1 overflow-y-auto pt-16 md:pt-0">
        <WorkspaceHeader role={session.role} />
        {workspace === "live-beta" && !livePaymentsEnabled && <div role="status" className="border-b border-amber-200 bg-amber-50 px-6 py-3 text-sm text-amber-900">Live Beta workspace · Live rides and payments are not enabled yet. Test accounts and simulated activity stay in Test.</div>}
        <div className="mc-content mx-auto w-full max-w-[1600px] px-4 py-5 sm:px-6 sm:py-6 lg:px-10 lg:py-8">
          {children}
        </div>
      </main>
    </div></WorkspaceProvider>
  );
}
