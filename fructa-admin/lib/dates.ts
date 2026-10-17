/**
 * Date formatting shared by server and client components.
 *
 * Every admin date renders in Nairobi time with a fixed layout built from
 * numeric parts, so the HTML from Firebase App Hosting (UTC) matches what the
 * browser hydrates, whatever the viewer's locale or ICU version.
 */

const TZ = "Africa/Nairobi";
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const partsFmt = new Intl.DateTimeFormat("en-US", {
  timeZone: TZ,
  year: "numeric",
  month: "numeric",
  day: "numeric",
  hour: "numeric",
  minute: "numeric",
  hourCycle: "h23",
});

type DateInput = string | number | Date | null | undefined;

/** Numeric date and time parts in Nairobi time, or null for a missing or bad value. */
function nairobiParts(v: DateInput) {
  if (v === null || v === undefined || v === "") return null;
  const d = v instanceof Date ? v : new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    Number(partsFmt.formatToParts(d).find((p) => p.type === type)?.value ?? 0);
  return { y: get("year"), m: get("month"), d: get("day"), h: get("hour") % 24, min: get("minute") };
}

/** "17 Oct 2026", or "" when the value is missing or invalid. */
export function fmtDate(v: DateInput): string {
  const p = nairobiParts(v);
  return p ? `${p.d} ${MONTHS[p.m - 1]} ${p.y}` : "";
}

/** "17 Oct 2026, 21:56", or "" when the value is missing or invalid. */
export function fmtDateTime(v: DateInput): string {
  const p = nairobiParts(v);
  if (!p) return "";
  const hh = String(p.h).padStart(2, "0");
  const mm = String(p.min).padStart(2, "0");
  return `${p.d} ${MONTHS[p.m - 1]} ${p.y}, ${hh}:${mm}`;
}
