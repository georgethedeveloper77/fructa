import { supabaseAdmin } from "@/lib/supabase/server";
import { DEFAULT_CONTENT } from "@/app/landing/content";
import { saveBrand, saveSeo, saveLinks } from "./actions";
import { AccountSection } from "./AccountSection";
import { LandingCopy } from "./LandingCopy";
import { PublishBar } from "./PublishBar";
import { SettingsForm } from "./SettingsForm";
import { StatBand } from "./StatBand";
import { Card, Row, input } from "./ui";

export const dynamic = "force-dynamic";

// The Images section is gone with the marketing screenshots: the landing draws
// its own charts from rate_history now, so there is nothing to upload.
const NAV: { group: string; items: { id: string; label: string }[] }[] = [
  { group: "Account", items: [{ id: "account", label: "Account" }] },
  {
    group: "Site",
    items: [
      { id: "brand", label: "Brand" },
      { id: "seo", label: "SEO" },
      { id: "links", label: "App links" },
    ],
  },
  {
    group: "Landing page",
    items: [
      { id: "copy", label: "Landing copy" },
      { id: "stats", label: "Stat band" },
    ],
  },
];

export default async function SettingsPage() {
  const { data } = await supabaseAdmin().from("app_config").select("key,value");
  const raw = new Map((data ?? []).map((r) => [r.key as string, (r as { value: unknown }).value]));

  const S = (k: string, d: string) => {
    const v = raw.get(k);
    return typeof v === "string" ? v : d;
  };
  const stats = Array.isArray(raw.get("landing.stats"))
    ? (raw.get("landing.stats") as { n?: string; l?: string }[]).map((s) => ({ n: s.n ?? "", l: s.l ?? "" }))
    : DEFAULT_CONTENT.stats;

  const D = DEFAULT_CONTENT;

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-7 flex flex-wrap items-center gap-4">
        <div>
          <p className="text-xs text-faint">Admin</p>
          <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        </div>
        <div className="ml-auto">
          <PublishBar />
        </div>
      </header>

      <div className="grid gap-8 md:grid-cols-[188px_1fr] md:items-start">
        <aside className="hidden md:block">
          <nav className="sticky top-6 space-y-5">
            {NAV.map((g) => (
              <div key={g.group}>
                <div className="mb-1.5 px-2.5 text-[10px] font-semibold uppercase tracking-wider text-faint">
                  {g.group}
                </div>
                {g.items.map((it) => (
                  <a
                    key={it.id}
                    href={`#${it.id}`}
                    className="block rounded-lg px-2.5 py-1.5 text-[13.5px] text-mute hover:bg-panel hover:text-ink"
                  >
                    {it.label}
                  </a>
                ))}
              </div>
            ))}
          </nav>
        </aside>

        <div className="min-w-0 space-y-4">
          <AccountSection />

          <Card id="brand" title="Brand" note="Name and contact used across the site, the footer and metadata." badge="public">
            <SettingsForm action={saveBrand}>
              <Row label="Name" hint="Shown in the nav and the footer.">
                <input name="name" defaultValue={S("brand.name", D.brand.name)} className={input} />
              </Row>
              <Row label="Footer blurb" hint="One line under the wordmark.">
                <textarea
                  name="footer_blurb"
                  rows={3}
                  defaultValue={S("brand.footer_blurb", D.brand.footerBlurb)}
                  className={input}
                />
              </Row>
              <Row label="Contact email" hint="Public support address.">
                <input
                  name="contact_email"
                  defaultValue={S("brand.contact_email", D.brand.contactEmail)}
                  className={input}
                />
              </Row>
            </SettingsForm>
          </Card>

          <Card id="seo" title="SEO" note="The title and description that appear in search results and social cards." badge="public">
            <SettingsForm action={saveSeo}>
              <Row label="Title" hint="The search result headline. Around 60 characters.">
                <input name="title" defaultValue={S("seo.title", D.seo.title)} className={input} />
              </Row>
              <Row label="Description" hint="The grey text under the title. Around 160 characters.">
                <textarea
                  name="description"
                  rows={3}
                  defaultValue={S("seo.description", D.seo.description)}
                  className={input}
                />
              </Row>
            </SettingsForm>
          </Card>

          <Card
            id="links"
            title="App store links"
            note="Where the Get-the-app buttons point. The landing detects the device and leads with the right one."
            badge="public"
          >
            <SettingsForm action={saveLinks}>
              <Row label="Google Play" hint="The Android listing URL.">
                <input
                  name="android_url"
                  defaultValue={S("links.android_url", "")}
                  placeholder="https://play.google.com/store/apps/details?id=com.mindberzerk.fructa"
                  className={input}
                />
              </Row>
              <Row label="App Store" hint="The iOS listing URL.">
                <input
                  name="ios_url"
                  defaultValue={S("links.ios_url", "")}
                  placeholder="https://apps.apple.com/app/id..."
                  className={input}
                />
              </Row>
            </SettingsForm>
          </Card>

          <Card id="copy" title="Landing copy" note="The hero and the closing call to action. The preview updates as you type." badge="public">
            <LandingCopy
              initial={{
                hero_headline: S("landing.hero_headline", D.hero.headline),
                hero_accent: S("landing.hero_accent", D.hero.headlineAccent),
                hero_subhead: S("landing.hero_subhead", D.hero.subhead),
                hero_microtrust: S("landing.hero_microtrust", D.hero.microtrust),
                cta_headline: S("landing.cta_headline", D.cta.headline),
                cta_subhead: S("landing.cta_subhead", D.cta.subhead),
              }}
            />
          </Card>

          <Card id="stats" title="Stat band" note="The four figures above the How it works band. Clear a pair to drop it." badge="public">
            <StatBand initial={stats} />
          </Card>
        </div>
      </div>
    </div>
  );
}
