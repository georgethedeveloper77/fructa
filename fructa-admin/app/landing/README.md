# Fructa landing + SEO

Public landing at `/`, theme-aware, chart-led hero with live MMF/USD/Fixed tabs,
official store badges with iOS/Android auto-detect.

## Files
- `app/page.tsx` — REPLACES the current root. SEO `generateMetadata` + JSON-LD + renders `<Landing/>`.
- `app/landing/Landing.tsx` — full UI (client): nav, hero, sections, theme toggle, store detect.
- `app/landing/RateChart.tsx` — the tabbed rate chart (client).
- `app/landing/landing.css` — scoped under `.fl`, will not touch admin/Tailwind.
- `app/landing/content.ts` — content model + defaults + the ONE wiring function.
- `app/robots.ts`, `app/sitemap.ts`, `app/manifest.ts` — SEO surface.

## Assumptions
- Root layout (`app/layout.tsx`) is a bare `<html><body>{children}</body>` shell
  (admin chrome lives in `app/admin/layout.tsx`), so dropping the landing at `/` is safe.
- Fonts load locally via `next/font` inside the landing, so no root-layout edit needed.

## Renders today on defaults. To go live:
1. Wire `getLandingContent()` in `content.ts` to `app_config` (key map documented in that file).
2. Bind `chart[]` to the published snapshot's rate history.
3. Upload an OG image (or set `seo.og_image`); `page.tsx` falls back to `/og.png`.

## Still pending your files (next layers): config seed migration + reader,
admin Settings section, and pulling login off `/login` (needs `proxy.ts`).
