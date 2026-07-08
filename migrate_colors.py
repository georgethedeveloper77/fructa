#!/usr/bin/env python3
"""
migrate_colors.py — fructa A1 colour sweep.

Rewrites `AppColors.*` references to the token system (`context.c.<token>`) so
the migrated screens become light/dark + accent aware. Handles the two things a
naive sed gets wrong:
  1. strips `const` from any widget subtree that now contains a token, and
  2. injects `final c = context.c;` into build methods (block or arrow-bodied)
     that use tokens.

It does NOT touch files that get rewritten later (compare, fund_detail,
rate_chart) or dead files (filter_sheet, category_cards) or theme.dart itself.
`category_colors.dart` has no BuildContext, so its one reference is inlined to a
literal instead.

Safe to run repeatedly (idempotent). Commit first, then eyeball `git diff`.
Anything it can't prove safe is printed under REVIEW — nothing is silently
half-migrated.

    python3 migrate_colors.py            # apply
    python3 migrate_colors.py --dry-run  # report only, no writes
"""

import os
import re
import sys

# old AppColors member -> token member on context.c
MAP = {
    "bg": "bg",
    "panel": "s1",
    "panel2": "s2",
    "line": "line",
    "ink": "text",
    "mute": "muted",
    "faint": "faint",
    "gold": "accent",
    "live": "up",
    "bad": "down",
}
# raw hex for no-context files (kept const, no theme awareness needed)
LITERAL = {
    "bg": "0xFF060709", "panel": "0xFF0D0F13", "panel2": "0xFF13161C",
    "line": "0xFF1B1F27", "ink": "0xFFF3F5F8", "mute": "0xFF8A92A3",
    "faint": "0xFF555D6B", "gold": "0xFFE7B24C", "live": "0xFF3DDC97",
    "bad": "0xFFFF6B6B",
}
TOKENS = set(MAP.values())
TOKEN_RE = re.compile(r"\bc\.(" + "|".join(sorted(TOKENS, key=len, reverse=True)) + r")\b")

# Files to migrate to context.c (live screens with a BuildContext in scope).
CONTEXT_FILES = [
    "lib/app/lock_gate.dart",
    "lib/features/alerts/alerts_page.dart",
    "lib/features/portfolio/portfolio_page.dart",
    "lib/features/portfolio/add_holding_page.dart",
    "lib/features/portfolio/manage_holding_sheet.dart",
    "lib/features/portfolio/projection_card.dart",
    "lib/core/widgets/fund_logo.dart",
]
# No BuildContext -> inline literals.
LITERAL_FILES = [
    "lib/core/category_colors.dart",
]
# Rewritten in a later phase or dead -> intentionally left on the shim.
SKIP_NOTE = {
    "lib/features/compare/compare_page.dart": "rewritten in B1.2",
    "lib/features/fund_detail/fund_detail_page.dart": "becomes company page in B2",
    "lib/features/fund_detail/widgets/rate_chart.dart": "rewritten in B2",
    "lib/features/markets/filter_sheet.dart": "retired (folded into sort pills)",
    "lib/features/markets/widgets/category_cards.dart": "retired",
    "lib/core/theme.dart": "shim lives here",
}


# ── scanning helpers ───────────────────────────────────────────────────────

