'use client';

import { useEffect, useState } from 'react';
import { Inter, Space_Grotesk } from 'next/font/google';
import type { LandingContent } from './content';
import RateChart from './RateChart';

const inter = Inter({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--fl-sans' });
const grotesk = Space_Grotesk({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--fl-mono' });

const PLAY = (
  <svg className="fl-mk" viewBox="0 0 24 24">
    <defs>
      <linearGradient id="flpg" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#00E2FF" />
        <stop offset="1" stopColor="#00A0FF" />
      </linearGradient>
    </defs>
    <polygon points="4,2.5 13.2,12 4,21.5" fill="url(#flpg)" />
    <polygon points="4,2.5 13.2,12 16.6,8.6" fill="#00E676" />
    <polygon points="4,21.5 13.2,12 16.6,15.4" fill="#FFCE00" />
    <polygon points="13.2,12 16.6,8.6 20.6,12 16.6,15.4" fill="#FF3D2E" />
  </svg>
);
const APPLE = (
  <svg className="fl-mk" viewBox="0 0 24 24" fill="#fff">
    <path d="M16.4 12.7c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.8-3.5.8-.7 0-1.9-.8-3.1-.8-1.6 0-3 .9-3.9 2.4-1.6 2.9-.4 7.1 1.2 9.4.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7 1.4 0 1.8.7 3 .7 1.2 0 2-1.1 2.8-2.2.9-1.3 1.2-2.5 1.2-2.6-.1 0-2.3-.9-2.3-3.6ZM14.1 5.6c.6-.8 1.1-1.9.9-3-1 0-2.1.6-2.8 1.4-.6.7-1.1 1.8-.9 2.9 1.1.1 2.2-.5 2.8-1.3Z" />
  </svg>
);

type Platform = 'ios' | 'android' | 'other';

function StoreBadges({ links, platform }: { links: LandingContent['links']; platform: Platform }) {
  const play = (
    <a key="play" href={links.androidUrl} className={platform === 'android' ? 'detected' : ''}>
      {PLAY}
      <span>
        <span className="fl-sm">Get it on</span>
        <span className="fl-lg">Google Play</span>
      </span>
    </a>
  );
  const apple = (
    <a key="apple" href={links.iosUrl} className={platform === 'ios' ? 'detected' : ''}>
      {APPLE}
      <span>
        <span className="fl-sm">Download on the</span>
        <span className="fl-lg">App Store</span>
      </span>
    </a>
  );
  const order = platform === 'ios' ? [apple, play] : [play, apple];
  return <div className="fl-store">{order}</div>;
}

const CHECK = (
  <svg viewBox="0 0 24 24">
    <path d="M5 13l4 4L19 7" />
  </svg>
);

export default function Landing({ content }: { content: LandingContent }) {
  const [platform, setPlatform] = useState<Platform>('other');
  const [theme, setTheme] = useState<'dark' | 'light' | null>(null);

  useEffect(() => {
    const ua = navigator.userAgent || '';
    if (/iPhone|iPad|iPod/i.test(ua)) setPlatform('ios');
    else if (/Android/i.test(ua)) setPlatform('android');
  }, []);

  const current = () =>
    document.documentElement.getAttribute('data-theme') ||
    (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');

  useEffect(() => {
    setTheme(current() as 'dark' | 'light');
  }, []);

  const toggleTheme = () => {
    const next = current() === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    setTheme(next);
  };

  const ticker = [
    ['91-DAY T-BILL', '8.71%', 1],
    ['182-DAY', '8.60%', 0],
    ['364-DAY', '8.87%', 1],
    ['CBR', '8.75', null],
    ['INFLATION', '6.70', null],
    ['USD/KES', '129.4', 0],
    ['TOP MMF KES', '13.42%', 1],
    ['SACCO AVG', '10.20', null],
  ] as [string, string, number | null][];

  const tItem = (l: string, v: string, d: number | null, k: number) => (
    <span className="fl-it" key={k}>
      {l} <b>{v}</b>
      {d === 1 ? (
        <svg className="fl-caret u" viewBox="0 0 10 10">
          <path d="M5 3 8 7H2z" />
        </svg>
      ) : d === 0 ? (
        <svg className="fl-caret d" viewBox="0 0 10 10">
          <path d="M5 7 2 3h6z" />
        </svg>
      ) : null}
    </span>
  );

  const shot = (img: string | null, label: string) =>
    img ? (
      // eslint-disable-next-line @next/next/no-img-element
      <img className="fl-shot-img" src={img} alt={label} />
    ) : (
      <div className="fl-ph">{label}</div>
    );

  return (
    <div className={`fl ${inter.variable} ${grotesk.variable}`} data-theme-ready={theme ? 'true' : undefined}>
      {/* TOP TICKER */}
      <div className="fl-tickerwrap" aria-hidden="true">
        <div className="fl-ticker">
          {ticker.map((t, i) => tItem(t[0], t[1], t[2], i))}
          {ticker.map((t, i) => tItem(t[0], t[1], t[2], i + 100))}
        </div>
      </div>

      {/* NAV */}
      <nav className="fl-nav">
        <div className="fl-nav-in">
          <a className="fl-brand" href="#">
            <span className="fl-dot" />
            {content.brand.name}
          </a>
          <div className="fl-nav-links">
            <a href="#rates">Rates</a>
            <a href="#how">How it works</a>
            <a href="#data">Data</a>
          </div>
          <div className="fl-nav-cta">
            <button className="fl-ttoggle" aria-label="Toggle theme" onClick={toggleTheme}>
              {theme === 'dark' ? (
                <svg viewBox="0 0 24 24">
                  <circle cx="12" cy="12" r="4.5" />
                  <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24">
                  <path d="M21 12.8A9 9 0 1111.2 3 7 7 0 0021 12.8Z" />
                </svg>
              )}
            </button>
            <a className="fl-btn fl-btn-gold" href="#get">
              Get the app
            </a>
          </div>
        </div>
      </nav>

      {/* HERO */}
      <section className="fl-hero">
        <div className="fl-wrap fl-hero-grid">
          <div>
            <span className="fl-eyebrow">Kenya · Live yields</span>
            <h1>
              {content.hero.headline}
              <br />
              <span className="hl">{content.hero.headlineAccent}</span>
            </h1>
            <p className="fl-sub">{content.hero.subhead}</p>
            <StoreBadges links={content.links} platform={platform} />
            <div className="fl-microtrust">
              <span className="g" />
              {content.hero.microtrust}
            </div>
          </div>
          <RateChart months={content.months} tabs={content.chart} />
        </div>
      </section>

      {/* COVERAGE */}
      <section className="fl-sec" id="rates">
        <div className="fl-wrap">
          <div className="fl-sec-head">
            <span className="fl-eyebrow">One place</span>
            <h2>Every rate that matters, in one board.</h2>
            <p>
              You currently chase yields across WhatsApp groups, fund manager PDFs and spreadsheets. Fructa pulls them
              into a single ranked view and keeps it fresh.
            </p>
          </div>
          <div className="fl-cov">
            <div className="c">
              <svg viewBox="0 0 24 24">
                <path d="M3 7l9-4 9 4-9 4-9-4Z" />
                <path d="M3 12l9 4 9-4M3 17l9 4 9-4" />
              </svg>
              <h3>Money Market</h3>
              <span>KES &amp; USD · daily</span>
            </div>
            <div className="c">
              <svg viewBox="0 0 24 24">
                <rect x="3" y="4" width="18" height="16" rx="2" />
                <path d="M7 9h10M7 13h6" />
              </svg>
              <h3>T-Bills</h3>
              <span>91 · 182 · 364</span>
            </div>
            <div className="c">
              <svg viewBox="0 0 24 24">
                <path d="M4 19V5M4 19h16M8 15l3-4 3 2 4-6" />
              </svg>
              <h3>Bonds</h3>
              <span>fixed income</span>
            </div>
            <div className="c">
              <svg viewBox="0 0 24 24">
                <circle cx="12" cy="8" r="4" />
                <path d="M5 21c0-4 3-6 7-6s7 2 7 6" />
              </svg>
              <h3>SACCOs</h3>
              <span>dividend rates</span>
            </div>
            <div className="c">
              <svg viewBox="0 0 24 24">
                <path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3Z" />
              </svg>
              <h3>Insurance</h3>
              <span>guaranteed funds</span>
            </div>
          </div>
        </div>
      </section>

      {/* FEATURE 1 */}
      <section className="fl-wrap">
        <div className="fl-feat">
          <div className="fx">
            <div className="fl-shot">{shot(content.images.rank, 'Ranked rates screenshot')}</div>
          </div>
          <div>
            <span className="fl-eyebrow">Compare</span>
            <h2>Ranked, net of tax, side by side.</h2>
            <p>
              Headline rates lie. Fructa shows the net yield after 15% withholding, the real return after inflation,
              and the minimum to get in — so the ranking reflects what you actually earn.
            </p>
            <ul>
              <li>{CHECK}Gross, net and real yield on every fund</li>
              <li>{CHECK}Filter by type, currency and minimum</li>
              <li>{CHECK}Side-by-side compare, winner highlighted</li>
            </ul>
          </div>
        </div>
      </section>

      {/* FEATURE 2 */}
      <section className="fl-wrap">
        <div className="fl-feat rev">
          <div className="fx">
            <div className="fl-shot">{shot(content.images.portfolio, 'Portfolio screenshot')}</div>
          </div>
          <div>
            <span className="fl-eyebrow">Your money</span>
            <h2>Your holdings, on top of the market.</h2>
            <p>
              Add what you already hold and Fructa overlays it on the live board. See your blended yield, projected
              earnings, and whether your money is sitting in a fund that&apos;s slipped down the ranking.
            </p>
            <ul>
              <li>{CHECK}KES-consolidated total across all funds</li>
              <li>{CHECK}Projected earnings with real tax applied</li>
              <li>{CHECK}Stored on-device — we never see your balances</li>
            </ul>
          </div>
        </div>
      </section>

      {/* FEATURE 3 */}
      <section className="fl-wrap">
        <div className="fl-feat">
          <div className="fx">
            <div className="fl-shot">{shot(content.images.alerts, 'Alerts screenshot')}</div>
          </div>
          <div>
            <span className="fl-eyebrow">Move first</span>
            <h2>Know the moment a rate moves.</h2>
            <p>
              Set an alert on any fund or benchmark. When a rate crosses your threshold, a T-bill auction prints, or a
              fund you hold slips, Fructa tells you — before the WhatsApp group does.
            </p>
            <ul>
              <li>{CHECK}Threshold alerts on any rate</li>
              <li>{CHECK}T-bill auction and maturity reminders</li>
              <li>{CHECK}Weekly digest of where rates landed</li>
            </ul>
          </div>
        </div>
      </section>

      {/* STAT BAND */}
      <section className="fl-band" id="data">
        <div className="fl-band-in">
          {content.stats.map((s, i) => (
            <div className="fl-stat" key={i}>
              <div className="n">{s.n}</div>
              <div className="l">{s.l}</div>
            </div>
          ))}
        </div>
      </section>

      {/* HOW */}
      <section className="fl-sec" id="how">
        <div className="fl-wrap">
          <div className="fl-sec-head">
            <span className="fl-eyebrow">How it works</span>
            <h2>Three taps to a clearer picture.</h2>
          </div>
          <div className="fl-steps">
            <div className="fl-step">
              <div className="no">01</div>
              <h3>Open the board</h3>
              <p>Every Kenyan rate, ranked and live, the second you land — no account required to look.</p>
            </div>
            <div className="fl-step">
              <div className="no">02</div>
              <h3>Add your holdings</h3>
              <p>Enter what you hold. It stays on your device and overlays onto the live market instantly.</p>
            </div>
            <div className="fl-step">
              <div className="no">03</div>
              <h3>Set your alerts</h3>
              <p>Pick the rates you care about and let Fructa watch them for you, day and night.</p>
            </div>
          </div>
        </div>
      </section>

      {/* FINAL CTA */}
      <section className="fl-final" id="get">
        <div className="fl-wrap">
          <span className="fl-eyebrow">Free to start</span>
          <h2>{content.cta.headline}</h2>
          <p>{content.cta.subhead}</p>
          <StoreBadges links={content.links} platform={platform} />
        </div>
      </section>

      {/* FOOTER */}
      <footer className="fl-footer">
        <div className="fl-wrap">
          <div className="fl-foot">
            <div>
              <div className="fl-brand" style={{ marginBottom: 14 }}>
                <span className="fl-dot" />
                {content.brand.name}
              </div>
              <p className="fl-foot-blurb">{content.brand.footerBlurb}</p>
            </div>
            <div className="fl-foot-links">
              <div className="fl-foot-col">
                <h4>Product</h4>
                <a href="#rates">Rates</a>
                <a href="#how">How it works</a>
                <a href="#data">Data sources</a>
              </div>
              <div className="fl-foot-col">
                <h4>Company</h4>
                <a href={`mailto:${content.brand.contactEmail}`}>Contact</a>
                <a href="/privacy">Privacy</a>
                <a href="/terms">Terms</a>
              </div>
              <div className="fl-foot-col">
                <h4>Get the app</h4>
                <a href={content.links.androidUrl}>Google Play</a>
                <a href={content.links.iosUrl}>App Store</a>
              </div>
            </div>
          </div>
          <div className="fl-legal">
            <span>© 2026 {content.brand.name} · Nairobi, Kenya</span>
            <span>fructa.africa</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
