'use client';

/*
 * The mark is the product: a rate that climbs, printed inside a terminal key.
 * The crest dot is the same gold pip the terminal uses for LIVE, so the logo and
 * the data share one vocabulary. Scales by font-size, so a single component
 * serves the nav, the footer and the favicon.
 *
 * The lockup sets FRUCTA in the mono face with wide tracking. The mono is what
 * every number on the site is set in, so the name reads as part of the readout
 * rather than as a sticker applied to it.
 */

export function Wordmark({
  size = 15,
  domain = false,
}: {
  /** wordmark font-size in px; the mark scales with it */
  size?: number;
  /** append .africa in the faint tone (footer lockup) */
  domain?: boolean;
}) {
  const box = Math.round(size * 1.5);
  return (
    <span className="fl-wm" style={{ fontSize: size }}>
      <svg
        className="fl-wm-mark"
        width={box}
        height={box}
        viewBox="0 0 24 24"
        aria-hidden="true"
        focusable="false"
      >
        <rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6.5" className="fl-wm-key" />
        <path d="M5 16.5 9.5 12l3 2.6L19 7.5" className="fl-wm-line" />
        <circle cx="19" cy="7.5" r="2.1" className="fl-wm-pip" />
      </svg>
      <span className="fl-wm-type">
        FRUCTA
        {domain && <span className="fl-wm-tld">.africa</span>}
      </span>
    </span>
  );
}
