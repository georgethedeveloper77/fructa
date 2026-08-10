import { inkOn, monogram, type PublicFund } from "@/lib/funds.server";

/*
 * The manager's mark.
 *
 * Two states and no third. When `companies.logo_url` exists it renders the real
 * image on a tile filled with the manager's brand colour, so a logo with a
 * transparent background still reads. When it does not, the same tile carries
 * the manager's initial. There is no spinner and no placeholder that later
 * swaps, because a tile that changes size after paint is layout shift, and
 * layout shift is a Core Web Vitals cost on the pages the whole SEO effort
 * depends on.
 *
 * Plain <img>, not next/image: the logo hosts are arbitrary third party domains
 * and next/image would need every one of them declared in remotePatterns, so a
 * manager added in the admin panel would silently 500 the page until someone
 * remembered to redeploy the config. Width and height are set explicitly, which
 * is what actually prevents the shift.
 */

const FALLBACK_BRAND = "#e7b24c";

export default function FundLogo({
  fund,
  size = 40,
}: {
  fund: PublicFund;
  size?: number;
}) {
  const brand = fund.brandColor ?? FALLBACK_BRAND;
  const ink = inkOn(brand);

  return (
    <span
      className="fu-logo"
      style={{
        width: size,
        height: size,
        background: brand,
        color: ink,
        fontSize: Math.round(size * 0.45),
      }}
      aria-hidden="true"
    >
      {fund.logoUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={fund.logoUrl}
          alt=""
          width={size}
          height={size}
          loading="lazy"
          decoding="async"
        />
      ) : (
        monogram(fund)
      )}
    </span>
  );
}
