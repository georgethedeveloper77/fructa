"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

// Kept as its own stylesheet rather than merged into admin-theme.css. The
// responsive rules stay reviewable on their own, and a nested layout's CSS
// loads after the root's, so these land last in the cascade without needing
// specificity tricks to win.
import "./admin-responsive.css";
import { usePathname } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/auth-browser";
import {
  IconOverview, IconFunds, IconCompanies, IconInsurers, IconAgents,
  IconSources, IconScrapers, IconImport, IconInsights, IconConfig,
  IconLearn, IconBell, IconPages, IconSettings, IconArticle, IconModeration,
  IconSearch, IconPower, IconRefresh, IconStocks, IconBrokers, IconSaccos,
  IconFactsheets, IconReview,
} from "./_icons";
import type { SVGProps } from "react";

type IconCmp = (p: SVGProps<SVGSVGElement> & { size?: number }) => React.ReactElement;
type NavItem = { href: string; label: string; icon: IconCmp; title: string; crumb: string };

const OPERATE: NavItem[] = [
  { href: "/admin", label: "Overview", icon: IconOverview, title: "Overview", crumb: "rates ops" },
  { href: "/admin/funds", label: "Funds", icon: IconFunds, title: "Funds", crumb: "rate directory" },
  { href: "/admin/stocks", label: "Stocks", icon: IconStocks, title: "Stocks", crumb: "NSE listings & dividends" },
  { href: "/admin/saccos", label: "SACCOs", icon: IconSaccos, title: "SACCOs", crumb: "AGM rates & common bond" },
  { href: "/admin/companies", label: "Companies", icon: IconCompanies, title: "Companies", crumb: "providers & brands" },
  { href: "/admin/insurers", label: "Insurers", icon: IconInsurers, title: "Insurers", crumb: "motor & travel" },
  { href: "/admin/agents", label: "Agents", icon: IconAgents, title: "Agents", crumb: "contacts" },
  { href: "/admin/brokers", label: "Brokers", icon: IconBrokers, title: "Brokers", crumb: "CMA-licensed stockbrokers" },
  { href: "/admin/moderation", label: "Moderation", icon: IconModeration, title: "Moderation", crumb: "review queue" },
  { href: "/admin/notifications", label: "Notify", icon: IconBell, title: "Notifications", crumb: "push console" },
];

const DATA: NavItem[] = [
  { href: "/admin/sources", label: "Sources", icon: IconSources, title: "Sources", crumb: "provenance" },
  { href: "/admin/scrapers", label: "Scrapers", icon: IconScrapers, title: "Scrapers", crumb: "run log" },
  // Both of these existed as routes with no way in. /admin/review has been
  // shipped since the rate-review migration and /admin/factsheets since the
  // ingestion work; each was reachable only by typing its URL, which is the
  // same as not existing.
  { href: "/admin/review", label: "Review", icon: IconReview, title: "Rate review", crumb: "held rate changes" },
  { href: "/admin/factsheets", label: "Fact sheets", icon: IconFactsheets, title: "Fact sheets", crumb: "extract, review, apply" },
  { href: "/admin/import", label: "Import", icon: IconImport, title: "Import", crumb: "manual lane" },
  { href: "/admin/config", label: "Config", icon: IconConfig, title: "Remote config", crumb: "app copy & flags" },
  { href: "/admin/learn", label: "Learn", icon: IconLearn, title: "Learn", crumb: "lessons & units" },
  { href: "/admin/insights", label: "Insights", icon: IconInsights, title: "Insights", crumb: "signal templates" },
];

const SITE: NavItem[] = [
  { href: "/admin/blog", label: "Blog", icon: IconArticle, title: "Blog", crumb: "articles & briefs" },
  { href: "/admin/content", label: "Content", icon: IconPages, title: "Content", crumb: "legal & marketing pages" },
  { href: "/admin/settings", label: "Settings", icon: IconSettings, title: "Settings", crumb: "brand, SEO, landing" },
];

const ALL = [...OPERATE, ...DATA, ...SITE];

