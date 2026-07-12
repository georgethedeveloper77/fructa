// Shared field primitives for Settings. Label and description sit left, control
// right, divider between rows: calmer than a stack of full-width inputs, and the
// description kills the guesswork about what a field actually drives.

export const input =
  "w-full rounded-lg border border-line bg-panel2 px-3 py-2 text-[13.5px] text-ink outline-none transition-colors placeholder:text-faint focus:border-gold/55";

export function Row({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="grid gap-5 border-t border-line py-3.5 first:border-t-0 first:pt-0 md:grid-cols-[172px_1fr]">
      <div className="pt-1.5">
        <div className="text-[13px] font-medium text-ink">{label}</div>
        {hint && <div className="mt-0.5 text-[11.5px] leading-snug text-faint">{hint}</div>}
      </div>
      <div className="min-w-0">{children}</div>
    </div>
  );
}

export function Card({
  id,
  title,
  note,
  badge,
  children,
}: {
  id: string;
  title: string;
  note?: string;
  badge?: "public" | "private";
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-24 overflow-hidden rounded-2xl border border-line bg-panel">
      <div className="flex items-start gap-3 px-5 pt-5">
        <div>
          <h2 className="text-[15px] font-semibold tracking-tight text-ink">{title}</h2>
          {note && <p className="mt-1 max-w-[34rem] text-[12.5px] leading-relaxed text-mute">{note}</p>}
        </div>
        {badge && (
          <span
            className={
              "ml-auto flex-none rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide " +
              (badge === "public" ? "bg-blue/10 text-blue" : "bg-panel2 text-faint")
            }
          >
            {badge}
          </span>
        )}
      </div>
      {children}
    </section>
  );
}
