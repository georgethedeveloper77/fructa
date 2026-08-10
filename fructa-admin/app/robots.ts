import type { MetadataRoute } from "next";

const SITE = "https://fructa.africa";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // /get is a user-agent dependent redirect with no content of its own.
        // Letting a crawler follow it wastes budget and risks Google reading a
        // store redirect as the destination for a link that should stay on site.
        disallow: ["/admin", "/console", "/login", "/api", "/get"],
      },
    ],
    sitemap: `${SITE}/sitemap.xml`,
    host: SITE,
  };
}
