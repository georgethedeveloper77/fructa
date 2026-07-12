'use client';

import { useEffect, useState } from 'react';
import { Inter, Space_Grotesk } from 'next/font/google';
import type { LandingCharts, LandingContent } from './content';
import { INFLATION, WHT } from './content';
import { Wordmark } from './Wordmark';
import HeroTerminal from './charts/HeroTerminal';
import NetOfTaxBars from './charts/NetOfTaxBars';
import PortfolioDonut from './charts/PortfolioDonut';
import AlertThreshold from './charts/AlertThreshold';
import MarketDonut from './charts/MarketDonut';
import YieldCurve from './charts/YieldCurve';

const inter = Inter({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--fl-sans' });
const grotesk = Space_Grotesk({ subsets: ['latin'], weight: ['400', '500', '600', '700'], variable: '--fl-mono' });

const PLAY = (
  <svg className="fl-mk" viewBox="0 0 24 24" aria-hidden="true">
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
  <svg className="fl-mk" viewBox="0 0 24 24" fill="#fff" aria-hidden="true">
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
  return <div className="fl-store">{platform === 'ios' ? [apple, play] : [play, apple]}</div>;
}

/** Feature claims read as a spec sheet, not a checklist. The key is the thing
 *  you get; the value is the condition it holds under. */
function Points({ rows }: { rows: [string, string][] }) {
  return (
    <dl className="fl-pts">
      {rows.map(([k, v]) => (
        <div className="fl-pt" key={k}>
          <dt>{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  );
}

export default function Landing({
  content,
  charts,
}: {
  content: LandingContent;
  charts: LandingCharts;
}) {
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

  // The ticker reads the same numbers the charts do, so it can never drift.
  // The curve and the benchmark chips both carry the 91d T-bill (and the chips
  // repeat CBR and inflation), so the tape is keyed by label and de-duplicated:
  // the first source to claim a label wins, and nothing prints twice.
  const lead = charts.tabs[0]?.series.find((s) => s.lead) ?? charts.tabs[0]?.series[0];
  const tape = new Map<string, string>();
  charts.curve.labels.forEach((l, i) => {
    tape.set(`${l.toUpperCase()} T-BILL`, `${charts.curve.values[i].toFixed(2)}%`);
  });
  if (lead && charts.tabs[0]) {
    tape.set(
      `TOP ${charts.tabs[0].label.toUpperCase()}`,
      `${lead.values[lead.values.length - 1].toFixed(2)}%`,
    );
  }
  for (const [k, v] of charts.tabs[0]?.benchmarks ?? []) {
    const key = k.toUpperCase();
    // the curve already printed every T-bill tenor
    if (key.includes('T-BILL')) continue;
    if (!tape.has(key)) tape.set(key, v);
  }
  const ticker = [...tape.entries()];

  const hasCharts = charts.live && charts.tabs.length > 0;

  return (
    <div className={`fl ${inter.variable} ${grotesk.variable}`} data-theme-ready={theme ? 'true' : undefined}>
      {ticker.length > 0 && (
        <div className="fl-tickerwrap" aria-hidden="true">
          <div className="fl-ticker">
            {[...ticker, ...ticker].map(([l, v], i) => (
              <span className="fl-it" key={i}>
                {l} <b>{v}</b>
              </span>
            ))}
          </div>
        </div>
      )}

      <nav className="fl-nav">
        <div className="fl-nav-in">
          <a className="fl-brandlink" href="#" aria-label={content.brand.name}>
            <Wordmark size={15} />
          </a>
          <div className="fl-nav-links">
            <a href="#rates">Rates</a>
            <a href="#market">Market</a>
            <a href="#how">How it works</a>
          </div>
          <div className="fl-nav-cta">
            <button className="fl-ttoggle" aria-label="Toggle theme" onClick={toggleTheme}>
              {theme === 'dark' ? (
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <circle cx="12" cy="12" r="4.5" />
                  <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" aria-hidden="true">
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

      <section className="fl-hero">
        <div className={'fl-wrap ' + (hasCharts ? 'fl-hero-grid' : 'fl-hero-solo')}>
          <div>
            <span className="fl-eyebrow">Kenya, live yields</span>
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
          {hasCharts && <HeroTerminal charts={charts} />}
        </div>
      </section>

      {hasCharts && (
        <>
          <section className="fl-wrap" id="rates">
            <div className="fl-feat">
              <div className="fx">
                <NetOfTaxBars funds={charts.netOfTax} />
              </div>
              <div>
                <span className="fl-eyebrow">Compare</span>
                <h2>The headline rate is not what you keep.</h2>
                <p>
                  Every board in Kenya quotes gross. Fructa ranks on what lands in your account: after
                  the {Math.round(WHT * 100)}% withholding, and after {INFLATION}% inflation takes its cut.
                </p>
                <Points
                  rows={[
                    ['Gross, net, real', 'all three on every fund, always visible'],
                    ['Filters', 'by type, currency and minimum to enter'],
                    ['Compare', 'any two funds side by side, winner marked'],
                  ]}
                />
              </div>
            </div>
          </section>

          <section className="fl-wrap">
            <div className="fl-feat rev">
              <div className="fx">
                <PortfolioDonut />
              </div>
              <div>
                <span className="fl-eyebrow">Your money</span>
                <h2>Your holdings, on top of the market.</h2>
                <p>
                  Add what you already hold and Fructa overlays it on the live board. See your blended
                  yield, your projected earnings, and whether your money is sitting in a fund that has
                  quietly slipped down the ranking.
                </p>
                <Points
                  rows={[
                    ['Blended yield', 'consolidated to KES across every holding'],
                    ['Projected earnings', 'with withholding already applied'],
                    ['On-device only', 'no account, no server, no balances leave the phone'],
                  ]}
                />
              </div>
            </div>
          </section>

          <section className="fl-wrap">
            <div className="fl-feat">
              <div className="fx">
                <AlertThreshold alert={charts.alert} />
              </div>
              <div>
                <span className="fl-eyebrow">Move first</span>
                <h2>Know the moment a rate moves.</h2>
                <p>
                  Set a threshold on any fund or benchmark. When a rate crosses it, when a T-bill
                  auction prints, or when a fund you hold slips, Fructa tells you before the WhatsApp
                  group does.
                </p>
                <Points
                  rows={[
                    ['Thresholds', 'on any rate on the board'],
                    ['Auctions', 'T-bill results and maturity reminders'],
                    ['Weekly digest', 'where every rate landed, once a week'],
                  ]}
                />
              </div>
            </div>
          </section>
        </>
      )}

      <section className="fl-band" id="data">
        <div className="fl-band-in">
          {content.stats.map((s) => (
            <div className="fl-stat" key={s.l}>
              <div className="n">{s.n}</div>
              <div className="l">{s.l}</div>
            </div>
          ))}
        </div>
      </section>

      {hasCharts && (
        <section className="fl-sec" id="market">
          <div className="fl-wrap">
            <div className="fl-sec-head">
              <span className="fl-eyebrow">The market</span>
              <h2>The whole board, and the curve that prices it.</h2>
              <p>
                Where Kenya&apos;s collective investment money sits, next to the Treasury curve every
                other rate in the country is measured against.
              </p>
            </div>
            <div className="fl-mkt">
              <MarketDonut market={charts.market} />
              <YieldCurve curve={charts.curve} />
            </div>
          </div>
        </section>
      )}

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
              <p>Every Kenyan rate, ranked and live, the second you land. No account required to look.</p>
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

      <section className="fl-final" id="get">
        <div className="fl-wrap">
          <span className="fl-eyebrow">Free to start</span>
          <h2>{content.cta.headline}</h2>
          <p>{content.cta.subhead}</p>
          <StoreBadges links={content.links} platform={platform} />
        </div>
      </section>

      <footer className="fl-footer">
        <div className="fl-wrap">
          <div className="fl-foot">
            <div>
              <div className="fl-foot-brand">
                <Wordmark size={16} domain />
              </div>
              <p className="fl-foot-blurb">{content.brand.footerBlurb}</p>
            </div>
            <div className="fl-foot-links">
              <div className="fl-foot-col">
                <h4>Product</h4>
                <a href="#rates">Rates</a>
                <a href="#market">Market</a>
                <a href="#how">How it works</a>
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
            <span>2026 {content.brand.name}, Nairobi</span>
            <span>fructa.africa</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
