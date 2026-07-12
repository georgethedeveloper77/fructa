'use client';

import type { EChartsOption } from 'echarts';
import type { LandingCharts } from '../content';
import { tooltip, useChart, type Tokens } from './echarts';

const RAMP: (keyof Tokens)[] = ['gold', 's2', 's3', 's4', 'faint'];

const PRETTY: Record<string, string> = {
  mmf: 'Money market',
  fixed_income: 'Fixed income',
  equity: 'Equity',
  balanced: 'Balanced',
  special: 'Special',
  other: 'Other',
};

/*
 * The industry split. Reads AUM when market.aum_by_class is seeded, and falls
 * back to a fund count otherwise, saying which it is in both the centre label
 * and the tooltip. It never presents a count as if it were money.
 */
export default function MarketDonut({ market }: { market: LandingCharts['market'] }) {
  const isAum = market.mode === 'aum';

  const ref = useChart(
    (t): EChartsOption => ({
      animationDuration: 900,
      tooltip: tooltip(t, {
        trigger: 'item',
        valueFormatter: (v: unknown) =>
          isAum ? `KES ${Number(v).toFixed(1)}B` : `${Number(v)} funds`,
      }),
      legend: {
        bottom: 2,
        itemWidth: 9,
        itemHeight: 9,
        icon: 'roundRect',
        textStyle: { color: t.mute, fontFamily: t.mono, fontSize: 11.5 },
      },
      series: [
        {
          type: 'pie',
          radius: ['54%', '78%'],
          center: ['50%', '44%'],
          padAngle: 2,
          itemStyle: { borderRadius: 4 },
          label: {
            show: true,
            position: 'center',
            formatter: `{a|${market.total}}\n{b|${market.label}}`,
            rich: {
              a: { color: t.ink, fontFamily: t.mono, fontSize: 24, fontWeight: 700, lineHeight: 30 },
              b: { color: t.faint, fontFamily: t.mono, fontSize: 11 },
            },
          },
          emphasis: { scale: true, scaleSize: 6, label: { show: true } },
          data: market.slices.map((s, i) => ({
            name: PRETTY[s.name] ?? s.name,
            value: s.value,
            itemStyle: { color: t[RAMP[i % RAMP.length]] },
          })),
        },
      ],
    }),
    [market],
  );

  return (
    <div className="fl-panel-c">
      <div className="fl-pc-top">
        <span className="t">{isAum ? 'Industry AUM by class' : 'Coverage by class'}</span>
        <span className="r">{isAum ? 'CMA quarterly' : 'Fructa board'}</span>
      </div>
      <div ref={ref} className="fl-canvas fl-canvas-donut" role="img" aria-label="Market split by asset class" />
    </div>
  );
}
