"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

/*
 * On phones, one bar at the bottom of every page: get the app, from the right
 * store. The link is /get, which picks the store on the server too, so the
 * bar works before this script runs; the label just names the store once it
 * knows the phone. Desktop never shows it. Search engines read the page the
 * same either way, because nothing here redirects.
 */
export default function GetBar() {
  const [store, setStore] = useState<string | null>(null);
  useEffect(() => {
    const ua = navigator.userAgent.toLowerCase();
    if (/iphone|ipad|ipod/.test(ua) || (/macintosh/.test(ua) && navigator.maxTouchPoints > 1)) {
      setStore("App Store");
    } else if (/android/.test(ua)) {
      setStore("Google Play");
    }
  }, []);
  return (
    <div className="fl-getbar" role="complementary" aria-label="Get the Fructa app">
      <span className="fl-getbar-text">
        Fructa for your phone
        <span className="fl-getbar-sub">Every rate, after tax. Free.</span>
      </span>
      <Link className="fl-btn fl-btn-gold" href="/get">
        {store ? `Get it on ${store}` : "Get the app"}
      </Link>
    </div>
  );
}
