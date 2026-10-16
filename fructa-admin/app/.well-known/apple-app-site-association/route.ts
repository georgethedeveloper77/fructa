import { appLinkConfig } from "../applinks";

/*
 * iOS Universal Links. Must be served as JSON at exactly this path, with no
 * redirect and no file extension. The Team ID comes from admin Config.
 */
export const revalidate = 3600;

export async function GET() {
  const c = await appLinkConfig();
  const body = c.iosTeamId
    ? {
        applinks: {
          details: [
            {
              appIDs: [`${c.iosTeamId}.${c.iosBundleId}`],
              components: c.paths.map((p) => ({ "/": p })),
            },
          ],
        },
      }
    : { applinks: { details: [] } };
  return Response.json(body, { headers: { "Cache-Control": "public, max-age=3600" } });
}
