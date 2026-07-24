"use client";

import { FormEvent, useMemo, useState } from "react";
import type React from "react";
import { useRouter } from "next/navigation";

type CampusOption = { id: string; name?: string; city?: string; state?: string };
type OrgOption = {
  id: string;
  name?: string;
  campusId?: string;
  campusName?: string;
  publicEmail?: string;
  leaderName?: string;
  relevanceScore?: number;
};

export function CampusForm() {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await postForm(event.currentTarget, "/api/campus-growth/campuses", setBusy, setMessage, router.refresh);
  }

  return (
    <FormShell title="Add campus" message={message} busy={busy}>
      <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
        <Input name="name" label="Campus name" required />
        <Input name="market" label="Market" placeholder="NYC / NJ" />
        <Input name="city" label="City" />
        <Input name="state" label="State" placeholder="NY" />
        <Select name="priority" label="Priority" options={["low", "medium", "high"]} defaultValue="medium" />
        <Select name="status" label="Status" options={["researching", "active", "paused", "archived"]} defaultValue="researching" />
        <Input name="owner" label="Owner" />
        <Input name="tags" label="Tags" placeholder="commuter, beta, nyc" />
        <TextArea name="notes" label="Notes" className="md:col-span-2" />
        <Submit busy={busy} label="Save campus" />
      </form>
    </FormShell>
  );
}

export function OrganizationForm({ campuses }: { campuses: CampusOption[] }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await postForm(event.currentTarget, "/api/campus-growth/organizations", setBusy, setMessage, router.refresh);
  }

  return (
    <FormShell title="Add public organization lead" message={message} busy={busy}>
      <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
        <CampusSelect campuses={campuses} />
        <Input name="name" label="Organization" required />
        <Input name="category" label="Category" placeholder="CS club, entrepreneurship, commuter org" />
        <Input name="publicEmail" label="Public email" type="email" />
        <Input name="leaderName" label="Public contact name" />
        <Input name="leaderTitle" label="Public contact title" />
        <Input name="website" label="Website" />
        <Input name="socialUrl" label="Social URL" />
        <Input name="instagramUrl" label="Instagram org URL" />
        <Input name="linkedInUrl" label="LinkedIn org URL" />
        <Input name="discordUrl" label="Discord invite URL" />
        <Input name="facebookUrl" label="Facebook page URL" />
        <Input name="tiktokUrl" label="TikTok public URL" />
        <Input name="meetingSchedule" label="Meeting schedule" />
        <Input name="estimatedStudentReach" label="Estimated reach" type="number" min={0} />
        <Input name="tags" label="Tags" placeholder="hackathon, cs, ambassador" />
        <Input name="owner" label="Owner" />
        <Select name="priorityLevel" label="Priority" options={["low", "medium", "high"]} defaultValue="medium" />
        <Select name="relationshipStrength" label="Relationship" options={["cold", "warm", "active", "partner"]} defaultValue="cold" />
        <Input name="source" label="Source" placeholder="Official campus page" />
        <Select name="status" label="Status" options={["new", "qualified", "queued", "contacted", "replied", "archived"]} defaultValue="new" />
        <TextArea name="description" label="Description" className="md:col-span-2" />
        <TextArea name="meetingNotes" label="Meeting notes" className="md:col-span-2" />
        <TextArea name="notes" label="Notes" className="md:col-span-2" />
        <Submit busy={busy} label="Save lead" />
      </form>
    </FormShell>
  );
}

