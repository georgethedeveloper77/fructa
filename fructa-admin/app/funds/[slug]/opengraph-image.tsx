import { ImageResponse } from "next/og";
import { getFundBySlug, netRate } from "@/lib/funds.server";

/*
 * The picture a shared fund link shows in WhatsApp, X or Slack: the fund, its
 * rate today and what you keep.
 *
 * Kept deliberately plain: solid colours only (no gradients, no remote fonts
 * or images), on the Node runtime, and any failure returns a simple card
 * rather than an error. The first version used a CSS gradient and the server
 * dropped the connection rendering it.
 */
export const runtime = "nodejs";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const revalidate = 3600;
export const alt = "Fund rate today on Fructa";

const BG = "#060709";
const INK = "#F3F5F8";
const MUTE = "#9AA2B2";
const GOLD = "#E7B24C";

function card(title: string, big: string | null, sub: string | null, accent: string) {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", background: BG, color: INK }}>
        <div style={{ width: 24, height: "100%", background: accent, display: "flex" }} />
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 72 }}>
          <div style={{ display: "flex", fontSize: 30, letterSpacing: 6, color: GOLD, fontWeight: 700 }}>FRUCTA</div>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div style={{ display: "flex", fontSize: 54, fontWeight: 700 }}>{title}</div>
            {big ? (
              <div style={{ display: "flex", alignItems: "flex-end", marginTop: 20 }}>
                <div style={{ display: "flex", fontSize: 140, fontWeight: 700 }}>{big}</div>
                {sub ? <div style={{ display: "flex", fontSize: 38, color: MUTE, marginLeft: 28, marginBottom: 26 }}>{sub}</div> : null}
              </div>
            ) : null}
          </div>
          <div style={{ display: "flex", fontSize: 28, color: MUTE }}>Kenyan rates, after tax · fructa.africa</div>
        </div>
      </div>
    ),
    size,
  );
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  try {
    const { slug } = await params;
    const found = await getFundBySlug(slug);
    if (!found) return card("Fund rates in Kenya", null, null, GOLD);
    const { fund, bundle } = found;
    const gross = fund.grossRate;
    const net = netRate(fund, bundle.whtPct);
    const accent = /^#[0-9a-f]{6}$/i.test(fund.brandColor ?? "") ? fund.brandColor! : GOLD;
    return card(
      fund.name,
      gross != null ? `${gross.toFixed(2)}%` : null,
      net != null && gross != null && net !== gross ? `${net.toFixed(2)}% after tax` : null,
      accent,
    );
  } catch (err) {
    console.error("[og] fund image failed:", err);
    return card("Fund rates in Kenya", null, null, GOLD);
  }
}
