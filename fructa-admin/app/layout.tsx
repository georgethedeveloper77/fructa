import { GoogleAnalytics } from "@next/third-parties/google";
import "./globals.css";

export const metadata = { title: "Fructa Admin" };

/**
 * GA4 measurement id. Set NEXT_PUBLIC_GA_ID in apphosting.yaml with BUILD
 * availability, since NEXT_PUBLIC_ vars are inlined at build time and a
 * RUNTIME-only var reaches the client as undefined.
 *
 * Absent means no tag renders at all, which is what we want locally and in
 * preview builds: dev traffic landing in the same GA4 property would poison the
 * only numbers worth trusting right now.
 */
const GA_ID = process.env.NEXT_PUBLIC_GA_ID;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      {/*
        Browser extensions (ColorZilla writes cz-shortcut-listen, Grammarly and
        LastPass do the same thing) mutate <body> before React hydrates, which
        React then reports as a hydration mismatch it cannot patch. The markup is
        correct; the attribute is not ours. suppressHydrationWarning silences that
        one node's attribute diff and nothing else: mismatches in the tree below
        are still reported normally.
      */}
      <body suppressHydrationWarning>
        <div className="min-h-screen">{children}</div>
      </body>
      {/*
        Loaded through @next/third-parties rather than a hand-rolled <Script>:
        it defers the tag off the critical path and keeps gtag out of the
        hydration tree, so a marketing tag cannot cost the landing page the Core
        Web Vitals the SEO work depends on.

        Measurement only. Search Console is the tool that tells you which queries
        you actually rank for, it is free, and for the SEO plan it matters more
        than this does.
      */}
      {GA_ID ? <GoogleAnalytics gaId={GA_ID} /> : null}
    </html>
  );
}
