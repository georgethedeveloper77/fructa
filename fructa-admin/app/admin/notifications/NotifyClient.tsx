"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { sendPush, type Segment, type SendResult } from "./actions";
import { IconSend, IconCheck, IconBell } from "../_icons";

type LogRow = {
  id: number;
  title: string;
  body: string;
  target: string | null;
  segment: string;
  sent_count: number;
  status: "sent" | "error";
  error: string | null;
  created_at: string;
};
type FundOpt = { id: string; name: string };
type Kpis = { total: number; sent: number; failed: number; lastAt: string | null; recipients: number };

type TargetKind = "none" | "markets" | "portfolio" | "alerts" | "fund";
type AudienceKind = "all" | "digest_weekly" | "market_alerts" | "followers";

// Must match Push.tagKey() / the backend tagKey() exactly.
function followTag(fundId: string): string {
  return "follow_" + fundId.replace(/[^a-zA-Z0-9]/g, "_");
}

function ago(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

const inputCls =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const labelCls = "text-[11px] uppercase tracking-wider text-faint";

export function NotifyClient({
  funds,
  log,
  kpis,
}: {
  funds: FundOpt[];
  log: LogRow[];
  kpis: Kpis;
}) {
  const router = useRouter();

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [targetKind, setTargetKind] = useState<TargetKind>("none");
  const [targetFund, setTargetFund] = useState<string>("");
  const [audienceKind, setAudienceKind] = useState<AudienceKind>("all");
  const [audienceFund, setAudienceFund] = useState<string>("");

  const [confirming, setConfirming] = useState(false);
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<SendResult | null>(null);

  const fundName = (id: string) => funds.find((f) => f.id === id)?.name ?? id;

  const target = useMemo<string | undefined>(() => {
    switch (targetKind) {
      case "markets":
      case "portfolio":
      case "alerts":
        return targetKind;
      case "fund":
        return targetFund ? `fund/${targetFund}` : undefined;
      default:
        return undefined;
    }
  }, [targetKind, targetFund]);

  const segment = useMemo<Segment>(() => {
    switch (audienceKind) {
      case "digest_weekly":
        return { tag: "digest_weekly" };
      case "market_alerts":
        return { tag: "market_alerts" };
      case "followers":
        return { tag: audienceFund ? followTag(audienceFund) : "follow_" };
      default:
        return "all";
    }
  }, [audienceKind, audienceFund]);

  const audienceLabel = useMemo(() => {
    switch (audienceKind) {
      case "digest_weekly":
        return "Weekly-digest subscribers";
      case "market_alerts":
        return "Market-alert subscribers";
      case "followers":
        return audienceFund ? `Followers of ${fundName(audienceFund)}` : "Followers of a fund";
      default:
        return "Everyone with notifications on";
    }
  }, [audienceKind, audienceFund]); // eslint-disable-line react-hooks/exhaustive-deps

  const canSend =
    title.trim() !== "" &&
    body.trim() !== "" &&
    !(targetKind === "fund" && !targetFund) &&
    !(audienceKind === "followers" && !audienceFund) &&
    !sending;

  async function doSend() {
    setSending(true);
    setResult(null);
    const r = await sendPush({ title: title.trim(), body: body.trim(), target, segment });
    setSending(false);
    setConfirming(false);
    setResult(r);
    if (r.ok) {
      setTitle("");
      setBody("");
      setTargetKind("none");
      setTargetFund("");
      setAudienceKind("all");
      setAudienceFund("");
      router.refresh(); // pull the new push_log row into the history table
    }
  }

  const Kpi = ({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: "warn" | "ok" }) => (
    <div className="rounded-xl border border-line bg-panel px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-faint">{label}</div>
      <div className={"mt-0.5 text-2xl font-semibold tnum " + (tone === "warn" ? "text-warn" : tone === "ok" ? "text-live" : "text-ink")}>{value}</div>
      {sub && <div className="text-[11px] text-faint">{sub}</div>}
    </div>
  );

  return (
    <div className="space-y-4">
      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Sends logged" value={kpis.total} />
        <Kpi label="Delivered" value={kpis.sent} sub={`${kpis.recipients} recipients`} tone="ok" />
        <Kpi label="Failed" value={kpis.failed} tone={kpis.failed ? "warn" : "ok"} />
        <Kpi label="Last send" value={kpis.lastAt ? ago(kpis.lastAt) : "—"} />
      </div>

      {/* compose */}
      <div className="rounded-xl border border-line bg-panel p-4">
        <div className="mb-3 flex items-center gap-2 text-sm font-medium text-ink">
          <span className="text-gold"><IconBell size={15} /></span> Compose
        </div>

        <div className="space-y-3">
          <label className="flex flex-col gap-1">
            <span className={labelCls}>Title</span>
            <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={60}
              placeholder="e.g. T-bill auction results are in" className={inputCls} />
          </label>

          <label className="flex flex-col gap-1">
            <span className={labelCls}>Message</span>
            <textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={180} rows={2}
              placeholder="One or two lines. Keep it specific — this lands on a lock screen."
              className={inputCls + " resize-none"} />
            <span className="self-end text-[11px] text-faint tnum">{body.length}/180</span>
          </label>

          <div className="grid gap-3 sm:grid-cols-2">
            {/* audience */}
            <label className="flex flex-col gap-1">
              <span className={labelCls}>Audience</span>
              <select value={audienceKind} onChange={(e) => setAudienceKind(e.target.value as AudienceKind)}
                className={inputCls}>
                <option value="all">Everyone (broadcast)</option>
                <option value="digest_weekly">Weekly-digest subscribers</option>
                <option value="market_alerts">Market-alert subscribers</option>
                <option value="followers">Followers of a fund…</option>
              </select>
              {audienceKind === "followers" && (
                <select value={audienceFund} onChange={(e) => setAudienceFund(e.target.value)}
                  className={inputCls + " mt-1"}>
                  <option value="">Select a fund…</option>
                  {funds.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
                </select>
              )}
            </label>

            {/* deep-link target */}
            <label className="flex flex-col gap-1">
              <span className={labelCls}>Opens (on tap)</span>
              <select value={targetKind} onChange={(e) => setTargetKind(e.target.value as TargetKind)}
                className={inputCls}>
                <option value="none">App (default)</option>
                <option value="markets">Markets</option>
                <option value="portfolio">Portfolio</option>
                <option value="alerts">Alerts feed</option>
                <option value="fund">A fund…</option>
              </select>
              {targetKind === "fund" && (
                <select value={targetFund} onChange={(e) => setTargetFund(e.target.value)}
                  className={inputCls + " mt-1"}>
                  <option value="">Select a fund…</option>
                  {funds.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
                </select>
              )}
            </label>
          </div>

          {/* preview */}
          <div className="rounded-lg border border-line bg-panel2 p-3">
            <div className="mb-1 text-[10px] uppercase tracking-wider text-faint">Preview</div>
            <div className="flex items-start gap-2.5">
              <div className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-gold/15 text-gold">
                <IconBell size={14} />
              </div>
              <div className="min-w-0">
                <div className="text-sm font-medium text-ink">{title || "Fructa"}</div>
                <div className="text-xs text-mute">{body || "Your message appears here."}</div>
              </div>
            </div>
          </div>

          {/* send / confirm */}
          {!confirming ? (
            <button
              disabled={!canSend}
              onClick={() => { setResult(null); setConfirming(true); }}
              className="inline-flex items-center gap-2 rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <IconSend size={14} /> Review &amp; send
            </button>
          ) : (
            <div className="rounded-lg border border-gold/40 bg-gold/5 p-3">
              <div className="text-sm text-ink">
                Send to <span className="font-semibold text-gold">{audienceLabel}</span>? This reaches real devices.
              </div>
              <div className="mt-3 flex items-center gap-2">
                <button
                  disabled={sending}
                  onClick={doSend}
                  className="inline-flex items-center gap-2 rounded-md border border-gold/50 bg-gold/15 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/25 disabled:opacity-50"
                >
                  <IconSend size={14} /> {sending ? "Sending…" : "Confirm send"}
                </button>
                <button
                  disabled={sending}
                  onClick={() => setConfirming(false)}
                  className="rounded-md border border-line px-3 py-1.5 text-sm text-mute hover:text-ink"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          {result && (
            <div className={"flex items-center gap-2 rounded-lg border px-3 py-2 text-sm " +
              (result.ok ? "border-live/40 bg-live/10 text-live" : "border-bad/40 bg-bad/10 text-bad")}>
              {result.ok ? <IconCheck size={14} /> : null}
              {result.ok
                ? `Sent to about ${result.recipients} device${result.recipients === 1 ? "" : "s"}.`
                : `Not sent — ${result.error}`}
            </div>
          )}
        </div>
      </div>

      {/* history */}
      <div className="rounded-xl border border-line bg-panel">
        <div className="flex items-center justify-between border-b border-line px-4 py-2.5">
          <h2 className="text-sm font-medium text-ink">Send history</h2>
          <span className="text-xs text-faint">last {log.length}</span>
        </div>
        {log.length === 0 ? (
          <p className="px-4 py-10 text-center text-sm text-mute">No sends yet. Compose one above.</p>
        ) : (
          <div className="divide-y divide-line">
            {log.map((r) => (
              <div key={r.id} className="flex items-start gap-3 px-4 py-3">
                <span className={"mt-1.5 h-2 w-2 shrink-0 rounded-full " + (r.status === "sent" ? "bg-live" : "bg-bad")} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-baseline gap-2">
                    <span className="truncate text-sm font-medium text-ink">{r.title}</span>
                    <span className="shrink-0 text-[11px] text-faint">{ago(r.created_at)}</span>
                  </div>
                  <div className="truncate text-xs text-mute">{r.body}</div>
                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] text-faint">
                    <span>to <span className="text-mute">{r.segment}</span></span>
                    {r.target && <span>opens <span className="text-mute">{r.target}</span></span>}
                    <span className="tnum">{r.sent_count} recipient{r.sent_count === 1 ? "" : "s"}</span>
                    {r.status === "error" && r.error && <span className="text-bad">{r.error}</span>}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
