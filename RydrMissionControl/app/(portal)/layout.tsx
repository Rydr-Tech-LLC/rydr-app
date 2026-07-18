import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";
import Sidebar from "@/components/Sidebar";

export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const session = await getAdminSession();
  if (!session) redirect("/login");

  return (
    <div className="flex min-h-screen min-w-0 bg-grouped">
      <Sidebar email={session.email} />
      <main className="scrollbar-thin min-w-0 flex-1 overflow-y-auto pt-16 md:pt-0">
        <div className="mx-auto w-full max-w-6xl px-4 py-5 sm:px-6 sm:py-6 lg:px-8 lg:py-8">{children}</div>
      </main>
    </div>
  );
}
