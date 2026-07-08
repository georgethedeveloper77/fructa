import { supabaseAdmin } from "@/lib/supabase/server";
import { NotifyClient } from "./NotifyClient";

export const dynamic = "force-dynamic"; // sends + log are always live

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

export default async function NotificationsPage() {
  const db = supabaseAdmin();
  let log: LogRow[] = [];
  let funds: FundOpt[] = [];
  let error: string | null = null;

  try {
    const [l, f] = await Promise.all([
      db
        .from("push_log")
        .select("id,title,body,target,segment,sent_count,status,error,created_at")
        .order("created_at", { ascending: false })
        .limit(100),
      db
        .from("funds")
        .select("id,name")
        .eq("kind", "fund")
        .neq("status", "hidden")
        .order("name"),
    ]);
    if (l.error) throw l.error;
    if (f.error) throw f.error;
    log = (l.data ?? []) as LogRow[];
    funds = (f.data ?? []) as FundOpt[];
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  const sent = log.filter((r) => r.status === "sent");
  const failed = log.filter((r) => r.status === "error");
  const kpis = {
    total: log.length,
    sent: sent.length,
    failed: failed.length,
    lastAt: log[0]?.created_at ?? null,
    recipients: sent.reduce((a, b) => a + (b.sent_count ?? 0), 0),
  };

  return (
    <div className="mx-auto max-w-4xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>
        <p className="mt-1 text-sm text-mute">
          Send a push to the app. A broadcast reaches everyone with notifications on; a
          segment send reaches only an opt-in group (weekly digest, market alerts, or the
          followers of one fund). Every send is recorded below.
        </p>
      </header>

      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">
          {error}
        </p>
      )}

      <NotifyClient funds={funds} log={log} kpis={kpis} />
    </div>
  );
}
