import { supabaseAdmin } from "@/lib/supabase/server";
import {
  createInsurer,
  createInsuranceType, updateInsuranceType, deleteInsuranceType,
} from "./actions";
import InsurersClient, { type Insurer, type Company } from "./InsurersClient";

export const dynamic = "force-dynamic";

type InsType = { key: string; label: string; icon: string | null; status: string; ord: number; sub: string | null; lottie_url: string | null; active: boolean };

const ICONS = ["motor", "travel", "life", "medical", "home", "business", "marine"];

const INSURER_COLS =
  "id,name,company_id,currency,motor_rate,min_premium,excess_pct,excess_min,claims_days,rating,benefits,logo_domain," +
  "settle_pct,licensed_since,phone,whatsapp,email,paybill,website,brand_color,classes,signals,travel_regions,travel_cover";

export default async function InsurersPage() {
  const db = supabaseAdmin();
  const [{ data: insurers, error }, { data: companies }, { data: types }] =
    await Promise.all([
      db.from("funds").select(INSURER_COLS).eq("kind", "insurance").order("name"),
      db.from("companies").select("id,name").order("name"),
      db.from("insurance_types").select("key,label,icon,status,ord,sub,lottie_url,active").order("ord"),
    ]);

  const rows = (insurers ?? []) as Insurer[];
  const cos = (companies ?? []) as Company[];
  const tps = (types ?? []) as InsType[];

  return (
    <div className="mx-auto max-w-5xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Insurers</h1>
        <p className="mt-1 text-sm text-mute">
          {rows.length} products. Motor uses a % of vehicle value; travel is region-priced per traveller. Edits publish to the app.
        </p>
      </header>

      {/* insurance types (Insure home grid) */}
      <section className="mb-8 rounded-xl border border-line bg-panel p-4">
        <div className="mb-3">
          <h2 className="text-sm font-semibold tracking-tight">Insurance types</h2>
          <p className="mt-0.5 text-xs text-mute">
            Cards on the Insure home. A type renders only once it has a live comparison flow and real data; a type marked soon stays hidden in the app until then.
          </p>
        </div>

        <form action={createInsuranceType} className="mb-4 flex flex-wrap items-end gap-2">
          <F label="Label" name="label" placeholder="Medical" required w="w-40" />
          <F label="Key (optional)" name="key" placeholder="medical" w="w-32" />
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Icon</span>
            <select name="icon" defaultValue="" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
              <option value="">shield (default)</option>
              {ICONS.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-[11px] uppercase tracking-wider text-faint">Status</span>
            <select name="status" defaultValue="soon" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
              <option value="soon">soon</option><option value="live">live</option>
            </select>
          </label>
          <F label="Order" name="ord" placeholder="2" w="w-20" />
          <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add type</button>
        </form>

        <div className="space-y-2">
          {tps.map((tp) => (
            <form key={tp.key} action={updateInsuranceType} className="flex flex-wrap items-end gap-2 rounded-lg border border-line bg-panel2 p-3">
              <input type="hidden" name="key" value={tp.key} />
              <F label="Label" name="label" defaultVal={tp.label} w="w-36" />
              <label className="flex flex-col gap-1">
                <span className="text-[11px] uppercase tracking-wider text-faint">Icon</span>
                <select name="icon" defaultValue={tp.icon ?? ""} className="rounded-md border border-line bg-panel px-2 py-1.5 text-xs text-ink outline-none focus:border-gold/60">
                  <option value="">shield</option>
                  {ICONS.map((n) => <option key={n} value={n}>{n}</option>)}
                </select>
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[11px] uppercase tracking-wider text-faint">Status</span>
                <select name="status" defaultValue={tp.status} className="rounded-md border border-line bg-panel px-2 py-1.5 text-xs text-ink outline-none focus:border-gold/60">
                  <option value="soon">soon</option><option value="live">live</option>
                </select>
              </label>
              <F label="Order" name="ord" defaultVal={String(tp.ord)} w="w-16" />
              <F label="Subtitle" name="sub" defaultVal={tp.sub ?? ""} placeholder="optional" w="w-40" />
              <F label="Lottie URL" name="lottie_url" defaultVal={tp.lottie_url ?? ""} placeholder="animated icon (optional)" w="w-52" />
              <label className="flex items-center gap-1.5 pb-1.5 text-xs text-mute">
                <input type="checkbox" name="active" defaultChecked={tp.active} className="accent-gold" /> active
              </label>
              <span className="pb-1.5 text-[11px] text-faint">{tp.key}</span>
              <div className="ml-auto flex items-center gap-2">
                <button className="rounded-md border border-gold/50 bg-gold/10 px-3 py-1.5 text-xs font-medium text-gold hover:bg-gold/20">Save</button>
                <button formAction={deleteInsuranceType} className="rounded-md border border-bad/40 px-2.5 py-1.5 text-xs text-bad hover:bg-bad/10">Delete</button>
              </div>
            </form>
          ))}
          {tps.length === 0 && (
            <p className="rounded-lg border border-line bg-panel2 px-4 py-6 text-center text-xs text-mute">No types yet. Motor and Travel are seeded by migration 0041.</p>
          )}
        </div>
      </section>

      {/* create */}
      <form action={createInsurer} className="mb-6 flex flex-wrap items-end gap-2 rounded-xl border border-line bg-panel p-4">
        <F label="Name" name="name" placeholder="CIC General" required w="w-52" />
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Company</span>
          <select name="company_id" defaultValue="" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            <option value="">none</option>
            {cos.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-[11px] uppercase tracking-wider text-faint">Currency</span>
          <select name="currency" defaultValue="KES" className="rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60">
            <option>KES</option><option>USD</option>
          </select>
        </label>
        <button className="rounded-md border border-gold/50 bg-gold/10 px-4 py-1.5 text-sm font-medium text-gold hover:bg-gold/20">Add insurer</button>
      </form>

      {error && <p className="mb-4 rounded-lg border border-bad/40 bg-bad/10 px-4 py-3 text-sm text-bad">{error.message}</p>}

      <InsurersClient insurers={rows} companies={cos} />
    </div>
  );
}

function F({ label, name, placeholder, required, w, defaultVal }: { label: string; name: string; placeholder?: string; required?: boolean; w: string; defaultVal?: string }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] uppercase tracking-wider text-faint">{label}</span>
      <input name={name} defaultValue={defaultVal} placeholder={placeholder} required={required} className={`${w} rounded-md border border-line bg-panel2 px-3 py-1.5 text-sm text-ink outline-none focus:border-gold/60`} />
    </label>
  );
}
