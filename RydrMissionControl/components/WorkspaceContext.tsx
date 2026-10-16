"use client";
import { createContext, useContext } from "react";
import Link, { type LinkProps } from "next/link";
import { usePathname, useRouter } from "next/navigation";
import type { AnchorHTMLAttributes } from "react";
export type Workspace = "test" | "live-beta";
const Context = createContext<Workspace>("test");
export function WorkspaceProvider({
  workspace,
  children,
}: {
  workspace: Workspace;
  children: React.ReactNode;
}) {
  return <Context.Provider value={workspace}>{children}</Context.Provider>;
}
export function useWorkspace() {
  return useContext(Context);
}
export function workspaceHref(href: string, workspace: Workspace) {
  return href.startsWith("/") &&
    !href.startsWith("//") &&
    !href.startsWith("/workspaces/") &&
    !["/login", "/api/"].some((p) => href.startsWith(p))
    ? `/workspaces/${workspace}${href}`
    : href;
}
export function WorkspaceLink({
  href,
  ...props
}: LinkProps & Omit<AnchorHTMLAttributes<HTMLAnchorElement>, keyof LinkProps>) {
  const workspace = useWorkspace();
  return (
    <Link
      {...props}
      href={
        typeof href === "string"
          ? workspaceHref(href, workspace)
          : {
              ...href,
              pathname: workspaceHref(href.pathname ?? "/", workspace),
            }
      }
    />
  );
}
export function useWorkspaceRouter() {
  const router = useRouter(),
    workspace = useWorkspace();
  return {
    ...router,
    push: (href: string) => router.push(workspaceHref(href, workspace)),
    replace: (href: string) => router.replace(workspaceHref(href, workspace)),
  };
}
// A full navigation discards the prior workspace’s cached server layout and data.
export function WorkspaceSwitcher() {
  const current = useWorkspace(),
    pathname = usePathname();
  let path =
    pathname.replace(/^\/workspaces\/(test|live-beta)/, "") || "/dashboard";
  if (
    /^\/(drivers|riders|rides|support|promotions|vehicle-library)\//.test(path)
  )
    path = "/" + path.split("/")[1];
  return (
    <div className="mx-3 mb-3 rounded-xl border border-line bg-grouped p-1">
      <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-muted">
        Workspace
      </p>
      <div className="grid grid-cols-2 gap-1">
        {(["test", "live-beta"] as const).map((id) => (
          <a
            key={id}
            href={`/workspaces/${id}${path}`}
            aria-current={id === current ? "page" : undefined}
            className={`rounded-lg px-2 py-2 text-center text-xs font-semibold ${id === current ? "bg-white text-rydr-burgundy shadow-sm" : "text-muted hover:bg-white/70"}`}
          >
            {id === "test" ? "Test" : "Live Beta"}
          </a>
        ))}
      </div>
    </div>
  );
}
