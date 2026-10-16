import { appLinkConfig } from "../applinks";

/*
 * Android App Links. Android fetches this once when the app is installed and,
 * if the app's signing fingerprint is listed, opens fructa.africa links in the
 * app instead of the browser. Fingerprints come from admin Config.
 */
export const revalidate = 3600;

export async function GET() {
  const c = await appLinkConfig();
  const body = c.androidSha256.length
    ? [
        {
          relation: ["delegate_permission/common.handle_all_urls"],
          target: {
            namespace: "android_app",
            package_name: c.androidPackage,
            sha256_cert_fingerprints: c.androidSha256,
          },
        },
      ]
    : [];
  return Response.json(body, { headers: { "Cache-Control": "public, max-age=3600" } });
}
