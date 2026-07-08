import { adminClient } from "../_shared/supabase.ts";

// Fetch a portfolio backup by recovery code. Body: { code }.
// Returns { found, data?, updated_at?, device_label?, schema? }. Never 404s on
// a missing backup — { found:false } lets the app distinguish "no backup" from
// a transport error.

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

function validCode(code: unknown): code is string {
  return typeof code === "string" && code.length >= 12 && code.length <= 128;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: { code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }
  if (!validCode(body.code)) return json({ error: "bad code" }, 400);

  const codeHash = await sha256hex(body.code);
  const db = adminClient();
  const { data, error } = await db
    .from("portfolio_backups")
    .select("data, updated_at, device_label, schema")
    .eq("code_hash", codeHash)
    .maybeSingle();

  if (error) return json({ error: error.message }, 500);
  if (!data) return json({ found: false });

  return json({
    found: true,
    data: data.data,
    updated_at: data.updated_at,
    device_label: data.device_label,
    schema: data.schema,
  });
});
