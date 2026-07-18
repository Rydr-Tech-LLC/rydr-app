"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export interface DriverProfileAdminInitial {
  firstName: string;
  lastName: string;
  email: string;
  phoneNumber: string;
  dob: string;
  address: {
    street: string;
    line2: string;
    city: string;
    state: string;
    zip: string;
  };
  license: {
    number: string;
    state: string;
  };
  vehicle: {
    year: string;
    make: string;
    model: string;
    trim: string;
    color: string;
    plate: string;
    vin: string;
    class: string;
  };
}

type AuthAction = "send_password_reset" | "send_email_verification" | "mark_email_verified";

export default function DriverProfileAdminTools({
  uid,
  initial
}: {
  uid: string;
  initial: DriverProfileAdminInitial;
}) {
  const router = useRouter();
  const [form, setForm] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [authLoading, setAuthLoading] = useState<AuthAction | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/drivers/${uid}/profile`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form)
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(body.error ?? "Unable to update driver profile.");
        return;
      }
      setMessage("Driver profile updated.");
      router.refresh();
    } finally {
      setSaving(false);
    }
  }

  async function runAuthAction(action: AuthAction) {
    if (action === "mark_email_verified" && !window.confirm("Mark this driver's email verified without sending a link?")) return;
    setAuthLoading(action);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/drivers/${uid}/auth`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(body.error ?? "Unable to complete auth action.");
        return;
      }
      setMessage(authMessage(action));
      router.refresh();
    } finally {
      setAuthLoading(null);
    }
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-1 text-sm font-semibold text-ink">Admin Profile Tools</h2>
      <p className="mb-4 text-[11px] leading-relaxed text-muted">
        Update driver account fields from Mission Control. Changes are audited and synced to Firebase Auth when applicable.
      </p>

      {message && <p className="mb-3 rounded-md bg-emerald-50 px-3 py-2 text-[11px] text-emerald-700">{message}</p>}
      {error && <p className="mb-3 rounded-md bg-rydr-red/10 px-3 py-2 text-[11px] text-rydr-red">{error}</p>}

      <div className="space-y-4">
        <FieldGroup title="Identity">
          <Input label="First name" value={form.firstName} onChange={(value) => setForm({ ...form, firstName: value })} />
          <Input label="Last name" value={form.lastName} onChange={(value) => setForm({ ...form, lastName: value })} />
          <Input label="Email" value={form.email} onChange={(value) => setForm({ ...form, email: value })} />
          <Input
            label="Phone"
            helper="Use E.164 format, for example +14045551212."
            value={form.phoneNumber}
            onChange={(value) => setForm({ ...form, phoneNumber: value })}
          />
          <Input label="Date of birth" type="date" value={form.dob} onChange={(value) => setForm({ ...form, dob: value })} />
        </FieldGroup>

        <FieldGroup title="Address">
          <Input label="Street" value={form.address.street} onChange={(value) => setNested("address", "street", value)} />
          <Input label="Line 2" value={form.address.line2} onChange={(value) => setNested("address", "line2", value)} />
          <Input label="City" value={form.address.city} onChange={(value) => setNested("address", "city", value)} />
          <Input label="State" value={form.address.state} onChange={(value) => setNested("address", "state", value)} />
          <Input label="ZIP" value={form.address.zip} onChange={(value) => setNested("address", "zip", value)} />
        </FieldGroup>

        <FieldGroup title="License">
          <Input label="License number" value={form.license.number} onChange={(value) => setNested("license", "number", value)} />
          <Input label="License state" value={form.license.state} onChange={(value) => setNested("license", "state", value)} />
        </FieldGroup>

        <FieldGroup title="Vehicle">
          <Input label="Year" value={form.vehicle.year} onChange={(value) => setNested("vehicle", "year", value)} />
          <Input label="Make" value={form.vehicle.make} onChange={(value) => setNested("vehicle", "make", value)} />
          <Input label="Model" value={form.vehicle.model} onChange={(value) => setNested("vehicle", "model", value)} />
          <Input label="Trim" value={form.vehicle.trim} onChange={(value) => setNested("vehicle", "trim", value)} />
          <Input label="Color" value={form.vehicle.color} onChange={(value) => setNested("vehicle", "color", value)} />
          <Input label="Plate" value={form.vehicle.plate} onChange={(value) => setNested("vehicle", "plate", value)} />
          <Input label="VIN" value={form.vehicle.vin} onChange={(value) => setNested("vehicle", "vin", value)} />
          <Input label="Vehicle class" value={form.vehicle.class} onChange={(value) => setNested("vehicle", "class", value)} />
        </FieldGroup>

        <button
          disabled={saving || authLoading !== null}
          onClick={save}
          className="w-full rounded-md bg-ink py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {saving ? "Saving..." : "Save Driver Updates"}
        </button>
      </div>

      <div className="mt-5 border-t border-line pt-4">
        <h3 className="mb-2 text-xs font-semibold text-ink">Auth Support</h3>
        <div className="flex flex-col gap-2">
          <button
            disabled={saving || authLoading !== null}
            onClick={() => runAuthAction("send_password_reset")}
            className="rounded-md border border-line bg-white py-2 text-xs font-semibold text-ink transition hover:bg-grouped disabled:opacity-40"
          >
            {authLoading === "send_password_reset" ? "Sending..." : "Send Password Reset Email"}
          </button>
          <button
            disabled={saving || authLoading !== null}
            onClick={() => runAuthAction("send_email_verification")}
            className="rounded-md border border-line bg-white py-2 text-xs font-semibold text-ink transition hover:bg-grouped disabled:opacity-40"
          >
            {authLoading === "send_email_verification" ? "Sending..." : "Send Email Verification"}
          </button>
          <button
            disabled={saving || authLoading !== null}
            onClick={() => runAuthAction("mark_email_verified")}
            className="rounded-md border border-line bg-white py-2 text-xs font-semibold text-ink transition hover:bg-grouped disabled:opacity-40"
          >
            {authLoading === "mark_email_verified" ? "Saving..." : "Mark Email Verified"}
          </button>
        </div>
        <p className="mt-3 text-[11px] leading-relaxed text-muted">
          Phone SMS verification codes must be sent from the driver app. Mission Control can update the phone number, but
          Firebase does not expose the client SMS verification challenge through the Admin SDK.
        </p>
      </div>
    </div>
  );

  function setNested<Group extends "address" | "license" | "vehicle">(
    group: Group,
    key: keyof DriverProfileAdminInitial[Group],
    value: string
  ) {
    setForm({
      ...form,
      [group]: {
        ...form[group],
        [key]: value
      }
    });
  }
}

function FieldGroup({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="mb-2 text-xs font-semibold text-muted">{title}</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">{children}</div>
    </div>
  );
}

function Input({
  label,
  value,
  onChange,
  type = "text",
  helper
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  helper?: string;
}) {
  return (
    <label className="block">
      <span className="text-[11px] font-medium text-muted">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs text-ink outline-none focus:border-ink"
      />
      {helper && <span className="mt-1 block text-[10px] leading-snug text-muted">{helper}</span>}
    </label>
  );
}

function authMessage(action: AuthAction): string {
  if (action === "send_password_reset") return "Password reset email sent.";
  if (action === "send_email_verification") return "Email verification sent.";
  return "Driver email marked verified.";
}
