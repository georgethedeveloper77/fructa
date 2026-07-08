import { adminClient } from "../_shared/supabase.ts";

// Upsert a portfolio backup. Body: { code, data, device?, schema? }.
// The code is hashed here and never stored raw. Returns { ok, updated_at }.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function sha256hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Recovery codes are app-generated, high-entropy tokens. Guard the shape so a
// junk/enumeration payload can't spam the table, but stay format-agnostic.
function validCode(code: unknown): code is string {
  return typeof code === "string" && code.length >= 12 && code.length <= 128;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: { code?: unknown; data?: unknown; device?: unknown; schema?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }

  const { code, data, device, schema } = body;
  if (!validCode(code)) return json({ error: "bad code" }, 400);
  if (data == null || (typeof data !== "object")) {
    return json({ error: "bad data" }, 400);
  }

  const codeHash = await sha256hex(code);
  const updatedAt = new Date().toISOString();

  const db = adminClient();
  const { error } = await db.from("portfolio_backups").upsert(
    {
      code_hash: codeHash,
      data,
      device_label: typeof device === "string" ? device.slice(0, 60) : null,
      schema: typeof schema === "number" ? schema : 1,
      updated_at: updatedAt,
    },
    { onConflict: "code_hash" },
  );
  if (error) return json({ error: error.message }, 500);

  return json({ ok: true, updated_at: updatedAt });
});
