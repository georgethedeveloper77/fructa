import { supabaseAdmin } from "@/lib/supabase/server";

/** The app-link settings from app_config (admin Config, applinks.* keys). */
export async function appLinkConfig() {
  const out = {
    androidPackage: "com.mindberzerk.fructa",
    androidSha256: [] as string[],
    iosTeamId: "",
    iosBundleId: "com.mindberzerk.fructa",
    paths: ["/funds/*", "/rates/*"],
  };
  try {
    const { data } = await supabaseAdmin().from("app_config").select("key,value").like("key", "applinks.%");
    const v = new Map((data ?? []).map((r) => [r.key as string, r.value as unknown]));
    const str = (k: string) => (typeof v.get(k) === "string" ? (v.get(k) as string).trim() : "");
    const list = (k: string) =>
      Array.isArray(v.get(k)) ? (v.get(k) as unknown[]).map(String).map((s) => s.trim()).filter(Boolean) : [];
    if (str("applinks.android_package")) out.androidPackage = str("applinks.android_package");
    out.androidSha256 = list("applinks.android_sha256").map((s) => s.toUpperCase());
    out.iosTeamId = str("applinks.ios_team_id");
    if (str("applinks.ios_bundle_id")) out.iosBundleId = str("applinks.ios_bundle_id");
    if (list("applinks.paths").length) out.paths = list("applinks.paths");
  } catch {
    // Serve what we have; an empty list simply means links open in the browser.
  }
  return out;
}
