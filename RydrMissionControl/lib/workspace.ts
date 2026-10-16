import "server-only";
import { headers } from "next/headers";
export type Workspace = "test" | "live-beta";
export async function currentWorkspace(): Promise<Workspace> {
  const value = (await headers()).get("x-rydr-workspace");
  if (value === "test" || value === "live-beta") return value;
  throw new Error("Workspace context is required");
}
export async function workspaceServiceURL(base: string) {
  return (
    base.replace(/\/+$/, "").replace(/\/workspaces\/(test|live-beta)$/, "") +
    "/workspaces/" +
    (await currentWorkspace())
  );
}