def blank_noncode(text: str) -> str:
    """Return a copy with string/comment bytes replaced by spaces (length
    preserved) so regex/scanning never matches inside strings or comments."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        two = text[i:i + 2]
        if two == "//":
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if two == "/*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                out[k] = " " if text[k] != "\n" else "\n"
            i = j
            continue
        if ch in "'\"":
            q = ch
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == q:
                    j += 1
                    break
                j += 1
            for k in range(i, min(j, n)):
                out[k] = " " if text[k] != "\n" else "\n"
            i = j
            continue
        i += 1
    return "".join(out)


def match_bracket(text: str, i: int) -> int:
    """Index of the bracket matching the opener at `i`, skipping strings/
    comments. Returns -1 if unbalanced."""
    n = len(text)
    depth = 0
    j = i
    while j < n:
        ch = text[j]
        two = text[j:j + 2]
        if two == "//":
            k = text.find("\n", j)
            j = n if k == -1 else k
            continue
        if two == "/*":
            k = text.find("*/", j + 2)
            j = n if k == -1 else k + 2
            continue
        if ch in "'\"":
            q = ch
            j += 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == q:
                    j += 1
                    break
                j += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def line_of(text: str, idx: int) -> int:
    return text.count("\n", 0, idx) + 1


# ── transforms ─────────────────────────────────────────────────────────────

def replace_refs(text: str, mode: str):
    """AppColors.X -> c.token (context) or const Color(hex) (literal)."""
    blank = blank_noncode(text)
    hits = list(re.finditer(r"\bAppColors\.(\w+)", blank))
    count = 0
    unknown = []
    for m in reversed(hits):
        member = m.group(1)
        if member not in MAP:
            unknown.append((line_of(text, m.start()), member))
            continue
        if mode == "literal":
            rep = f"const Color({LITERAL[member]})"
        else:
            rep = f"c.{MAP[member]}"
        text = text[:m.start()] + rep + text[m.end():]
        count += 1
    return text, count, unknown


# context method headers: `... build(BuildContext context ...)` etc.
HEADER_ARROW = re.compile(
    r"(?:[\w<>?, ]+\s+)?\b\w+\s*\([^;{]*?\bBuildContext\s+context\b[^;{]*?\)\s*(?:async\s*)?=>",
)
HEADER_BLOCK = re.compile(
    r"(?:[\w<>?, ]+\s+)?\b\w+\s*\([^;{]*?\bBuildContext\s+context\b[^;{]*?\)\s*(?:async\s*)?\{",
)


def convert_arrow_builds(text: str):
    """`X(BuildContext context) => expr;` -> block body with `final c` when the
    expression uses a token."""
    converted = 0
    while True:
        blank = blank_noncode(text)
        m = HEADER_ARROW.search(blank)
        found = None
        # iterate all, act on first whose expr uses a token & not yet converted
        for m in HEADER_ARROW.finditer(blank):
            arrow_end = m.end()  # just after =>
            # expression runs until the `;` at depth 0
            j = arrow_end
            depth = 0
            n = len(text)
            end = -1
            while j < n:
                ch = blank[j]
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif ch == ";" and depth == 0:
                    end = j
                    break
                j += 1
            if end == -1:
                continue
            expr = text[arrow_end:end]
            if not TOKEN_RE.search(expr):
                continue
            found = (m.start(), arrow_end, end, expr)
            break
        if not found:
            break
        hstart, aend, end, expr = found
        head = text[hstart:aend - 2]  # drop the `=>`
        block = head + "{\n    final c = context.c;\n    return" + expr + ";\n  }"
        text = text[:hstart] + block + text[end + 1:]
        converted += 1
    return text, converted


def inject_block_builds(text: str):
    """Insert `final c = context.c;` after the `{` of each context block method
    that uses a token and doesn't already declare it."""
    injected = 0
    blank = blank_noncode(text)
    inserts = []
    for m in HEADER_BLOCK.finditer(blank):
        brace = m.end() - 1  # position of `{`
        close = match_bracket(text, brace)
        if close == -1:
            continue
        body = text[brace + 1:close]
        if not TOKEN_RE.search(body):
            continue
        if "final c = context.c" in body:
            continue
        inserts.append(brace + 1)
        injected += 1
    for pos in sorted(inserts, reverse=True):
        text = text[:pos] + "\n    final c = context.c;" + text[pos:]
    return text, injected


CONST_RE = re.compile(r"\bconst\b")


def strip_const(text: str):
    """Remove `const` from any construct whose span contains a token."""
    blank = blank_noncode(text)
    # token positions (recomputed on current text)
    token_starts = [m.start() for m in TOKEN_RE.finditer(text)]
    removals = []
    for m in CONST_RE.finditer(blank):
        i = m.end()
        n = len(text)
        while i < n and blank[i] in " \t\n":
            i += 1
        if i >= n:
            continue
        ch = blank[i]
        if ch in "[{(":
            open_i = i
        else:
            # const Type(.named)? <...>? (  — advance over identifier chunk
            j = i
            while j < n and (blank[j].isalnum() or blank[j] in "_.<>, "):
                j += 1
            # back up to the first bracket in [i, j]
            open_i = -1
            k = i
            while k < j:
                if blank[k] in "([{":
                    open_i = k
                    break
                k += 1
            if open_i == -1:
                # e.g. `const Foo bar` field — find next bracket after
                while j < n and blank[j] not in "([{;":
                    j += 1
                if j >= n or blank[j] == ";":
                    continue
                open_i = j
        close = match_bracket(text, open_i)
        if close == -1:
            continue
        if any(open_i <= t <= close for t in token_starts):
            removals.append((m.start(), m.end()))
    removed = 0
    for start, end in sorted(removals, reverse=True):
        after = end
        while after < len(text) and text[after] in " \t":
            after += 1
        text = text[:start] + text[after:]
        removed += 1
    return text, removed


