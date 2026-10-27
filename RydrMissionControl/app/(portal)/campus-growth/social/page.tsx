import { getAdminSession } from "@/lib/session";
import SocialConnection from "./SocialConnection";
export default async function Page() {
  if (!await getAdminSession()) return <p className="rounded-xl border border-line bg-white p-5 text-sm">An administrator must manage social account connections.</p>;
  return <SocialConnection />;
}