export function EventForm({ campuses }: { campuses: CampusOption[] }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await postForm(event.currentTarget, "/api/campus-growth/events", setBusy, setMessage, router.refresh);
  }

  return (
    <FormShell title="Add public event lead" message={message} busy={busy}>
      <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
        <CampusSelect campuses={campuses} />
        <Input name="name" label="Event" required />
        <Input name="venue" label="Venue" />
        <Input name="category" label="Category" placeholder="career fair, hackathon, student event" />
        <Input name="startsAt" label="Starts" type="datetime-local" />
        <Input name="eventUrl" label="Event URL" />
        <Input name="website" label="Website" />
        <Input name="estimatedStudentReach" label="Estimated reach" type="number" min={0} />
        <Input name="tags" label="Tags" placeholder="career fair, startup, beta" />
        <Input name="owner" label="Owner" />
        <Select name="priorityLevel" label="Priority" options={["low", "medium", "high"]} defaultValue="medium" />
        <Select name="relationshipStrength" label="Relationship" options={["cold", "warm", "active", "partner"]} defaultValue="cold" />
        <Input name="source" label="Source" placeholder="Ticketmaster, campus calendar, public page" />
        <Select name="status" label="Status" options={["new", "qualified", "queued", "contacted", "replied", "archived"]} defaultValue="new" />
        <TextArea name="description" label="Description" className="md:col-span-2" />
        <TextArea name="meetingNotes" label="Meeting notes" className="md:col-span-2" />
        <TextArea name="notes" label="Notes" className="md:col-span-2" />
        <Submit busy={busy} label="Save event" />
      </form>
    </FormShell>
  );
}

