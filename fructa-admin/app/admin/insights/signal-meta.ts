// Human-readable meanings for the signal engine's keys and tokens, plus the
// sample fund used to render live previews. THIS FILE IS THE ONE PLACE to fix
// wording. The meanings are inferred from the key/token names and standard fund
// metrics; entries marked `unsure` are genuine guesses, confirm them against the
// engine that scores keys and fills tokens, then drop the flag.

export type Tag = "STRENGTH" | "WATCH" | "NOTE";
export type Group = "Momentum" | "Ranking" | "Cost & access" | "Composition" | "Structure";

export const GROUPS: Group[] = ["Momentum", "Ranking", "Cost & access", "Composition", "Structure"];

export type KeyMeta = { key: string; group: Group; tag: Tag; meaning: string; unsure?: boolean };

// The 25 condition keys the engine evaluates, grouped by what they describe.
export const KEY_META: KeyMeta[] = [
  // Momentum
  { key: "upBig",       group: "Momentum",     tag: "STRENGTH", meaning: "Rate rose sharply this week, one of the biggest moves in its class." },
  { key: "upSmall",     group: "Momentum",     tag: "NOTE",     meaning: "Rate ticked up modestly this week." },
  { key: "downBig",     group: "Momentum",     tag: "WATCH",    meaning: "Rate dropped sharply this week, worth a second look." },
  { key: "downSmall",   group: "Momentum",     tag: "NOTE",     meaning: "Rate eased down slightly this week." },
  { key: "flat",        group: "Momentum",     tag: "NOTE",     meaning: "Rate held steady this week." },
  // Ranking
  { key: "top1",        group: "Ranking",      tag: "STRENGTH", meaning: "Highest-yielding fund in its class right now." },
  { key: "mgrTop",      group: "Ranking",      tag: "STRENGTH", meaning: "Run by a manager whose funds rank near the top.", unsure: true },
  { key: "mgrBig",      group: "Ranking",      tag: "NOTE",     meaning: "Run by one of the larger managers by assets.", unsure: true },
  { key: "concentrated",group: "Ranking",      tag: "WATCH",    meaning: "Holdings sit in a few names, more single-name risk." },
  { key: "diversified", group: "Ranking",      tag: "STRENGTH", meaning: "Holdings are well spread across issuers." },
  // Cost & access
  { key: "minLow",      group: "Cost & access", tag: "STRENGTH", meaning: "Low minimum to start, easy to get into." },
  { key: "minHigh",     group: "Cost & access", tag: "WATCH",    meaning: "High minimum to start." },
  { key: "feeHigh",     group: "Cost & access", tag: "WATCH",    meaning: "Management fee sits above its peers." },
  { key: "taxfree",     group: "Cost & access", tag: "STRENGTH", meaning: "Returns are tax-advantaged.", unsure: true },
  { key: "liqFast",     group: "Cost & access", tag: "STRENGTH", meaning: "Money is quick to withdraw.", unsure: true },
  { key: "insurerGap",  group: "Cost & access", tag: "NOTE",     meaning: "A cover gap the fund's insurer does not fill.", unsure: true },
  // Composition
  { key: "gokHeavy",    group: "Composition",  tag: "NOTE",     meaning: "Portfolio leans on government (GoK) securities." },
  { key: "tbillHeavy",  group: "Composition",  tag: "NOTE",     meaning: "Portfolio leans on Treasury bills." },
  { key: "corpHeavy",   group: "Composition",  tag: "WATCH",    meaning: "Portfolio leans on corporate debt.", unsure: true },
  { key: "depositHeavy",group: "Composition",  tag: "NOTE",     meaning: "Portfolio leans on bank deposits." },
  { key: "offshoreEx",  group: "Composition",  tag: "NOTE",     meaning: "Carries some offshore exposure.", unsure: true },
  { key: "unlistedEx",  group: "Composition",  tag: "WATCH",    meaning: "Holds unlisted securities.", unsure: true },
  // Structure
  { key: "usd",         group: "Structure",    tag: "NOTE",     meaning: "Denominated in US dollars, not shillings." },
  { key: "sacco",       group: "Structure",    tag: "NOTE",     meaning: "A SACCO product rather than a fund." },
  { key: "bondLock",    group: "Structure",    tag: "WATCH",    meaning: "Locks your money in for a fixed term.", unsure: true },
];

export const KEY_BY_NAME: Record<string, KeyMeta> =
  Object.fromEntries(KEY_META.map((k) => [k.key, k]));

export const KEYS: string[] = KEY_META.map((k) => k.key);

export type TokenMeta = { token: string; meaning: string; sample: string; unsure?: boolean };

// Replacement tokens the engine fills per fund, with the value used in previews.
export const TOKEN_META: TokenMeta[] = [
  { token: "n",       meaning: "Fund name",                sample: "Lofty-Corban MMF" },
  { token: "r",       meaning: "Gross yield",              sample: "14.88" },
  { token: "net",     meaning: "Yield after 15% WHT",      sample: "12.65" },
  { token: "d",       meaning: "Change this week (pp)",    sample: "+0.42" },
  { token: "rank",    meaning: "Rank in its class",        sample: "1" },
  { token: "top",     meaning: "Top fund's rate",          sample: "14.88" },
  { token: "topName", meaning: "Top fund's name",          sample: "Lofty-Corban" },
  { token: "min",     meaning: "Minimum to invest",        sample: "100" },
  { token: "fee",     meaning: "Management fee",           sample: "2.00" },
  { token: "aum",     meaning: "Assets under management",  sample: "6.2B" },
  { token: "gok",     meaning: "Govt securities share",    sample: "61" },
  { token: "tb",      meaning: "T-bill share",             sample: "44" },
  { token: "dep",     meaning: "Bank deposit share",       sample: "22" },
  { token: "cp",      meaning: "Corporate paper share",    sample: "18", unsure: true },
  { token: "liq",     meaning: "Liquidity / withdrawal",   sample: "same day", unsure: true },
  { token: "off",     meaning: "Offshore share",           sample: "0", unsure: true },
  { token: "unl",     meaning: "Unlisted share",           sample: "0", unsure: true },
];

export const SAMPLE: Record<string, string> =
  Object.fromEntries(TOKEN_META.map((t) => [t.token, t.sample]));

export const VALID_TOKENS: Set<string> = new Set(Object.keys(SAMPLE));

export function unknownTokens(text: string): string[] {
  const found = [...text.matchAll(/\{([^}]+)\}/g)].map((m) => m[1].trim());
  return [...new Set(found.filter((t) => !VALID_TOKENS.has(t)))];
}

// Substitute {tokens} with the sample fund's values. Unknown tokens stay literal
// so the token warning can flag them.
export function fillTemplate(t: string): string {
  return t.replace(/\{([^}]+)\}/g, (m, key) => SAMPLE[String(key).trim()] ?? m);
}
