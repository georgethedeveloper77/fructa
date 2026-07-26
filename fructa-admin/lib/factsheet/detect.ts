/// Work out which fund a PDF is about, from the PDF.
///
/// The form used to open with a dropdown of every fund in the database and ask
/// the operator to find the right one. That is the wrong way round: the answer
/// is written on the document, usually in 24pt at the top of page one.
///
/// SUGGESTS, DOES NOT DECIDE. Every candidate comes back with a score and the
/// words it matched on, and the caller preselects the leader only when it is
/// clearly ahead. A wrong auto-pick is worse than no auto-pick, because the
/// operator's attention has already moved on to the numbers.

export type FundLite = {
  id: string;
  name: string;
  currency: string;
  /// funds.manager. Carries the expansion of whatever the name abbreviates,
  /// which is the only thing that rescues a fund named by initials.
  manager?: string | null;
};

export type Candidate = {
  fund: FundLite;
  /// 0 to 1. Share of the fund's distinctive vocabulary present in the document.
  score: number;
  /// The words that matched, so a reviewer can see WHY rather than trust a number.
  matched: string[];
  /// True when the fund's full name appears verbatim.
  exact: boolean;
  currencyAgrees: boolean;
};

/// Words that appear in so many fund names they identify nothing. Not stripped
/// outright, because "Money Market" genuinely distinguishes an MMF from a
/// special fund; they are down-weighted by the IDF below instead. This list is
/// only for the verbatim-name check.
const FILLER = /\b(fund|funds|the|and|of|a|ltd|limited|plc|scheme|unit|trust)\b/g;

const norm = (s: string) =>
  s.toLowerCase().replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();

const tokens = (s: string) => norm(s).split(" ").filter((w) => w.length > 1);

/// Inverse document frequency across the fund list.
///
/// This is the whole trick. "Cytonn Money Market Fund" and "Cytonn High Yield
/// Special Fund" share their most obvious token, and a naive overlap score
/// cannot separate them: both look like a 33% match on any Cytonn document.
///
/// IDF fixes it by weighting a token by how RARE it is across all fund names.
/// "money" appears in sixty of them and counts for almost nothing; "cytonn"
/// appears in four; "yield" in a handful. So a sheet headed HIGH YIELD scores
/// the special fund far above the money market one, which is the distinction
/// that actually matters and the one a manual dropdown was there to make.
function buildIdf(funds: FundLite[]): Map<string, number> {
  const df = new Map<string, number>();
  for (const f of funds) {
    for (const t of new Set([...tokens(f.name), ...tokens(f.manager ?? "")])) {
      df.set(t, (df.get(t) ?? 0) + 1);
    }
  }
  const n = Math.max(funds.length, 1);
  const idf = new Map<string, number>();
  for (const [t, d] of df) idf.set(t, Math.log(n / d) + 0.1);
  return idf;
}

/// Which currency does this document talk about?
///
/// Returns null when it is ambiguous, which is common: a KES sheet mentions the
/// dollar in its market commentary. Only a clear majority counts, so the signal
/// is used as a tie-break rather than a filter.
export function detectCurrency(text: string): "KES" | "USD" | null {
  const t = text.toLowerCase();
  const kes = (t.match(/\bkes\b|\bkshs?\b|kenya shilling|shilling/g) ?? []).length;
  const usd = (t.match(/\busd\b|us dollar|\bdollar\b/g) ?? []).length;
  if (kes === 0 && usd === 0) return null;
  if (kes >= usd * 2) return "KES";
  if (usd >= kes * 2) return "USD";
  return null;
}

