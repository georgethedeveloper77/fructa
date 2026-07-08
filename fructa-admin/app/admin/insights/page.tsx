import { supabaseAdmin } from "@/lib/supabase/server";
import { InsightsClient, type Template } from "./InsightsClient";

export const dynamic = "force-dynamic";

export default async function InsightsPage() {
  const db = supabaseAdmin();
  const { data, error } = await db
    .from("insight_templates")
    .select("id,key,tag,template,active")
    .order("key")
    .order("id");

  const rows = (data ?? []) as Template[];

  return (
    <div className="mx-auto max-w-4xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Insights</h1>
        <p className="mt-1 text-sm text-mute">
          Signal-bank phrasings — the app picks one deterministically per fund/day. Tokens:{" "}
          <code className="text-faint">{"{n} {r} {net} {min} {fee} {d} {liq} {tb} {cp} {gok} {dep} {off} {unl} {top} {topName} {rank} {aum}"}</code>, plus{" "}
          <code className="text-faint">{"<b>…</b>"}</code>.
        </p>
      </header>

      {error && (
        <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>
      )}

      <InsightsClient rows={rows} />
    </div>
  );
}
