import { supabaseAdmin } from "@/lib/supabase/server";

/// The spend guard. Checked BEFORE every LLM call, project wide.
///
/// Two rules, and the ordering matters. The switch is checked first because it
/// is the one a person reaches for in a hurry, and it must not depend on a
/// working sum. The cap is checked second.

/// Cents per million tokens, in and out. Update when pricing moves.
const PRICING: Record<string, { in: number; out: number }> = {
  "claude-opus-4-6":   { in: 1500, out: 7500 },
  "claude-sonnet-4-6": { in: 300,  out: 1500 },
  "claude-haiku-4-5":  { in: 100,  out: 500 },
};
const FALLBACK = { in: 300, out: 1500 };

/// Cost of a call, in whole cents, ROUNDED UP.
///
/// Up, not nearest. A ledger that rounds down drifts below the truth, and the
/// direction of the error decides whether the cap stops you a little early or a
/// little late. Early is the harmless one.
export function costCents(model: string, inTok: number, outTok: number): number {
  const p = PRICING[model] ?? FALLBACK;
  return Math.ceil((inTok / 1e6) * p.in + (outTok / 1e6) * p.out);
}

export type Budget = {
  allowed: boolean;
  reason: string;
  spentCents: number;
  capCents: number;
  calls: number;
};

/// May we spend? [estimateCents] is what the call is expected to cost, so a
/// request that would BREACH the cap is refused rather than one that already
/// has. Checking after the fact means the cap is always exceeded exactly once.
export async function checkBudget(estimateCents = 10): Promise<Budget> {
  const db = supabaseAdmin();

  const [{ data: cfg }, { data: mtd }] = await Promise.all([
    db.from("app_config").select("key,value").in("key", ["llm.enabled", "llm.monthly_cap_cents"]),
    db.from("llm_spend_mtd").select("cents,calls").single(),
  ]);

  const byKey = new Map((cfg ?? []).map((r) => [r.key as string, r.value as Record<string, unknown>]));
  const enabled = (byKey.get("llm.enabled")?.on ?? true) as boolean;
  const capCents = Number(byKey.get("llm.monthly_cap_cents")?.cents ?? 500);
  const spentCents = Number(mtd?.cents ?? 0);
  const calls = Number(mtd?.calls ?? 0);

  if (!enabled) {
    return {
      allowed: false, spentCents, capCents, calls,
      reason: "LLM calls are switched off. Turn llm.enabled back on in Config when you want to spend again.",
    };
  }
  if (spentCents + estimateCents > capCents) {
    return {
      allowed: false, spentCents, capCents, calls,
      reason: `This month is at ${fmt(spentCents)} of a ${fmt(capCents)} cap across ${calls} calls. Raise llm.monthly_cap_cents in Config, or wait for the month to roll.`,
    };
  }
  return { allowed: true, reason: "", spentCents, capCents, calls };
}

/// Write the call to the ledger. Called for FAILURES TOO.
///
/// A call that errors after the tokens were read still cost money, and a loop
/// that fails every time is precisely the runaway the cap exists to stop. A
/// ledger of successes only would watch that loop spend all month and report
/// zero.
export async function recordSpend(args: {
  purpose: string;
  model: string;
  inputTokens?: number;
  outputTokens?: number;
  ok: boolean;
  error?: string | null;
  ref?: string | null;
}): Promise<number> {
  const inTok = args.inputTokens ?? 0;
  const outTok = args.outputTokens ?? 0;
  const cents = costCents(args.model, inTok, outTok);
  try {
    await supabaseAdmin().from("llm_spend").insert({
      purpose: args.purpose,
      model: args.model,
      input_tokens: inTok,
      output_tokens: outTok,
      cents,
      ok: args.ok,
      error: args.error ?? null,
      ref: args.ref ?? null,
    });
  } catch {
    // Never let bookkeeping break the thing it is measuring. A lost ledger row
    // understates the month by a few cents; a thrown error here would fail an
    // extraction that already succeeded and already cost money.
  }
  return cents;
}

export const fmt = (cents: number) => `$${(cents / 100).toFixed(2)}`;
