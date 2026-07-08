import Link from "next/link";
import "../landing/landing.css";
import "./site.css";

// Slim, theme-aware chrome for content pages (privacy/terms/blog). Reuses the
// landing's .fl tokens so it matches the brand and follows system light/dark.
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
            <Link href="/blog">Blog</Link>
          </div>
          <div className="fl-nav-cta">
            <Link className="fl-btn fl-btn-gold" href="/#get">
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
              <Link href="/privacy">Privacy</Link> · <Link href="/terms">Terms</Link> ·{" "}
              <Link href="/blog">Blog</Link>
            </span>
          </div>
        </div>
      </footer>
    </div>
  );
}
