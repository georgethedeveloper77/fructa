import { NextResponse } from "next/server";

/*
 * /get, the one link to hand out.
 *
 * Sniffs the user agent server side and sends the visitor to the right store.
 * Ads, social bios, QR codes and the in-page CTAs all point here, so a single
 * URL works everywhere and you stop maintaining two buttons in six places.
 *
 * Deliberately NOT a redirect on `/`. Googlebot crawls as a mobile device, so
 * user-agent redirecting the homepage would bounce the crawler straight out of
 * the site and cost you the page the whole SEO effort is built on. Isolating
 * the behaviour behind its own route keeps every indexable page untouched.
 *
 * Also deliberately not Firebase Dynamic Links: Google shut that service down
 * on 25 August 2025 and every page.link URL now returns a 404. For opening a
 * specific fund inside the app, use Android App Links and iOS Universal Links
 * against these same /funds/<slug> URLs, which is the supported replacement and
 * needs no third party.
 */

const APP_STORE = "https://apps.apple.com/us/app/fructa/id6789087329";
const PLAY_STORE =
  "https://play.google.com/store/apps/details?id=com.mindberzerk.fructa";

export const dynamic = "force-dynamic";

export function GET(request: Request) {
  const ua = (request.headers.get("user-agent") ?? "").toLowerCase();

  // iPadOS reports itself as Macintosh, so a bare "mac" test would send iPad
  // users to the desktop fallback. Checking for touch support in the UA string
  // is unreliable, so iPad is matched explicitly first.
  const isApple =
    /iphone|ipad|ipod/.test(ua) ||
    (/macintosh/.test(ua) && /mobile/.test(ua));
  const isAndroid = /android/.test(ua);

  // Desktop and anything unrecognised goes to the landing page, where both
  // store buttons are visible. Guessing wrong is worse than not guessing.
  const target = isApple ? APP_STORE : isAndroid ? PLAY_STORE : "/#get";

  return NextResponse.redirect(new URL(target, request.url), {
    status: 302,
    headers: {
      // Never cache a UA-dependent redirect at the edge: one Android visitor
      // would otherwise pin the iPhone response for everyone behind that cache.
      "Cache-Control": "no-store",
      Vary: "User-Agent",
    },
  });
}
