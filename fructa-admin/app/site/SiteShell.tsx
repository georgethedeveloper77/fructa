import Link from "next/link";
import GetBar from "./GetBar";
import "../landing/landing.css";
import "./site.css";

// Slim, theme-aware chrome for content pages (privacy, terms, blog, funds,
// rates). Reuses the landing's .fl tokens so it matches the brand and follows
// system light and dark. Every "get" link goes to /get, which sends a phone
// to its own store.
export default function SiteShell({
  children,
  wide = false,
}: {
  children: React.ReactNode;
  /** The rates pages carry wide tables: give them the full width. */
  wide?: boolean;
}) {
  const [y, m] = new Date(Date.now() + 3 * 3_600_000).toISOString().slice(0, 7).split("-");
  return (
    <div className="fl fl-has-getbar">
      <nav className="fl-nav">
        <div className="fl-nav-in">
          <Link className="fl-brand" href="/">
            <span className="fl-dot" />
            Fructa
          </Link>
          <div className="fl-nav-links">
            {/* Every page links to the rates hub, the month and the funds
                directory, and they link on to every fund: that two-way path
                is how Googlebot reaches every page, not just the sitemap. */}
            <Link href="/rates/money-market-funds">Rates today</Link>
            <Link href="/funds">Funds</Link>
            <Link href={`/rates/money-market-funds/${y}/${m}`}>By month</Link>
            <Link href="/blog">Learn</Link>
          </div>
          <div className="fl-nav-cta">
            <Link className="fl-btn fl-btn-gold" href="/get">
              Get the app
            </Link>
          </div>
        </div>
      </nav>

      <main className={"fl-site-main" + (wide ? " fl-site-wide" : "")}>{children}</main>

      <footer className="fl-footer">
        <div className="fl-wrap">
          <div className="fl-legal">
            <span>© {y} Fructa · Nairobi, Kenya</span>
            <span>
              <Link href="/rates/money-market-funds">Rates today</Link> · <Link href="/funds">Funds</Link> ·{" "}
              <Link href="/privacy">Privacy</Link> · <Link href="/terms">Terms</Link> · <Link href="/blog">Learn</Link>
            </span>
          </div>
        </div>
      </footer>
      <GetBar />
    </div>
  );
}
