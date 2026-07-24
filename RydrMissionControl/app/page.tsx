import { redirect } from "next/navigation";
import { getMissionControlSession, homeForRole } from "@/lib/session";

export default async function RootPage() {
  const session = await getMissionControlSession();
  redirect(session ? homeForRole(session.role) : "/login");
}
