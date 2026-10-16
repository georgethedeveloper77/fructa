import { ImageResponse } from "next/og";
import { getFundBySlug, netRate } from "@/lib/funds.server";

/*
 * The picture a shared fund link shows in WhatsApp, X or Slack: the fund, its
 * rate today and what you keep, instead of a generic card. Rebuilt hourly.
 */
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const revalidate = 3600;
export const alt = "Fund rate today on Fructa";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const found = await getFundBySlug(slug);
  const fund = found?.fund;
  const gross = fund?.grossRate ?? null;
  const net = fund && found ? netRate(fund, found.bundle.whtPct) : null;
  const brand = fund?.brandColor ?? "#e7b24c";
  const day = new Date(Date.now() + 3 * 3_600_000).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 72,
          background: "#060709",
          color: "#F3F5F8",
          backgroundImage: `radial-gradient(circle at 0% 0%, ${brand}66, transparent 60%)`,
        }}
      >
        <div style={{ display: "flex", fontSize: 28, letterSpacing: 6, color: "#E7B24C", fontWeight: 700 }}>FRUCTA</div>
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ fontSize: 52, fontWeight: 700, lineHeight: 1.1 }}>{fund?.name ?? "Fund rates in Kenya"}</div>
          {gross != null ? (
            <div style={{ display: "flex", alignItems: "baseline", marginTop: 24 }}>
              <div style={{ fontSize: 132, fontWeight: 700, letterSpacing: -4 }}>{gross.toFixed(2)}%</div>
              <div style={{ fontSize: 36, color: "#9AA2B2", marginLeft: 24 }}>
                {net != null ? `${net.toFixed(2)}% after tax` : "gross"}
              </div>
            </div>
          ) : null}
        </div>
        <div style={{ display: "flex", fontSize: 28, color: "#9AA2B2" }}>Rate today · {day} · fructa.africa</div>
      </div>
    ),
    size,
  );
}
