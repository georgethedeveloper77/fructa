import { supabaseAdmin } from "@/lib/supabase/server";
import { ConfigClient } from "./ConfigClient";
import type { ConfigRow } from "./actions";

export const dynamic = "force-dynamic";

// Brand / SEO / store-link / landing copy live under Settings, which has proper
// forms and image upload. Hide them here so Remote config stays operational
// (benchmarks, flags, CMA market, search, onboarding, learn).
const SETTINGS_NS = /^(brand|seo|links|landing)\./;

export default async function ConfigPage() {
  const db = supabaseAdmin();
  const { data } = await db
    .from("app_config")
    .select("key,value,description,updated_at")
    .order("key");

  const rows = ((data ?? []) as ConfigRow[]).filter((r) => !SETTINGS_NS.test(r.key));

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Remote config</h1>
        <p className="mt-1 text-sm text-mute">
          The machine values published inside the app snapshot — benchmark anchors, the Markets
          donut, feature flags, search, and onboarding copy. Every save republishes; devices pick
          changes up on their next refresh, no app release. Brand, SEO and landing copy live under{" "}
          <span className="text-gold">Settings</span>.
        </p>
      </header>
      <ConfigClient rows={rows} />
    </div>
  );
}
