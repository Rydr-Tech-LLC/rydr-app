import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";

export default async function RootPage() {
  const session = await getAdminSession();
  redirect(session ? "/dashboard" : "/login");
}
