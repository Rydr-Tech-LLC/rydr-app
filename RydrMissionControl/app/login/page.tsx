import { redirect } from "next/navigation";
import { getAdminSession } from "@/lib/session";
import LoginForm from "./LoginForm";

export default async function LoginPage() {
  const session = await getAdminSession();
  if (session) redirect("/dashboard");

  return (
    <div className="flex min-h-screen items-center justify-center bg-ink px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-md bg-gradient-to-br from-rydr-red to-rydr-burgundy text-lg font-bold text-white">
            R
          </div>
          <h1 className="text-xl font-semibold text-white">Rydr Mission Control</h1>
          <p className="mt-1 text-sm text-white/50">Staff access only</p>
        </div>
        <LoginForm />
      </div>
    </div>
  );
}
