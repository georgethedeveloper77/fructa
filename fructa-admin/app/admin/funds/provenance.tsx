// Rate provenance: where a fund's current rate came from, read off the latest
// rate_history row (source + as_of). The source strings are written by the
// ingestion lanes themselves, so this maps them rather than guessing:
//   setRate            -> source "manual"   (actions.ts)
//   applyFundImport    -> source "import"   (actions.ts)
//   scrape-aggregator  -> adapter name, e.g. "industry-table" / "press-mmf"
//   consensus writer   -> source "consensus" (lights up automatically if used)
// Any other non-null source is treated as an automated scrape and shows its raw
// string as the sub-label, so an unrecognised lane is labelled honestly, never
// mislabelled. Icons come from _icons per the house rule.
import { IconScrapers, IconImport, IconEdit, IconCheck } from "../_icons";
import type { SVGProps } from "react";

type IconCmp = (p: SVGProps<SVGSVGElement> & { size?: number }) => React.ReactElement;

export type Provenance = { source: string | null; asOf: string | null };

type Lane = { key: string; label: string; cls: string; Icon: IconCmp; showRaw: boolean };

function laneFor(source: string | null): Lane | null {
  if (!source) return null;
  const s = source.trim().toLowerCase();
  if (s === "manual") return { key: "manual", label: "MANUAL", cls: "bg-gold/10 text-gold", Icon: IconEdit, showRaw: false };
  if (s === "import") return { key: "import", label: "IMPORTED", cls: "bg-blue/10 text-blue", Icon: IconImport, showRaw: false };
  if (s === "consensus") return { key: "consensus", label: "CONSENSUS", cls: "bg-violet/10 text-violet", Icon: IconCheck, showRaw: false };
  // adapter names and any other automated source fall here
  return { key: "scraped", label: "SCRAPED", cls: "bg-ok/10 text-ok", Icon: IconScrapers, showRaw: true };
}

// as_of is a YYYY-MM-DD day stamp (EAT). Age in whole days, UTC-anchored.
function daysSince(asOf: string | null): number | null {
  if (!asOf) return null;
  const t = Date.parse(`${asOf}T00:00:00Z`);
  if (!Number.isFinite(t)) return null;
  return Math.floor((Date.now() - t) / 86_400_000);
}

function freshTone(days: number | null): "ok" | "warn" | "faint" {
  if (days == null) return "faint";
  if (days <= 2) return "ok";
  if (days <= 13) return "warn";
  return "faint";
}

function ageLabel(days: number | null): string {
  if (days == null) return "no rate";
  if (days <= 0) return "today";
  if (days === 1) return "1d ago";
  if (days < 31) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return months === 1 ? "1mo ago" : `${months}mo ago`;
}

const DOT: Record<"ok" | "warn" | "faint", string> = {
  ok: "bg-ok",
  warn: "bg-warn",
  faint: "bg-faint",
};

/** Small freshness dot + relative age, driven by the latest as_of. */
export function FreshDot({ asOf }: { asOf: string | null }) {
  const days = daysSince(asOf);
  const tone = freshTone(days);
  return (
    <span className="inline-flex items-center gap-1.5 text-[11px] text-faint">
      <span className={"h-1.5 w-1.5 shrink-0 rounded-full " + DOT[tone]} />
      <span className="tnum">{ageLabel(days)}</span>
    </span>
  );
}

/** Provenance badge for a single rate lane. Returns null when there is no rate. */
export function ProvenanceBadge({ source }: { source: string | null }) {
  const lane = laneFor(source);
  if (!lane) return null;
  const { label, cls, Icon } = lane;
  return (
    <span className={"inline-flex items-center gap-1 rounded-md px-2 py-0.5 font-mono text-[11px] font-medium " + cls}>
      <Icon size={12} /> {label}
    </span>
  );
}

/** Table cell: badge on top, adapter name (if any) + freshness underneath. */
export function ProvenanceCell({ p }: { p?: Provenance }) {
  const source = p?.source ?? null;
  const asOf = p?.asOf ?? null;
  const lane = laneFor(source);

  if (!lane) {
    // no rate history yet
    return (
      <span className="inline-flex items-center gap-1.5 text-[11px] text-faint">
        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-faint" /> no rate yet
      </span>
    );
  }

  return (
    <div className="flex flex-col gap-1">
      <ProvenanceBadge source={source} />
      <div className="flex items-center gap-2">
        {lane.showRaw && source ? <span className="font-mono text-[10px] text-faint">{source}</span> : null}
        <FreshDot asOf={asOf} />
      </div>
    </div>
  );
}
