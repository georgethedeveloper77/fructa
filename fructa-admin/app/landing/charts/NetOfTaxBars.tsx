'use client';

import type { EChartsOption } from 'echarts';
import { INFLATION, WHT, type LandingCharts } from '../content';
import { tooltip, useChart } from './echarts';

/*
 * The argument the section makes, drawn: gross, then what withholding leaves,
 * then what inflation leaves. The third bar is short on purpose. It is the whole
 * point of the product and no screenshot could make it as plainly.
 */
export default function NetOfTaxBars({ funds }: { funds: LandingCharts['netOfTax'] }) {
  const ref = useChart(
    (t): EChartsOption => {
      const names = funds.map((f) => f.name).reverse(); // ECharts category axis runs bottom-up
      const gross = funds.map((f) => f.gross).reverse();
      const net = gross.map((g) => +(g * (1 - WHT)).toFixed(2));
      const real = net.map((n) => +(n - INFLATION).toFixed(2));

      return {
        animationDuration: 900,
        animationDelay: (i: number) => i * 55,
        grid: { left: 8, right: 40, top: 6, bottom: 22, containLabel: true },
        tooltip: tooltip(t, {
          trigger: 'axis',
          axisPointer: { type: 'shadow' },
          valueFormatter: (v: unknown) => `${Number(v).toFixed(2)}%`,
        }),
        xAxis: {
          type: 'value',
          splitLine: { lineStyle: { color: t.grid } },
          axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11, formatter: '{value}%' },
        },
        yAxis: {
          type: 'category',
          data: names,
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: { color: t.mute, fontFamily: t.mono, fontSize: 11.5 },
        },
        series: [
          { name: 'Gross', type: 'bar', data: gross, barWidth: 7, itemStyle: { color: t.gold, borderRadius: [0, 3, 3, 0] } },
          { name: 'Net', type: 'bar', data: net, barWidth: 7, itemStyle: { color: t.s2, borderRadius: [0, 3, 3, 0] } },
          { name: 'Real', type: 'bar', data: real, barWidth: 7, itemStyle: { color: t.s3, borderRadius: [0, 3, 3, 0] } },
        ],
      };
    },
    [funds],
  );

  return (
    <div className="fl-panel-c">
      <div className="fl-pc-top">
        <span className="t">What you keep</span>
        <span className="r">Top {funds.length} MMF, KES</span>
      </div>
      <div className="fl-pc-legend">
        <span className="fl-lgd"><i style={{ background: 'var(--fl-gold)' }} />Gross</span>
        <span className="fl-lgd"><i style={{ background: 'var(--fl-s2)' }} />After {Math.round(WHT * 100)}% WHT</span>
        <span className="fl-lgd"><i style={{ background: 'var(--fl-s3)' }} />After {INFLATION}% inflation</span>
      </div>
      <div ref={ref} className="fl-canvas fl-canvas-tall" role="img" aria-label="Gross, net and real yield by fund" />
    </div>
  );
}
