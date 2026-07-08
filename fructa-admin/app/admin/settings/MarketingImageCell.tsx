"use client";

import { useRef, useState, useTransition } from "react";
import { uploadMarketingImage, removeMarketingImage, type Result } from "./actions";
import { IconCheck } from "../_icons";

// Rectangular image slot (screenshots / OG card): preview + upload/remove to the
// `marketing` bucket, URL stored in the given app_config key. Surfaces the real
// error text (e.g. "Storage: Bucket not found" if migration 0033 isn't pushed).
export function MarketingImageCell({
  configKey,
  url,
  ratio = "16 / 11",
  hint,
}: {
  configKey: string;
  url: string | null;
  ratio?: string;
  hint: string;
}) {
  const [preview, setPreview] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const fileRef = useRef<HTMLInputElement>(null);

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setMsg(null);
    setPreview(null);
    if (!f) return;
    if (f.size > 4 * 1024 * 1024) setMsg({ ok: false, text: "Over 4 MB — will be rejected" });
    setPreview(URL.createObjectURL(f));
  }

  function show(r: Result, okText: string) {
    setMsg(r.ok ? { ok: true, text: okText } : { ok: false, text: r.error ?? "Failed" });
  }

  function doUpload(fd: FormData) {
    start(async () => {
      const r = await uploadMarketingImage(fd);
      show(r, "Uploaded");
      if (r.ok && fileRef.current) fileRef.current.value = "";
    });
  }
  function doRemove(fd: FormData) {
    start(async () => show(await removeMarketingImage(fd), "Removed"));
  }

  const frame = "overflow-hidden rounded-lg border border-line bg-panel2";

  return (
    <div className="flex items-start gap-4">
      <div className={frame} style={{ aspectRatio: ratio, width: 220 }}>
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={preview} alt="" className="h-full w-full object-cover" />
        ) : url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center px-3 text-center text-[11px] text-faint">
            No image
          </div>
        )}
      </div>

      <div className="flex flex-col gap-2">
        <p className="text-[11px] text-faint">{hint}</p>

        <form action={doUpload} className="flex items-center gap-2">
          <input type="hidden" name="key" value={configKey} />
          <input
            ref={fileRef}
            type="file"
            name="file"
            accept="image/png,image/webp,image/jpeg"
            required
            onChange={onPick}
            className="w-44 text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute"
          />
          <button
            disabled={pending}
            className="rounded-md border border-gold/50 bg-gold/10 px-2.5 py-1 text-xs font-medium text-gold hover:bg-gold/20 disabled:opacity-40"
          >
            {pending ? "…" : "Upload"}
          </button>
        </form>

        {msg && (
          <span className={"inline-flex items-center gap-1 text-[11px] " + (msg.ok ? "text-live" : "text-bad")}>
            {msg.ok && <IconCheck size={11} />}
            {msg.text}
          </span>
        )}

        {url && (
          <form action={doRemove}>
            <input type="hidden" name="key" value={configKey} />
            <input type="hidden" name="url" value={url} />
            <button disabled={pending} className="text-xs text-faint hover:text-bad disabled:opacity-40">
              Remove
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
