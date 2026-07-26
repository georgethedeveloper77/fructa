/// The upload ceiling, in ONE place.
///
/// Three separate things enforce it and they must agree:
///
///   next.config.ts   experimental.serverActions.bodySizeLimit
///   extract.ts       refuses a PDF over the limit before calling the API
///   ExtractForm      refuses it in the browser, before uploading anything
///
/// When they disagree the user gets whichever error fires first, and the
/// framework's is the worst of the three: a stack trace naming a component,
/// with no mention of file size. That is what "Body exceeded 1 MB limit"
/// pointing at page.tsx line 69 actually was.
///
/// No imports, deliberately. This module is pulled into both a client
/// component and a server one, so anything server-only in here would break the
/// browser bundle.

/// 12 MB. Sized from the real corpus rather than a round number: the largest
/// sheet in the collection is a manager's range deck at around 5 MB, and the
/// Old Mutual booklet covering six funds is under 4. Twelve leaves room for a
/// scanned sheet, which is several times larger for the same content, without
/// inviting somebody to upload an annual report.
export const MAX_PDF_BYTES = 12 * 1024 * 1024;

export const MAX_PDF_LABEL = "12 MB";

export const humanBytes = (n: number) =>
  n >= 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.round(n / 1024)} KB`;

/// Why this file is too big, in words a person can act on. Null when it is fine.
export function tooBig(bytes: number): string | null {
  if (bytes <= MAX_PDF_BYTES) return null;
  return `That PDF is ${humanBytes(bytes)}, over the ${MAX_PDF_LABEL} limit. If it is a range deck, extract just this fund's pages and upload those.`;
}
