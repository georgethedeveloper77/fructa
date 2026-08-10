import Link from "next/link";
import "../landing/landing.css";
import "./site.css";

// Slim, theme-aware chrome for content pages (privacy/terms/blog/funds). Reuses
// the landing's .fl tokens so it matches the brand and follows system
// light/dark.
export default function SiteShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="fl">
      <nav className="fl-nav">
        <div className="fl-nav-in">
          <Link className="fl-brand" href="/">
            <span className="fl-dot" />
            Fructa
          </Link>
          <div className="fl-nav-links">
            <Link href="/">Home</Link>
            {/* Every fund page links back here and this links on to all of
                them. That two-way path is how Googlebot reaches 144 URLs it
                would otherwise only see in the sitemap: a sitemap invites a
                crawl, internal links are what earn one. */}
            <Link href="/funds">Rates</Link>
            <Link href="/blog">Blog</Link>
          </div>
          <div className="fl-nav-cta">
            <Link className="fl-btn fl-btn-gold" href="/get">
              Get the app
            </Link>
          </div>
        </div>
      </nav>

      <main className="fl-site-main">{children}</main>

      <footer className="fl-footer">
        <div className="fl-wrap">
          <div className="fl-legal">
            <span>© 2026 Fructa · Nairobi, Kenya</span>
            <span>
              <Link href="/funds">Rates</Link> · <Link href="/privacy">Privacy</Link> ·{" "}
              <Link href="/terms">Terms</Link> · <Link href="/blog">Blog</Link>
            </span>
          </div>
        </div>
      </footer>
    </div>
  );
}
