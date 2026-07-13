"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/auth-browser";
import {
  IconOverview, IconFunds, IconCompanies, IconInsurers, IconAgents,
  IconSources, IconScrapers, IconImport, IconInsights, IconConfig,
  IconLearn, IconBell, IconPages, IconSettings, IconArticle, IconModeration,
  IconSearch, IconPower, IconRefresh, IconStocks, IconBrokers, IconSaccos,
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
  { href: "/admin/import", label: "Import", icon: IconImport, title: "Import", crumb: "manual lane" },
  { href: "/admin/config", label: "Config", icon: IconConfig, title: "Remote config", crumb: "app copy & flags" },
  { href: "/admin/learn", label: "Learn", icon: IconLearn, title: "Learn", crumb: "lessons & units" },
  { href: "/admin/insights", label: "Insights", icon: IconInsights, title: "Insights", crumb: "signal templates" },
];

const SITE: NavItem[] = [
  { href: "/admin/blog", label: "Blog", icon: IconArticle, title: "Blog", crumb: "articles & briefs" },
  { href: "/admin/content", label: "Content", icon: IconPages, title: "Content", crumb: "legal & marketing pages" },
  { href: "/admin/settings", label: "Settings", icon: IconSettings, title: "Settings", crumb: "brand · SEO · landing" },
];

const ALL = [...OPERATE, ...DATA, ...SITE];

function activeFor(path: string): NavItem {
  // longest-prefix match; "/admin" only matches exactly
  const hit = ALL.filter((n) => (n.href === "/admin" ? path === "/admin" : path.startsWith(n.href)))
    .sort((a, b) => b.href.length - a.href.length)[0];
  return hit ?? ALL[0];
}

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const path = usePathname();
  const current = activeFor(path);
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

  return (
    <div className="admin">
      <div className="app">
        <aside className="side">
          <div className="brand">
            <div className="lg">f</div>
            <div className="bt">fructa<span className="d">.</span></div>
            <span className="env">prod</span>
          </div>

          <div className="cmdk"><IconSearch size={14} /> Search anything <kbd>⌘K</kbd></div>

          <div className="nsec">Operate</div>
          <nav className="nav">
            {OPERATE.map((n) => (
              <Link key={n.href} href={n.href} className={isOn(n) ? "on" : undefined}>
                <span className="ni"><n.icon size={16} /></span> {n.label}
              </Link>
            ))}
          </nav>

          <div className="nsec">Data</div>
          <nav className="nav">
            {DATA.map((n) => (
              <Link key={n.href} href={n.href} className={isOn(n) ? "on" : undefined}>
                <span className="ni"><n.icon size={16} /></span> {n.label}
              </Link>
            ))}
          </nav>

          <div className="nsec">Site</div>
          <nav className="nav">
            {SITE.map((n) => (
              <Link key={n.href} href={n.href} className={isOn(n) ? "on" : undefined}>
                <span className="ni"><n.icon size={16} /></span> {n.label}
              </Link>
            ))}
          </nav>

          <div className="sfoot">
            <div className="av">G</div>
            <div style={{ flex: 1 }}>
              <div className="on">George</div>
              <div className="oe">owner · eu-central-1</div>
            </div>
            <button className="rowmenu" title="Sign out" onClick={signOut}><IconPower size={15} /></button>
          </div>
        </aside>

        <div className="main">
          <div className="top">
            <div>
              <h1>{current.title}</h1>
              <div className="crumb">{current.crumb} · {today}</div>
            </div>
            <div className="spacer" />
            {/* Pipeline stages - neutral until wired to last-run health */}
            <div className="pipeline" title="scrape → validate → write → publish">
              {["scrape", "validate", "write", "snapshot"].map((s) => (
                <span className="pn" key={s}>
                  <span className="pdot" style={{ background: "var(--muted)" }} /> {s}
                </span>
              ))}
            </div>
            <Link href="/admin/scrapers" className="btn gold"><IconRefresh size={14} /> Run pipeline</Link>
          </div>

          <div className="content">{children}</div>
        </div>
      </div>
    </div>
  );
}
