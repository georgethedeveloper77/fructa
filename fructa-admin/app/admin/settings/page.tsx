import { supabaseAdmin } from "@/lib/supabase/server";
import { DEFAULT_CONTENT } from "@/app/landing/content";
import { saveBrand, saveSeo, saveLinks, saveCopy, saveStats } from "./actions";
import { MarketingImageCell } from "./MarketingImageCell";
import { AccountSection } from "./AccountSection";

export const dynamic = "force-dynamic";

const input =
  "w-full rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none placeholder:text-faint focus:border-gold/60";
const saveBtn =
  "rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20";

function Field({
  label,
  name,
  defaultValue,
  placeholder,
  multiline,
}: {
  label: string;
  name: string;
  defaultValue: string;
  placeholder?: string;
  multiline?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-[10px] uppercase tracking-wider text-faint">{label}</span>
      {multiline ? (
        <textarea name={name} rows={3} defaultValue={defaultValue} placeholder={placeholder} className={input} />
      ) : (
        <input name={name} defaultValue={defaultValue} placeholder={placeholder} className={input} />
      )}
    </label>
  );
}

function Section({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <section className="rounded-xl border border-line bg-panel p-5">
      <div className="mb-4">
        <h2 className="text-sm font-semibold text-ink">{title}</h2>
        {note && <p className="mt-0.5 text-xs text-mute">{note}</p>}
      </div>
      {children}
    </section>
  );
}

export default async function SettingsPage() {
  const { data } = await supabaseAdmin().from("app_config").select("key,value");
  const raw = new Map((data ?? []).map((r) => [r.key as string, (r as { value: unknown }).value]));

  const S = (k: string, d: string) => {
    const v = raw.get(k);
    return typeof v === "string" ? v : d;
  };
  const IMG = (k: string) => {
    const v = raw.get(k);
    return typeof v === "string" && v.trim() ? v : null;
  };
  const stats = Array.isArray(raw.get("landing.stats"))
    ? (raw.get("landing.stats") as { n?: string; l?: string }[])
    : DEFAULT_CONTENT.stats;

  const D = DEFAULT_CONTENT;

  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        <p className="mt-1 text-sm text-mute">
          Your account, brand, SEO and the public landing page at fructa.africa. Saves republish the
          snapshot; the landing re-reads on its next request.
        </p>
      </header>

      <div className="space-y-4">
        <AccountSection />

        <Section title="Brand" note="Name and contact used across the site, footer and metadata.">
          <form action={saveBrand} className="space-y-3">
            <Field label="Name" name="name" defaultValue={S("brand.name", D.brand.name)} />
            <Field label="Footer blurb" name="footer_blurb" defaultValue={S("brand.footer_blurb", D.brand.footerBlurb)} multiline />
            <Field label="Contact email" name="contact_email" defaultValue={S("brand.contact_email", D.brand.contactEmail)} />
            <div className="flex justify-end">
              <button className={saveBtn}>Save &amp; republish</button>
            </div>
          </form>
        </Section>

        <Section title="SEO" note="Title and description for search + social cards. The OG image is below.">
          <form action={saveSeo} className="space-y-3">
            <Field label="Title" name="title" defaultValue={S("seo.title", D.seo.title)} />
            <Field label="Description" name="description" defaultValue={S("seo.description", D.seo.description)} multiline />
            <div className="flex justify-end">
              <button className={saveBtn}>Save &amp; republish</button>
            </div>
          </form>
        </Section>

        <Section title="App store links" note="Where the Get-the-app buttons point. Auto-detect picks the right one per device.">
          <form action={saveLinks} className="space-y-3">
            <Field label="Google Play URL" name="android_url" defaultValue={S("links.android_url", "")} placeholder="https://play.google.com/store/apps/details?id=…" />
            <Field label="App Store URL" name="ios_url" defaultValue={S("links.ios_url", "")} placeholder="https://apps.apple.com/app/…" />
            <div className="flex justify-end">
              <button className={saveBtn}>Save &amp; republish</button>
            </div>
          </form>
        </Section>

        <Section title="Landing copy" note="Hero and closing call-to-action text.">
          <form action={saveCopy} className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <Field label="Hero headline" name="hero_headline" defaultValue={S("landing.hero_headline", D.hero.headline)} />
              <Field label="Hero accent line" name="hero_accent" defaultValue={S("landing.hero_accent", D.hero.headlineAccent)} />
            </div>
            <Field label="Hero subhead" name="hero_subhead" defaultValue={S("landing.hero_subhead", D.hero.subhead)} multiline />
            <Field label="Hero microtrust line" name="hero_microtrust" defaultValue={S("landing.hero_microtrust", D.hero.microtrust)} />
            <div className="grid grid-cols-2 gap-3">
              <Field label="CTA headline" name="cta_headline" defaultValue={S("landing.cta_headline", D.cta.headline)} />
              <Field label="CTA subhead" name="cta_subhead" defaultValue={S("landing.cta_subhead", D.cta.subhead)} />
            </div>
            <div className="flex justify-end">
              <button className={saveBtn}>Save &amp; republish</button>
            </div>
          </form>
        </Section>

        <Section title="Stat band" note="The four figures above ‘How it works’. Leave a pair blank to drop it.">
          <form action={saveStats} className="space-y-3">
            {[0, 1, 2, 3].map((i) => (
              <div key={i} className="grid grid-cols-[120px_1fr] gap-3">
                <Field label={`Figure ${i + 1}`} name={`stat_${i}_n`} defaultValue={stats[i]?.n ?? ""} placeholder="144" />
                <Field label="Label" name={`stat_${i}_l`} defaultValue={stats[i]?.l ?? ""} placeholder="funds tracked across the market" />
              </div>
            ))}
            <div className="flex justify-end">
              <button className={saveBtn}>Save &amp; republish</button>
            </div>
          </form>
        </Section>

        <Section title="Images" note="Feature screenshots and the social card. PNG or WebP; the app frames them.">
          <div className="space-y-5">
            <MarketingImageCell configKey="landing.feature_rank_image" url={IMG("landing.feature_rank_image")} hint="Feature 1 — ranked rates screenshot" />
            <MarketingImageCell configKey="landing.feature_portfolio_image" url={IMG("landing.feature_portfolio_image")} hint="Feature 2 — portfolio screenshot" />
            <MarketingImageCell configKey="landing.feature_alerts_image" url={IMG("landing.feature_alerts_image")} hint="Feature 3 — alerts screenshot" />
            <MarketingImageCell configKey="seo.og_image" url={IMG("seo.og_image")} ratio="1200 / 630" hint="Social share card — 1200×630 recommended" />
          </div>
        </Section>
      </div>
    </div>
  );
}
