// USD/KES for portfolio conversion, fetched server-side by the aggregator and
// upserted into fx_rates so the app stays keyless.
//
// Primary source is a free, keyless FX API (open.er-api.com). If CBK_FX_URL is
// set it's tried FIRST as an override — but the parse of the CBK page is a
// heuristic (find the US DOLLAR row, take a plausible number), so verify it
// against a saved fixture before relying on it. Returns null only if every
// source fails, so a bad fetch never breaks the scrape run.

export interface FxPoint {
  pair: string; // 'USD/KES'
  rate: number;
  as_of: string; // YYYY-MM-DD (EAT)
}

function eatToday(): string {
  return new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 10);
}

function plausible(n: unknown): number | null {
  return typeof n === "number" && n >= 90 && n <= 250
    ? Number(n.toFixed(4))
    : null;
}

// Optional CBK override — heuristic parse of the indicative-rates page.
function parseUsdKes(text: string): number | null {
  const seg = text.match(/US\s*DOLLAR[\s\S]{0,200}/i)?.[0] ??
    text.match(/\bUSD\b[\s\S]{0,200}/i)?.[0] ??
    text;
  const nums = [...seg.matchAll(/(\d{2,3}(?:\.\d{1,4})?)/g)].map((m) =>
    Number(m[1])
  );
  const band = nums.filter((n) => n >= 90 && n <= 250);
  if (band.length === 0) return null;
  const take = band.slice(0, 2); // buy/sell mean ≈ indicative mean
  return Number((take.reduce((a, b) => a + b, 0) / take.length).toFixed(4));
}

async function fromCbk(url: string): Promise<number | null> {
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "fructaBot/0.1 (+https://fructa.app)" },
    });
    if (!res.ok) return null;
    return parseUsdKes(await res.text());
  } catch {
    return null;
  }
}

// Free, no key, generous limits. Shape: { result, rates: { KES: <num>, ... } }.
async function fromOpenErApi(): Promise<number | null> {
  try {
    const res = await fetch("https://open.er-api.com/v6/latest/USD");
    if (!res.ok) return null;
    const j = await res.json();
    return plausible(j?.rates?.KES);
  } catch {
    return null;
  }
}

export async function fetchUsdKes(): Promise<FxPoint | null> {
  const cbkUrl = Deno.env.get("CBK_FX_URL");
  let rate: number | null = cbkUrl ? await fromCbk(cbkUrl) : null;
  rate ??= await fromOpenErApi();
  if (rate == null) return null;
  return { pair: "USD/KES", rate, as_of: eatToday() };
}
