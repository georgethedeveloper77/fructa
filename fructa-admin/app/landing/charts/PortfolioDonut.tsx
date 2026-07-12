'use client';

import type { EChartsOption } from 'echarts';
import { tooltip, useChart } from './echarts';

/*
 * The one chart on the page that is not live, because it cannot be: holdings are
 * on-device and Fructa never sees them. It is labelled as an example in the
 * panel header, which is also the privacy claim the section makes.
 */
const HOLDINGS = [
  { name: 'MMF KES', value: 420_000, tone: 'gold' as const },
  { name: 'T-bills', value: 180_000, tone: 's2' as const },
  { name: 'SACCO', value: 120_000, tone: 's3' as const },
  { name: 'Bonds', value: 80_000, tone: 's4' as const },
];
const BLENDED = 13.9;

export default function PortfolioDonut() {
  const ref = useChart(
    (t): EChartsOption => ({
      animationDuration: 900,
      tooltip: tooltip(t, {
        trigger: 'item',
        valueFormatter: (v: unknown) => `KES ${Number(v).toLocaleString('en-KE')}`,
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
          radius: ['58%', '80%'],
          center: ['50%', '44%'],
          padAngle: 2,
          itemStyle: { borderRadius: 4 },
          label: {
            show: true,
            position: 'center',
            formatter: `{a|${BLENDED.toFixed(1)}%}\n{b|blended yield}`,
            rich: {
              a: { color: t.gold, fontFamily: t.mono, fontSize: 26, fontWeight: 700, lineHeight: 32 },
              b: { color: t.faint, fontFamily: t.mono, fontSize: 11 },
            },
          },
          emphasis: { scale: true, scaleSize: 6, label: { show: true } },
          data: HOLDINGS.map((h) => ({
            name: h.name,
            value: h.value,
            itemStyle: { color: t[h.tone] },
          })),
        },
      ],
    }),
    [],
  );

  return (
    <div className="fl-panel-c">
      <div className="fl-pc-top">
        <span className="t">Blended portfolio</span>
        <span className="r">Example, on-device</span>
      </div>
      <div ref={ref} className="fl-canvas fl-canvas-donut" role="img" aria-label="Example portfolio allocation" />
      <div className="fl-pc-foot">Your balances never leave your phone.</div>
    </div>
  );
}
