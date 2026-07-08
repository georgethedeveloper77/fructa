// The ONE place that talks to the OneSignal REST API. emit-events, send-push
// and weekly-digest all send through here, so every push carries a deep-link
// `data.target` by construction and copy never drifts between callers.
//
// Keys are server-only (Supabase secrets), never shipped in the app:
//   ONESIGNAL_APP_ID, ONESIGNAL_REST_KEY

const APP_ID = Deno.env.get("ONESIGNAL_APP_ID");
const REST = Deno.env.get("ONESIGNAL_REST_KEY");

export interface PushMsg {
  heading: string;
  body: string;
  target?: string; // fund/<id> | markets | portfolio | alerts | settings
}

export interface PushResult {
  ok: boolean;
  id?: string;
  recipients?: number;
  error?: string;
}

export const oneSignalEnabled = (): boolean => !!(APP_ID && REST);

function dataFor(target?: string): Record<string, unknown> | undefined {
  return target ? { target } : undefined;
}

async function post(payload: Record<string, unknown>): Promise<PushResult> {
  if (!APP_ID || !REST) {
    return { ok: false, error: "ONESIGNAL_APP_ID / ONESIGNAL_REST_KEY not set" };
  }
  try {
    const res = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${REST}`,
      },
      body: JSON.stringify({ app_id: APP_ID, ...payload }),
    });
    const json = await res.json().catch(() => ({} as Record<string, unknown>));
    if (!res.ok) {
      const errs = (json as { errors?: unknown }).errors;
      return { ok: false, error: `HTTP ${res.status}${errs ? `: ${JSON.stringify(errs)}` : ""}` };
    }
    return {
      ok: true,
      id: (json as { id?: string }).id,
      recipients: (json as { recipients?: number }).recipients ?? 0,
    };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

/// Send to everyone in a segment (default: OneSignal's built-in "Subscribed
/// Users"). Used by admin "send to all" and any market-wide broadcast.
export function broadcast(
  msg: PushMsg,
  segment = "Subscribed Users",
): Promise<PushResult> {
  return post({
    included_segments: [segment],
    headings: { en: msg.heading },
    contents: { en: msg.body },
    data: dataFor(msg.target),
  });
}

/// Send to the users carrying a tag (e.g. follow_<id>, leader_<cat>,
/// digest_weekly, market_alerts). Value defaults to "true" to match the app.
export function sendToTag(
  key: string,
  value: string,
  msg: PushMsg,
): Promise<PushResult> {
  return post({
    filters: [{ field: "tag", key, relation: "=", value }],
    headings: { en: msg.heading },
    contents: { en: msg.body },
    data: dataFor(msg.target),
  });
}
