import { ImportClient } from "./ImportClient";
import { IconDownload } from "../_icons";

export const dynamic = "force-dynamic";

export default function ImportPage() {
  return (
    <div className="mx-auto max-w-3xl">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold tracking-tight">Import</h1>
        <p className="mt-1 text-sm text-mute">
          <strong className="font-medium text-ink">Weekly rates</strong>: paste the week&apos;s
          figures (or upload a CSV) and pick the date — matched by name, written to history;
          today&apos;s date also updates the live rate.{" "}
          <strong className="font-medium text-ink">CMA report</strong>: apply the quarterly
          composition extraction JSON — powers the &ldquo;What it holds&rdquo; pie on the
          Company page.{" "}
          <strong className="font-medium text-ink">Fund returns</strong>: paste each manager&apos;s
          monthly fact-sheet figures (1Y/3Y/5Y vs benchmark, best/worst month) — powers the
          Performance card.
        </p>
        <a
          href="/admin/import/template"
          className="mt-3 inline-flex items-center gap-1 rounded-md border border-line px-3 py-1.5 text-xs text-mute hover:border-gold/60 hover:text-gold"
        >
          <IconDownload size={13} /> Download name template (CSV)
        </a>
      </header>
      <ImportClient />
    </div>
  );
}
