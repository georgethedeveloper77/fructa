'use client';

import type { EChartsOption } from 'echarts';
import type { LandingCharts } from '../content';
import { fade, tooltip, useChart } from './echarts';

/*
 * The alert mechanic, shown rather than described: the leader's own history, the
 * threshold as a dashed line, and the month it crossed marked on the curve.
 */
export default function AlertThreshold({ alert }: { alert: LandingCharts['alert'] }) {
  const ref = useChart(
    (t): EChartsOption => ({
      animationDuration: 1000,
      grid: { left: 44, right: 24, top: 26, bottom: 26 },
      tooltip: tooltip(t, {
        trigger: 'axis',
        valueFormatter: (v: unknown) => `${Number(v).toFixed(2)}%`,
      }),
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: alert.labels,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11 },
      },
      yAxis: {
        type: 'value',
        scale: true,
        splitLine: { lineStyle: { color: t.grid } },
        axisLabel: { color: t.faint, fontFamily: t.mono, fontSize: 11, formatter: (v: number) => v.toFixed(1) },
      },
      series: [
        {
          type: 'line',
          smooth: true,
          symbol: 'none',
          data: alert.values,
          lineStyle: { width: 2.8, color: t.gold },
          areaStyle: { color: fade(t.gold, 0.18) },
          markLine: {
            silent: true,
            symbol: 'none',
            lineStyle: { color: t.up, type: 'dashed', width: 1.4 },
            label: {
              formatter: `Alert  ${alert.threshold.toFixed(2)}%`,
              color: t.up,
              fontFamily: t.mono,
              fontSize: 11,
              position: 'insideStartTop',
            },
            data: [{ yAxis: alert.threshold }],
          },
          markPoint: alert.crossedAt
            ? {
                symbol: 'circle',
                symbolSize: 9,
                itemStyle: { color: t.up, borderColor: t.panel, borderWidth: 2 },
                label: {
                  show: true,
                  formatter: 'crossed',
                  position: 'top',
                  distance: 8,
                  color: t.up,
                  fontFamily: t.mono,
                  fontSize: 10.5,
                },
                data: [
                  {
                    coord: [
                      alert.crossedAt,
                      alert.values[alert.labels.indexOf(alert.crossedAt)],
                    ],
                  },
                ],
              }
            : undefined,
        },
      ],
    }),
    [alert],
  );

  return (
    <div className="fl-panel-c">
      <div className="fl-pc-top">
        <span className="t">Alert threshold</span>
        <span className="r">{alert.fund}</span>
      </div>
      <div ref={ref} className="fl-canvas fl-canvas-tall" role="img" aria-label={`${alert.fund} rate against an alert threshold`} />
      <div className="fl-pc-foot">
        {alert.crossedAt
          ? `Crossed ${alert.threshold.toFixed(2)}% in ${alert.crossedAt}. You would have known that morning.`
          : `Watching for ${alert.threshold.toFixed(2)}%.`}
      </div>
    </div>
  );
}
