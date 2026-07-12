'use client';

// Shared ECharts 6 layer for the landing.
//
// Tree-shaken registration (only the chart types and components the landing
// actually uses) and the SVG renderer, which stays crisp on a mostly-static
// marketing page and prints better than canvas.
//
// Colours are never hardcoded here. readTokens() pulls the live values off the
// .fl CSS custom properties, which means light mode, dark mode and any future
// token change flow into the charts with no chart-side edits. The font families
// come from the same place because next/font emits a hashed family name, so a
// literal "Space Grotesk" in a chart label would silently miss the loaded face.

import * as echarts from 'echarts/core';
import { BarChart, LineChart, PieChart } from 'echarts/charts';
import {
  GridComponent,
  LegendComponent,
  MarkLineComponent,
  MarkPointComponent,
  TooltipComponent,
} from 'echarts/components';
import { LabelLayout } from 'echarts/features';
import { SVGRenderer } from 'echarts/renderers';
import { useEffect, useRef } from 'react';
import type { EChartsOption } from 'echarts';

echarts.use([
  BarChart,
  LineChart,
  PieChart,
  GridComponent,
  LegendComponent,
  MarkLineComponent,
  MarkPointComponent,
  TooltipComponent,
  LabelLayout,
  SVGRenderer,
]);

export type Tokens = {
  gold: string; s2: string; s3: string; s4: string;
  ink: string; mute: string; faint: string;
  grid: string; line: string; up: string; down: string;
  panel: string; mono: string; sans: string;
};

const VARS: Record<keyof Tokens, string> = {
  gold: '--fl-gold', s2: '--fl-s2', s3: '--fl-s3', s4: '--fl-s4',
  ink: '--fl-ink', mute: '--fl-mute', faint: '--fl-faint',
  grid: '--fl-grid', line: '--fl-line', up: '--fl-up', down: '--fl-down',
  panel: '--fl-panel', mono: '--fl-mono', sans: '--fl-sans',
};

export function readTokens(el: HTMLElement): Tokens {
  const cs = getComputedStyle(el);
  const out = {} as Tokens;
  (Object.keys(VARS) as (keyof Tokens)[]).forEach((k) => {
    out[k] = cs.getPropertyValue(VARS[k]).trim();
  });
  out.mono = `${out.mono || 'Space Grotesk'}, monospace`;
  out.sans = `${out.sans || 'Inter'}, system-ui, sans-serif`;
  return out;
}

/** rgba() from a #rrggbb token. Falls back to the raw value if it is not hex. */
export function alpha(color: string, a: number): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(color.trim());
  if (!m) return color;
  const n = parseInt(m[1], 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

/** Vertical fade under a line series. */
export function fade(color: string, from = 0.18) {
  return {
    type: 'linear' as const,
    x: 0, y: 0, x2: 0, y2: 1,
    colorStops: [
      { offset: 0, color: alpha(color, from) },
      { offset: 1, color: alpha(color, 0) },
    ],
  };
}

/** Shared tooltip skin. */
export function tooltip(t: Tokens, extra: Record<string, unknown> = {}) {
  return {
    backgroundColor: t.panel,
    borderColor: t.line,
    borderWidth: 1,
    padding: [7, 10],
    textStyle: { color: t.ink, fontFamily: t.mono, fontSize: 12 },
    ...extra,
  };
}

/**
 * Mounts a chart, rebuilds it whenever `deps` change, and repaints on a theme
 * flip (both the explicit data-theme attribute and the system preference, since
 * landing.css honours both). Respects prefers-reduced-motion by dropping the
 * entry animation rather than the chart.
 */
export function useChart(build: (t: Tokens) => EChartsOption, deps: unknown[] = []) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const chart = echarts.init(el, undefined, { renderer: 'svg' });
    const still = window.matchMedia('(prefers-reduced-motion: reduce)');

    const paint = () => {
      const opt = build(readTokens(el));
      chart.setOption(still.matches ? { ...opt, animation: false } : opt, true);
    };
    paint();

    const ro = new ResizeObserver(() => chart.resize());
    ro.observe(el);

    const mo = new MutationObserver(paint);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

    const scheme = window.matchMedia('(prefers-color-scheme: light)');
    scheme.addEventListener('change', paint);

    return () => {
      ro.disconnect();
      mo.disconnect();
      scheme.removeEventListener('change', paint);
      chart.dispose();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return ref;
}

export { echarts };
