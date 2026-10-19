import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";
import { currentWorkspace } from "@/lib/workspace";
import Notifications from "./Notifications";
export const dynamic = "force-dynamic";
export default async function Page() {
  if (!await getAdminSession()) redirect("/login");
  if (await currentWorkspace() !== "live-beta") redirect("/workspaces/live-beta/notifications");
  return <Notifications />;
}