export function OutreachDraftForm({ campuses, organizations }: { campuses: CampusOption[]; organizations: OrgOption[] }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [selectedOrgId, setSelectedOrgId] = useState("");
  const selectedOrg = useMemo(() => organizations.find((org) => org.id === selectedOrgId), [organizations, selectedOrgId]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = Object.fromEntries(new FormData(form).entries());
    const payload = selectedOrg
      ? {
          ...data,
          targetType: "organization",
          targetId: selectedOrg.id,
          campusId: selectedOrg.campusId ?? data.campusId,
          campusName: selectedOrg.campusName ?? data.campusName,
          organizationName: selectedOrg.name ?? data.organizationName,
          recipientName: selectedOrg.leaderName ?? data.recipientName,
          recipientEmail: selectedOrg.publicEmail ?? data.recipientEmail,
          relevanceScore: selectedOrg.relevanceScore ?? 0
        }
      : data;

    setBusy(true);
    setMessage(null);
    try {
      const response = await fetch("/api/campus-growth/outreach", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to save outreach draft.");
      form.reset();
      setSelectedOrgId("");
      setMessage("Draft saved to inbox.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to save outreach draft.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <FormShell title="Create outreach draft" message={message} busy={busy}>
      <form key={selectedOrgId || "manual"} onSubmit={submit} className="grid gap-3 md:grid-cols-2">
        <label className="space-y-1 text-xs font-medium text-muted">
          Organization lead
          <select
            value={selectedOrgId}
            onChange={(event) => setSelectedOrgId(event.target.value)}
            className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
          >
            <option value="">Manual draft</option>
            {organizations.map((org) => (
              <option key={org.id} value={org.id}>
                {org.name} {org.campusName ? `- ${org.campusName}` : ""}
              </option>
            ))}
          </select>
        </label>
        <CampusSelect campuses={campuses} />
        <Input name="organizationName" label="Organization name" defaultValue={selectedOrg?.name ?? ""} />
        <Input name="recipientName" label="Recipient name" defaultValue={selectedOrg?.leaderName ?? ""} />
        <Input name="recipientEmail" label="Recipient email" type="email" defaultValue={selectedOrg?.publicEmail ?? ""} />
        <Select
          name="channel"
          label="Channel"
          options={["email", "instagram", "facebook", "tiktok", "linkedin", "discord", "event_invitation", "internship_invitation", "ambassador_invitation", "other"]}
          defaultValue="email"
        />
        <Input name="subject" label="Subject" required className="md:col-span-2" />
        <TextArea name="body" label="Message body" required rows={8} className="md:col-span-2" />
        <div className="rounded-md border border-line bg-grouped px-3 py-2 text-xs text-muted md:col-span-2">
          Sender: support@rydr-go.com · BCC: khris.nunnally@rydr-go.com · saved for admin approval only
        </div>
        <Submit busy={busy} label="Save draft" />
      </form>
    </FormShell>
  );
}

export function AmbassadorForm({ campuses }: { campuses: CampusOption[] }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await postForm(event.currentTarget, "/api/campus-growth/ambassadors", setBusy, setMessage, router.refresh);
  }

  return (
    <FormShell title="Add ambassador candidate" message={message} busy={busy}>
      <form onSubmit={submit} className="grid gap-3 md:grid-cols-2">
        <CampusSelect campuses={campuses} />
        <Input name="name" label="Name" required />
        <Input name="email" label="Email" type="email" required />
        <Select name="status" label="Status" options={["prospect", "interview", "accepted", "active", "inactive"]} defaultValue="prospect" />
        <Input name="goals" label="Goals" placeholder="interns, riders, drivers" />
        <Input name="sourceLeadId" label="Source lead ID" />
        <TextArea name="notes" label="Notes" className="md:col-span-2" />
        <Submit busy={busy} label="Save candidate" />
      </form>
    </FormShell>
  );
}

async function postForm(
  form: HTMLFormElement,
  url: string,
  setBusy: (busy: boolean) => void,
  setMessage: (message: string | null) => void,
  refresh: () => void
) {
  setBusy(true);
  setMessage(null);
  try {
    const payload = Object.fromEntries(new FormData(form).entries());
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? "Unable to save record.");
    form.reset();
    setMessage("Saved.");
    refresh();
  } catch (error) {
    setMessage(error instanceof Error ? error.message : "Unable to save record.");
  } finally {
    setBusy(false);
  }
}

function FormShell({ title, message, busy, children }: { title: string; message: string | null; busy: boolean; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="mb-4 flex items-center justify-between gap-4">
        <h2 className="text-sm font-semibold text-ink">{title}</h2>
        {busy && <span className="text-xs text-muted">Saving...</span>}
      </div>
      {children}
      {message && <p className="mt-3 text-xs text-muted">{message}</p>}
    </div>
  );
}

function Input({
  label,
  className,
  ...props
}: React.InputHTMLAttributes<HTMLInputElement> & { label: string; className?: string }) {
  return (
    <label className={`space-y-1 text-xs font-medium text-muted ${className ?? ""}`}>
      {label}
      <input
        {...props}
        className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
      />
    </label>
  );
}

function TextArea({
  label,
  className,
  ...props
}: React.TextareaHTMLAttributes<HTMLTextAreaElement> & { label: string; className?: string }) {
  return (
    <label className={`space-y-1 text-xs font-medium text-muted ${className ?? ""}`}>
      {label}
      <textarea
        {...props}
        className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
      />
    </label>
  );
}

function Select({ label, options, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & { label: string; options: string[] }) {
  return (
    <label className="space-y-1 text-xs font-medium text-muted">
      {label}
      <select {...props} className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink">
        {options.map((option) => (
          <option key={option} value={option}>
            {option.replaceAll("_", " ")}
          </option>
        ))}
      </select>
    </label>
  );
}

function CampusSelect({ campuses }: { campuses: CampusOption[] }) {
  return (
    <label className="space-y-1 text-xs font-medium text-muted">
      Campus
      <select name="campusId" className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink">
        <option value="">Unassigned</option>
        {campuses.map((campus) => (
          <option key={campus.id} value={campus.id}>
            {campus.name} {campus.city ? `- ${campus.city}${campus.state ? `, ${campus.state}` : ""}` : ""}
          </option>
        ))}
      </select>
    </label>
  );
}

function Submit({ busy, label }: { busy: boolean; label: string }) {
  return (
    <div className="md:col-span-2">
      <button type="submit" disabled={busy} className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
        {busy ? "Saving..." : label}
      </button>
    </div>
  );
}
