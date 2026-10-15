"use client";
import { useMemo, useState } from "react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  CartesianGrid,
  XAxis,
  YAxis,
  Tooltip,
  Brush,
  BarChart,
  Bar,
} from "recharts";
import { Download, ChartNoAxesCombined } from "lucide-react";
import {
  reportingDay as day,
  inReportingWindow,
} from "@/lib/workspaceReporting";
import StatCard from "./StatCard";
export type AnalyticsRide = {
  id: string;
  at: number;
  status: string;
  paymentStatus: string;
  rideType: string;
  charge: number;
  platform: number;
  tips: number;
};
const money = (c: number) =>
  (c / 100).toLocaleString("en-US", { style: "currency", currency: "USD" });
export default function AnalyticsWorkspace({
  rides,
  onlineDrivers,
  loadedAt,
  capped,
  failed,
}: {
  rides: AnalyticsRide[];
  onlineDrivers: number | null;
  loadedAt: number;
  capped: boolean;
  failed: boolean;
}) {
  const [days, setDays] = useState(30);
  const [metric, setMetric] = useState<"charge" | "platform" | "tips">(
    "charge",
  );
  const [table, setTable] = useState(false);
  const data = useMemo(() => {
    const selected = rides.filter((r) =>
      inReportingWindow(r.at, loadedAt, days),
    );
    const buckets = new Map<
      string,
      {
        date: string;
        name: string;
        charge: number;
        platform: number;
        tips: number;
        rides: number;
      }
    >();
    for (let i = days - 1; i >= 0; i--) {
      const date = day(loadedAt - i * 86400000);
      buckets.set(date, {
        date,
        name: date,
        charge: 0,
        platform: 0,
        tips: 0,
        rides: 0,
      });
    }
    for (const r of selected) {
      const b = buckets.get(day(r.at));
      if (!b) continue;
      if (r.status === "completed") b.rides++;
      if (r.paymentStatus === "succeeded") {
        b.charge += r.charge;
        b.platform += r.platform;
        b.tips += r.tips;
      }
    }
    const mix = new Map<string, number>();
    selected
      .filter((r) => r.status === "completed")
      .forEach((r) => mix.set(r.rideType, (mix.get(r.rideType) ?? 0) + 1));
    return {
      selected,
      points: [...buckets.values()],
      mix: [...mix].map(([name, count]) => ({ name, count })),
    };
  }, [rides, days, loadedAt]);
  const paid = data.selected.filter((r) => r.paymentStatus === "succeeded");
  const total = (key: "charge" | "platform" | "tips") =>
    paid.reduce((n, r) => n + r[key], 0);
  function exportCsv() {
    const csv = [
      "Date,Rider charges USD,Estimated platform share USD,Tips USD,Completed rides",
      ...data.points.map((p) =>
        [
          p.date,
          (p.charge / 100).toFixed(2),
          (p.platform / 100).toFixed(2),
          (p.tips / 100).toFixed(2),
          p.rides,
        ].join(","),
      ),
    ].join("\r\n");
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `rydr-analytics-${days}days.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="mc-eyebrow mb-2">Performance overview</p>
          <h1 className="text-3xl font-semibold tracking-tight">Analytics</h1>
          <p className="mt-2 text-sm text-muted">
            Explore ride activity and payments. Dates shown in Eastern Time.
          </p>
        </div>
        <div className="mc-segment">
          {[7, 14, 30].map((n) => (
            <button
              key={n}
              aria-pressed={days === n}
              onClick={() => setDays(n)}
            >
              Last {n} days
            </button>
          ))}
        </div>
      </div>
      {failed && (
        <p
          role="alert"
          className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        >
          Some reporting data could not be loaded. Refresh to try again;
          unavailable totals are not financial statements.
        </p>
      )}
      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <StatCard
          label="Completed rides"
          value={data.selected.filter((r) => r.status === "completed").length}
        />
        <StatCard
          label="Rider charges · paid rides"
          value={money(total("charge"))}
        />
        <StatCard
          label="Estimated platform share"
          value={money(total("platform"))}
        />
        <StatCard
          label="Drivers online now"
          value={onlineDrivers ?? "Unavailable"}
        />
      </div>
      <section className="mc-panel">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p className="mc-eyebrow">Payment trends</p>
            <h2 className="mt-1 text-lg font-semibold">
              Every ride, in perspective
            </h2>
          </div>
          <button
            onClick={exportCsv}
            disabled={failed}
            className="flex items-center gap-2 rounded-xl border border-line px-3 py-2 text-xs"
          >
            <Download size={15} />
            Export daily totals
          </button>
        </div>
        <div className="mc-segment my-5 w-fit">
          {(["charge", "platform", "tips"] as const).map((key) => (
            <button
              key={key}
              aria-pressed={metric === key}
              onClick={() => setMetric(key)}
            >
              {key === "charge"
                ? "Rider charges"
                : key === "platform"
                  ? "Estimated platform share"
                  : "Driver tips"}
            </button>
          ))}
        </div>
        <div className="h-80 min-w-0" aria-label="Daily payment chart">
          <ResponsiveContainer width="100%" height="100%" minWidth={0}>
            <AreaChart
              key={days}
              data={data.points}
              margin={{ top: 10, right: 12, left: 10, bottom: 0 }}
              accessibilityLayer
            >
              <defs>
                <linearGradient id="revenueFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#f03567" stopOpacity={0.25} />
                  <stop offset="100%" stopColor="#9b64e8" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid
                strokeDasharray="3 5"
                vertical={false}
                stroke="#edf0f7"
              />
              <XAxis
                dataKey="date"
                tickFormatter={(v) => String(v).slice(5)}
                tick={{ fontSize: 11 }}
                minTickGap={32}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                tickFormatter={(v) => `$${Number(v) / 100}`}
                tick={{ fontSize: 11 }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip
                formatter={(v) => money(Number(v))}
                contentStyle={{ borderRadius: 14, borderColor: "#e7e9f1" }}
              />
              <Area
                type="monotone"
                dataKey={metric}
                name={
                  metric === "platform"
                    ? "Estimated platform share"
                    : metric === "tips"
                      ? "Driver tips"
                      : "Rider charges"
                }
                stroke="#e93665"
                strokeWidth={3}
                fill="url(#revenueFill)"
                isAnimationActive={false}
              />
              <Brush
                dataKey="date"
                height={24}
                stroke="#bd9cdf"
                tickFormatter={(v) => String(v).slice(5)}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
        {!paid.length && (
          <p className="mt-3 text-center text-sm text-muted">
            No successful payments in this reporting window.
          </p>
        )}
        <button
          aria-expanded={table}
          onClick={() => setTable(!table)}
          className="mt-5 text-xs font-medium text-rydr-burgundy"
        >
          {table ? "Hide" : "View"} accessible data table
        </button>
        {table && (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left">
              <caption className="sr-only">
                Daily payment totals in Eastern Time
              </caption>
              <thead>
                <tr>
                  {[
                    "Date",
                    "Rider charges",
                    "Estimated platform share",
                    "Tips",
                    "Completed rides",
                  ].map((h) => (
                    <th className="px-3" key={h}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {data.points.map((p) => (
                  <tr key={p.date}>
                    <td className="px-3">{p.date}</td>
                    <td>{money(p.charge)}</td>
                    <td>{money(p.platform)}</td>
                    <td>{money(p.tips)}</td>
                    <td>{p.rides}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <div className="grid gap-5 lg:grid-cols-2">
        <section className="mc-panel">
          <p className="mc-eyebrow">Completed rides</p>
          <h2 className="mt-1 text-lg font-semibold">Ride type mix</h2>
          {data.mix.length ? (
            <div className="mt-5 h-64">
              <ResponsiveContainer width="100%" height="100%" minWidth={0}>
                <BarChart data={data.mix} layout="vertical" accessibilityLayer>
                  <CartesianGrid horizontal={false} stroke="#edf0f7" />
                  <XAxis type="number" allowDecimals={false} />
                  <YAxis
                    type="category"
                    dataKey="name"
                    width={130}
                    tick={{ fontSize: 11 }}
                  />
                  <Tooltip />
                  <Bar
                    dataKey="count"
                    name="Completed rides"
                    fill="#9c58cf"
                    radius={[0, 6, 6, 0]}
                    isAnimationActive={false}
                  />
                </BarChart>
              </ResponsiveContainer>
            </div>
          ) : (
            <div className="mc-empty">
              <ChartNoAxesCombined size={32} />
              Completed rides will appear here.
            </div>
          )}
        </section>
        <section className="mc-panel">
          <p className="mc-eyebrow">Payment health</p>
          <h2 className="mt-1 text-lg font-semibold">Status breakdown</h2>
          <div className="mt-5 space-y-3">
            {[...new Set(data.selected.map((r) => r.paymentStatus))].map(
              (status) => (
                <div
                  key={status}
                  className="flex justify-between border-b border-line py-3 text-sm"
                >
                  <span className="capitalize">
                    {status.replaceAll("_", " ")}
                  </span>
                  <strong>
                    {
                      data.selected.filter((r) => r.paymentStatus === status)
                        .length
                    }
                  </strong>
                </div>
              ),
            )}
            {!data.selected.length && (
              <p className="py-10 text-center text-sm text-muted">
                No ride records in this window.
              </p>
            )}
          </div>
        </section>
      </div>
      <p className="text-xs leading-relaxed text-muted">
        Reporting sample: {rides.length} most recently updated rides
        {capped ? " (500-record limit reached; totals may be incomplete)" : ""}.
        This is an operational view, not an accounting ledger. Charges use final
        rider totals when present, otherwise estimates. Platform share is
        estimated. Loaded{" "}
        {new Date(loadedAt).toLocaleString("en-US", {
          timeZone: "America/New_York",
        })}{" "}
        ET.
      </p>
    </div>
  );
}