/// Rank funds against a document.
///
/// [filename] is included in the haystack on purpose. Managers name these files
/// descriptively and the name is often clearer than the cover page:
/// `cmmfusd-factsheet-june-26.pdf` says Cytonn Money Market Fund USD before a
/// single page is parsed.
export function detectFunds(
  text: string,
  funds: FundLite[],
  filename?: string,
): Candidate[] {
  // Only the first stretch of the document. A range deck names its subject at
  // the top of each page, while the market commentary further down mentions
  // every manager in Kenya, and scoring against all of it makes a Britam
  // commentary paragraph look like a Britam fund sheet.
  const head = text.slice(0, 6000);
  const hay = norm(`${filename ?? ""} ${head}`);
  const haySet = new Set(hay.split(" "));

  /// Does the document contain this token?
  ///
  /// Whole-word first, then substring for anything long enough to be safe.
  /// Managers do not spell their own products the way the database does: the
  /// row reads "Mansa-X Special Fund KES", which tokenises to `mansa`, while
  /// every sheet SIB publishes says "MansaX", which tokenises to `mansax`.
  /// Under strict equality those never meet, and the detector returned nothing
  /// at all for the fund this whole pipeline was designed around.
  ///
  /// Four characters is the floor. Below it substring matching starts finding
  /// `cic` inside `specific` and `kes` inside `stakes`, and a false positive
  /// here selects the wrong fund rather than merely failing to select one.
  const has = (t: string) => haySet.has(t) || (t.length >= 4 && hay.includes(t));
  const idf = buildIdf(funds);
  const docCcy = detectCurrency(head);

  const out: Candidate[] = [];
  for (const f of funds) {
    const ft = [...new Set(tokens(f.name))];
    if (ft.length === 0) continue;

    // Manager tokens, at reduced weight.
    //
    // The row is named "AA Kenya Special Fund" and every sheet African Alliance
    // publishes says "African Alliance Kenya Special Fund". No amount of string
    // matching turns AA into African Alliance, and the same holds for EIB and
    // GCIB. But funds.manager already carries the expansion, so the fund's
    // vocabulary is its name AND its manager's.
    //
    // Reduced because a manager name is supporting evidence, not identity: one
    // manager publishes eight funds, and matching on the manager alone would
    // make all eight equally plausible for any of its sheets.
    const mt = [...new Set(tokens(f.manager ?? ""))].filter((t) => !ft.includes(t));

    let total = 0;
    let hit = 0;
    let rarest = ft[0];
    let rarestW = -1;
    const matched: string[] = [];
    for (const t of ft) {
      const w = idf.get(t) ?? 1;
      total += w;
      if (w > rarestW) { rarestW = w; rarest = t; }
      if (has(t)) { hit += w; matched.push(t); }
    }
    let mRarest = "";
    let mRarestW = -1;
    for (const t of mt) {
      const w = (idf.get(t) ?? 1) * 0.6;
      total += w;
      if (w > mRarestW) { mRarestW = w; mRarest = t; }
      if (has(t)) { hit += w; matched.push(t); }
    }

    if (total === 0) continue;
    let score = hit / total;

    // THE NAME'S RAREST WORD IS THE NAME.
    //
    // Without this, "Mansa-X Special Fund KES" scored as highly on an Oak sheet
    // as Oak did, purely by matching `special`, `fund` and `kes` while its own
    // identifying word was nowhere on the page. Generic tokens accumulate, and
    // a fund with several of them can out-score the fund the document is
    // actually about.
    //
    // So a fund whose single most distinctive word is absent is heavily
    // discounted rather than merely scored lower. If the sheet does not say
    // "Mansa", it is not the MansaX sheet, however many other words line up.
    // Satisfied by the NAME's anchor or the MANAGER's, not the name's alone.
    //
    // "AA Kenya Special Fund" has `aa` as its rarest token, and `aa` is an
    // abbreviation that appears on no sheet African Alliance has ever
    // published. Requiring it discarded the fund entirely on its own fact
    // sheet, which is the opposite of what the rule is for: it exists to reject
    // funds the document is not about, not to reject the one it is.
    if (!has(rarest) && !(mRarest && has(mRarest))) score *= 0.55;

    // Verbatim name, filler removed. "Cytonn High Yield Fund" on the page is
    // about as certain as this gets.
    const bare = norm(f.name).replace(FILLER, " ").replace(/\s+/g, " ").trim();
    const exact = bare.length > 6 && hay.includes(bare);
    if (exact) score = Math.min(1, score + 0.35);

    // Currency as a tie-break, never a filter. Two rows differing only by
    // currency are the single most common near-tie in this database, and the
    // document almost always resolves it.
    const currencyAgrees = docCcy == null || docCcy === f.currency;
    if (docCcy != null) score += currencyAgrees ? 0.08 : -0.22;

    if (score >= 0.45) {
      out.push({ fund: f, score: Math.max(0, Math.min(1, score)), matched, exact, currencyAgrees });
    }
  }

  return out.sort((a, b) => b.score - a.score).slice(0, 8);
}

/// Should the UI preselect the leader?
///
/// Only when it is both strong AND clear of the runner-up. A 0.9 leading a 0.88
/// is a coin toss between two currency variants of the same fund, and
/// preselecting one of those is exactly how a dollar sheet gets applied to a
/// shilling fund.
export function shouldAutoSelect(c: Candidate[]): boolean {
  if (c.length === 0) return false;
  if (c.length === 1) return c[0].score >= 0.6;
  return c[0].score >= 0.7 && c[0].score - c[1].score >= 0.15;
}
