'use client';

import { useState } from 'react';
import type { ChartTab } from './content';

const PLOT = { x0: 46, x1: 664, y0: 24, y1: 276, ax: 296 };
const SERIES_COLORS = ['var(--fl-gold)', 'var(--fl-s2)', 'var(--fl-s3)', 'var(--fl-faint)'];

function CaretUp() {
  return (
    <svg className="fl-caret u" viewBox="0 0 10 10">
      <path d="M5 3 8 7H2z" />
    </svg>
  );
}
function CaretDown() {
  return (
    <svg className="fl-caret d" viewBox="0 0 10 10">
      <path d="M5 7 2 3h6z" />
    </svg>
  );
}

export default function RateChart({ months, tabs }: { months: string[]; tabs: ChartTab[] }) {
  const [active, setActive] = useState(0);
  const tab = tabs[active];
  const n = months.length;

  const all = tab.series.flatMap((s) => s.values);
  let mn = Math.min(...all);
  let mx = Math.max(...all);
  const pad = (mx - mn) * 0.15 || 0.5;
  mn -= pad;
  mx += pad;

  const X = (i: number) => PLOT.x0 + ((PLOT.x1 - PLOT.x0) * i) / (n - 1);
  const Y = (v: number) => PLOT.y1 - ((v - mn) / (mx - mn)) * (PLOT.y1 - PLOT.y0);

  // colour assignment: leader gold, then s2/s3/faint by order
  const colorFor = (idx: number, lead?: boolean) => (lead ? SERIES_COLORS[0] : SERIES_COLORS[Math.min(idx + 1, 3)]);
  const withColor = tab.series.map((s, i) => ({ ...s, color: colorFor(i, s.lead) }));

  // peers first, leader painted last (on top)
  const ordered = [...withColor].sort((a, b) => (a.lead ? 1 : 0) - (b.lead ? 1 : 0));

  const gridVals = [0, 1, 2, 3, 4].map((g) => mn + (mx - mn) * (g / 4));

  const ranked = [...withColor]
    .map((s) => ({ ...s, last: s.values[n - 1], prev: s.values[n - 2] }))
    .sort((a, b) => b.last - a.last);

  return (
    <div className="fl-term">
      <div className="fl-term-top">
        <span className="fl-title">FRUCTA TERMINAL</span>
        <div className="fl-tabs" role="tablist">
          {tabs.map((t, i) => (
            <button
              key={t.key}
              role="tab"
              aria-selected={i === active}
              className={'fl-tab' + (i === active ? ' active' : '')}
              onClick={() => setActive(i)}
            >
              {t.label}
            </button>
          ))}
        </div>
        <span className="fl-live">
          <i />
          LIVE
        </span>
      </div>

      <div className="fl-chart-wrap">
        <svg viewBox="0 0 680 340" role="img" aria-label={`${tab.label} rate history`} className="fl-chart">
          {/* gridlines + y labels */}
          {gridVals.map((val, g) => {
            const y = Y(val);
            return (
              <g key={'g' + g}>
                <line x1={PLOT.x0} y1={y} x2={PLOT.x1} y2={y} stroke="var(--fl-grid)" strokeWidth={1} />
                <text className="fl-axis" x={PLOT.x0 - 8} y={y + 3.5} textAnchor="end">
                  {val.toFixed(1)}
                </text>
              </g>
            );
          })}
          {/* x labels */}
          {months.map((m, i) => (
            <text key={'m' + i} className="fl-axis" x={X(i)} y={PLOT.ax} textAnchor="middle">
              {m}
            </text>
          ))}
          {/* series */}
          {ordered.map((s, oi) => {
            const pts = s.values.map((v, i) => `${X(i)},${Y(v)}`);
            const line = `M ${pts.join(' L ')}`;
            return (
              <g key={'s' + oi}>
                {s.lead && (
                  <path
                    d={`M ${pts.join(' L ')} L ${X(n - 1)},${PLOT.y1} L ${X(0)},${PLOT.y1} Z`}
                    fill="var(--fl-gold)"
                    opacity={0.1}
                  />
                )}
                <path
                  className="fl-ln fl-draw"
                  d={line}
                  stroke={s.color}
                  pathLength={1}
                  opacity={s.lead ? 1 : 0.55}
                  strokeWidth={s.lead ? 2.6 : 1.6}
                />
                {s.lead &&
                  (() => {
                    const lx = X(n - 1);
                    const ly = Y(s.values[n - 1]);
                    return (
                      <g>
                        <circle cx={lx} cy={ly} r={3.4} fill="var(--fl-gold)" />
                        <rect x={lx - 44} y={ly - 24} width={46} height={17} rx={4} fill="var(--fl-gold)" />
                        <text className="fl-end" x={lx - 21} y={ly - 12} textAnchor="middle">
                          {s.values[n - 1].toFixed(2)}
                          {tab.unit}
                        </text>
                      </g>
                    );
                  })()}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="fl-board">
        {ranked.map((s, i) => {
          const chg = s.last - s.prev;
          const up = chg >= 0;
          return (
            <div className="fl-brow" key={'b' + i}>
              <span className={'fl-rk' + (i === 0 ? ' top' : '')}>{i + 1}</span>
              <span className="fl-nm">
                <span className="fl-sw" style={{ background: s.color }} />
                {s.name}
              </span>
              <span className={'fl-ch ' + (up ? 'u' : 'd')}>
                {up ? <CaretUp /> : <CaretDown />}
                {Math.abs(chg).toFixed(2)}
              </span>
              <span className="fl-rt">
                {s.last.toFixed(2)}
                {tab.unit}
              </span>
            </div>
          );
        })}
      </div>

      <div className="fl-benchmarks">
        {tab.benchmarks.map(([k, v], i) => (
          <span className="fl-chip" key={'c' + i}>
            {k} <b>{v}</b>
          </span>
        ))}
      </div>
    </div>
  );
}
