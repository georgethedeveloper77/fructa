'use client';

import { useState } from 'react';
import type { EChartsOption } from 'echarts';
import type { LandingCharts } from '../content';
import { fade, tooltip, useChart, type Tokens } from './echarts';

/*
 * ONE colour rule, used by both the chart and the board underneath it, so a
 * series line and its swatch can never disagree. The leader is always gold;
 * peers walk the cool ramp. The board uses the matching CSS class rather than an
 * interpolated var name, which is what dropped the leader's swatch before.
 */
const peer = (t: Tokens, i: number) => [t.s2, t.s3, t.s4][i % 3];
const swatchClass = (i: number, lead: boolean) => (lead ? 'fl-sw c-lead' : `fl-sw c-${(i % 3) + 2}`);

export default function HeroTerminal({ charts }: { charts: LandingCharts }) {
  const [active, setActive] = useState(0);
  const tab = charts.tabs[active];

  const ref = useChart(
    (t): EChartsOption => ({
      animationDuration: 1100,
      animationEasing: 'cubicOut',
      grid: { left: 44, right: 62, top: 18, bottom: 26 },
      tooltip: tooltip(t, {
        trigger: 'axis',
        valueFormatter: (v: unknown) => `${Number(v).toFixed(2)}${tab.unit}`,
      }),
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: charts.months,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11 },
      },
      yAxis: {
        type: 'value',
        scale: true,
        splitLine: { lineStyle: { color: t.grid } },
        axisLabel: {
          color: t.faint,
          fontFamily: t.mono,
          fontSize: 11,
          formatter: (v: number) => v.toFixed(1),
        },
      },
      series: tab.series.map((s, i) => {
        const color = s.lead ? t.gold : peer(t, i);
        return {
          name: s.name,
          type: 'line',
          smooth: true,
          symbol: 'none',
          data: s.values,
          z: s.lead ? 3 : 2,
          lineStyle: { width: s.lead ? 2.8 : 1.6, color, opacity: s.lead ? 1 : 0.6 },
          areaStyle: s.lead ? { color: fade(t.gold, 0.18) } : undefined,
          endLabel: s.lead
            ? {
                show: true,
                formatter: (p: { value: number }) => `${p.value.toFixed(2)}${tab.unit}`,
                color: '#1A1206',
                backgroundColor: t.gold,
                padding: [3, 6],
                borderRadius: 4,
                fontFamily: t.mono,
                fontWeight: 600,
                fontSize: 11,
              }
            : undefined,
        };
      }),
    }),
    [active, charts],
  );

  const ranked = tab.series
    .map((s, i) => ({
      name: s.name,
      lead: !!s.lead,
      i,
      last: s.values[s.values.length - 1],
      prev: s.values[s.values.length - 2],
    }))
    .sort((a, b) => b.last - a.last);

  return (
    <div className="fl-term">
      <div className="fl-term-top">
        <span className="fl-title">FRUCTA TERMINAL</span>
        <div className="fl-tabs" role="tablist">
          {charts.tabs.map((t, i) => (
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
        {charts.live && (
          <span className="fl-live">
            <i />
            LIVE
          </span>
        )}
      </div>

      <div ref={ref} className="fl-canvas fl-canvas-hero" role="img" aria-label={`${tab.label} rate history`} />

      <div className="fl-board">
        {ranked.map((r, i) => {
          const chg = r.last - r.prev;
          const up = chg >= 0;
          const first = i === 0;
          return (
            <div className={'fl-brow' + (first ? ' lead' : '')} key={r.name}>
              <span className="fl-rk">{i + 1}</span>
              <span className={swatchClass(r.i, r.lead)} />
              <span className="fl-nm">{r.name}</span>
              <span className={'fl-ch ' + (up ? 'u' : 'd')}>
                {up ? '+' : '-'}
                {Math.abs(chg).toFixed(2)}
              </span>
              <span className="fl-rt">
                {r.last.toFixed(2)}
                {tab.unit}
              </span>
            </div>
          );
        })}
      </div>

      <div className="fl-benchmarks">
        {tab.benchmarks.map(([k, v]) => (
          <span className="fl-chip" key={k}>
            {k} <b>{v}</b>
          </span>
        ))}
      </div>
    </div>
  );
}