function activeFor(path: string): NavItem {
  // longest-prefix match; "/admin" only matches exactly
  const hit = ALL.filter((n) => (n.href === "/admin" ? path === "/admin" : path.startsWith(n.href)))
    .sort((a, b) => b.href.length - a.href.length)[0];
  return hit ?? ALL[0];
}

function IconMenu({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={2} strokeLinecap="round">
      <path d="M4 7h16M4 12h16M4 17h16" />
    </svg>
  );
}

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const path = usePathname();
  const current = activeFor(path);
  const [navOpen, setNavOpen] = useState(false);

  // Close on navigation. Without this a tap on a link leaves the drawer sitting
  // over the page it just opened, which reads as the tap having failed.
  useEffect(() => setNavOpen(false), [path]);

  // Escape closes it. A full-screen overlay with no keyboard exit is a trap on
  // a laptop, where this drawer also appears at narrow widths.
  useEffect(() => {
    if (!navOpen) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setNavOpen(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [navOpen]);

  const today = new Date().toLocaleDateString("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
  });

  async function signOut() {
    await supabaseBrowser().auth.signOut();
    window.location.href = "/console";
  }

  const isOn = (n: NavItem) => n.href === current.href;

  const section = (items: NavItem[]) => (
    <nav className="nav">
      {items.map((n) => (
        <Link key={n.href} href={n.href} className={isOn(n) ? "on" : undefined}>
          <span className="ni"><n.icon size={16} /></span> {n.label}
        </Link>
      ))}
    </nav>
  );

  return (
    <div className="admin">
      <div className={"app" + (navOpen ? " nav-open" : "")}>
        {/* Backdrop. Rendered always and hidden by CSS above the breakpoint, so
            the drawer's open state never leaks onto a desktop layout. */}
        <button
          className="navscrim"
          aria-label="Close navigation"
          onClick={() => setNavOpen(false)}
        />

        <aside className="side" id="admin-nav">
          <div className="brand">
            <div className="lg">f</div>
            <div className="bt">fructa<span className="d">.</span></div>
            <span className="env">prod</span>
          </div>

          <div className="cmdk"><IconSearch size={14} /> Search anything <kbd>&#8984;K</kbd></div>

          {/* The nav scrolls, the brand and the footer do not.
              Structural rather than a CSS-only fix, because a scroll region
              needs an element to be. The sidebar carries 21 rows across three
              sections plus a header and a footer, which overflows a 900px
              laptop, and an overflowing sidebar with no scroll simply hides
              whatever is at the bottom. Settings was the row falling off. */}
          <div className="sidescroll">
            <div className="nsec">Operate</div>
            {section(OPERATE)}

            <div className="nsec">Data</div>
            {section(DATA)}

            <div className="nsec">Site</div>
            {section(SITE)}
          </div>

          <div className="sfoot">
            <div className="av">G</div>
            <div style={{ flex: 1 }}>
              <div className="on">George</div>
              <div className="oe">owner &#183; eu-central-1</div>
            </div>
            <button className="rowmenu" title="Sign out" onClick={signOut}><IconPower size={15} /></button>
          </div>
        </aside>

        <div className="main">
          <div className="top">
            <button
              className="navtoggle"
              aria-label="Open navigation"
              aria-expanded={navOpen}
              aria-controls="admin-nav"
              onClick={() => setNavOpen(true)}
            >
              <IconMenu />
            </button>

            <div className="topttl">
              <h1>{current.title}</h1>
              <div className="crumb">{current.crumb} &#183; {today}</div>
            </div>
            <div className="spacer" />

            {/* Pipeline stages, neutral until wired to last-run health. Hidden
                on narrow screens: it is ambient status, and it was pushing the
                title and the action button off the row. */}
            <div className="pipeline" title="scrape, validate, write, publish">
              {["scrape", "validate", "write", "snapshot"].map((s) => (
                <span className="pn" key={s}>
                  <span className="pdot" style={{ background: "var(--muted)" }} /> {s}
                </span>
              ))}
            </div>

            <Link href="/admin/scrapers" className="btn gold runbtn">
              <IconRefresh size={14} /> <span className="runlabel">Run pipeline</span>
            </Link>
          </div>

          <div className="content">{children}</div>
        </div>
      </div>
    </div>
  );
}
