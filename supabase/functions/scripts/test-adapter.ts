// Verify the table parser against a saved HTML fixture BEFORE deploying.
//   1. Save the source page:  curl -A "fructaBot/0.1" "<url>" > fixture.html
//   2. Run:  deno run --allow-read scripts/test-adapter.ts fixture.html
import { parseTable } from "../scrape-aggregator/adapters/industry-table.ts";

const path = Deno.args[0] ?? "fixture.html";
const rows = parseTable(await Deno.readTextFile(path), "KES");
console.log(`parsed ${rows.length} rows:`);
for (const r of rows) console.log(`  ${r.rate.toFixed(2)}%  ${r.name}`);
