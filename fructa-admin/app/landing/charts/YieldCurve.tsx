'use client';

import type { EChartsOption } from 'echarts';
import { CBR, type LandingCharts } from '../content';
import { fade, tooltip, useChart } from './echarts';

/*
 * The curve that prices everything else on the page, with the policy rate behind
 * it as the reference line. Points are labelled because there are only three and
 * the exact print is the interesting part.
 */
export default function YieldCurve({ curve }: { curve: LandingCharts['curve'] }) {
  const ref = useChart(
    (t): EChartsOption => ({
      animationDuration: 1000,
      grid: { left: 46, right: 30, top: 30, bottom: 28 },
      tooltip: tooltip(t, {
        trigger: 'axis',
        valueFormatter: (v: unknown) => `${Number(v).toFixed(2)}%`,
      }),
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: curve.labels,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11.5 },
      },
      yAxis: {
        type: 'value',
        scale: true,
        splitLine: { lineStyle: { color: t.grid } },
        axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11, formatter: (v: number) => v.toFixed(2) },
      },
      series: [
        {
          type: 'line',
          smooth: true,
          data: curve.values,
          symbol: 'circle',
          symbolSize: 8,
          itemStyle: { color: t.gold, borderColor: t.panel, borderWidth: 2 },
          lineStyle: { width: 2.8, color: t.gold },
          areaStyle: { color: fade(t.gold, 0.15) },
          label: {
            show: true,
            position: 'top',
            distance: 8,
            formatter: (p: { value: number }) => `${p.value.toFixed(2)}%`,
            color: t.ink,
            fontFamily: t.mono,
            fontSize: 11,
          },
          markLine: {
            silent: true,
            symbol: 'none',
            lineStyle: { color: t.s3, type: 'dashed', width: 1.2 },
            label: {
              formatter: `CBR ${CBR.toFixed(2)}`,
              color: t.s3,
              fontFamily: t.mono,
              fontSize: 10.5,
              position: 'insideEndTop',
            },
            data: [{ yAxis: CBR }],
          },
        },
      ],
    }),
    [curve],
  );

  return (
    <div className="fl-panel-c">
      <div className="fl-pc-top">
        <span className="t">T-bill yield curve</span>
        <span className="r">CBK auction</span>
      </div>
      <div ref={ref} className="fl-canvas fl-canvas-donut" role="img" aria-label="Treasury bill yield curve" />
    </div>
  );
}