def find_review(text: str):
    """Named methods that use a token but have neither BuildContext nor an
    injected `final c` — likely helpers needing context threaded in. Local
    functions inside a build capture `c`, so these may be false positives:
    flagged for review, not auto-changed."""
    blank = blank_noncode(text)
    flagged = []
    for m in re.finditer(r"\b(\w+)\s*\(([^;{}]*)\)\s*(?:async\s*)?[{=]", blank):
        name = m.group(1)
        params = m.group(2)
        if name in ("if", "for", "while", "switch", "catch", "return"):
            continue
        # A ':' in the "params" means this is a call with named args (e.g.
        # Column(children: ...)), not a method declaration — skip.
        if ":" in params:
            continue
        # body span
        brace = text.find("{", m.end() - 1)
        arrow = m.group(0).rstrip().endswith("=")
        if arrow:
            # arrow body to `;`
            j = m.end()
            depth = 0
            end = -1
            while j < len(text):
                cch = blank[j]
                if cch in "([{":
                    depth += 1
                elif cch in ")]}":
                    depth -= 1
                elif cch == ";" and depth == 0:
                    end = j
                    break
                j += 1
            body = text[m.end():end] if end != -1 else ""
        else:
            close = match_bracket(text, m.end() - 1)
            body = text[m.end():close] if close != -1 else ""
        if not TOKEN_RE.search(body):
            continue
        if "BuildContext" in params or "final c = context.c" in body:
            continue
        flagged.append((line_of(text, m.start()), name))
    return flagged


def process(path: str, mode: str, dry: bool):
    with open(path, encoding="utf-8") as fh:
        orig = fh.read()
    text = orig
    text, n_ref, unknown = replace_refs(text, mode)
    report = {"refs": n_ref, "unknown": unknown, "arrow": 0, "inject": 0,
              "const": 0, "review": []}
    if mode == "context" and n_ref:
        text, report["arrow"] = convert_arrow_builds(text)
        text, report["inject"] = inject_block_builds(text)
        text, report["const"] = strip_const(text)
        report["review"] = find_review(text)
    changed = text != orig
    if changed and not dry:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
    report["changed"] = changed
    return report


def main():
    dry = "--dry-run" in sys.argv
    if not os.path.isdir("lib"):
        sys.exit("Run from the repo root (no ./lib found).")

    print("=" * 64)
    print("fructa colour sweep" + ("  (dry run)" if dry else ""))
    print("=" * 64)

    total = 0
    review = []
    for path in CONTEXT_FILES + LITERAL_FILES:
        mode = "literal" if path in LITERAL_FILES else "context"
        if not os.path.exists(path):
            print(f"  skip (missing): {path}")
            continue
        r = process(path, mode, dry)
        total += r["refs"]
        flag = "·" if not r["changed"] else "✎"
        print(f"  {flag} {path}")
        print(f"      refs:{r['refs']}  arrow→block:{r['arrow']}  "
              f"inject c:{r['inject']}  const removed:{r['const']}")
        for ln, mem in r["unknown"]:
            print(f"      ! UNKNOWN AppColors.{mem}  (line {ln}) — left as-is")
        for ln, name in r["review"]:
            review.append((path, ln, name))

    if review:
        print("\nREVIEW — methods using tokens without an obvious BuildContext.")
        print("Local functions inside a build capture `c` and are fine; true")
        print("helpers need `BuildContext context` threaded in:")
        for path, ln, name in review:
            print(f"    {path}:{ln}  {name}(...)")

    print("\nSkipped (left on the shim on purpose):")
    for path, why in SKIP_NOTE.items():
        if os.path.exists(path):
            print(f"    {path} — {why}")

    print(f"\nTotal references migrated: {total}")
    print("Now run:  flutter analyze   then eyeball  git diff")


if __name__ == "__main__":
    main()
