"use client";

import { useState } from "react";
import { uploadMarketingImage, removeMarketingImage } from "./actions";
import { IconCheck } from "../_icons";

// Generic marketing image slot: preview + upload/remove to the `marketing`
// bucket, URL stored in the given app_config key. Mirrors LogoCell, but the
// frame is rectangular since these are screenshots / OG cards, not square marks.
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
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setNote(null);
    setPreview(null);
    if (!f) return;
    if (f.size > 4 * 1024 * 1024) setNote({ ok: false, text: "Over 4 MB" });
    const u = URL.createObjectURL(f);
    setPreview(u);
    const img = new Image();
    img.onload = () => setNote({ ok: true, text: `${img.width}×${img.height}` });
    img.src = u;
  }

  const frame = "overflow-hidden rounded-lg border border-line bg-panel2";
  const frameStyle = { aspectRatio: ratio, width: 220 } as const;

  return (
    <div className="flex items-start gap-4">
      <div className={frame} style={frameStyle}>
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

        <form action={uploadMarketingImage} className="flex items-center gap-2">
          <input type="hidden" name="key" value={configKey} />
          <input
            type="file"
            name="file"
            accept="image/png,image/webp,image/jpeg"
            required
            onChange={onPick}
            className="w-44 text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute"
          />
          <button className="rounded-md border border-gold/50 bg-gold/10 px-2.5 py-1 text-xs font-medium text-gold hover:bg-gold/20">
            Upload
          </button>
        </form>

        {note && (
          <span className={"inline-flex items-center gap-1 text-[10px] " + (note.ok ? "text-live" : "text-warn")}>
            {note.ok && <IconCheck size={11} />}
            {note.text}
          </span>
        )}

        {url && (
          <form action={removeMarketingImage}>
            <input type="hidden" name="key" value={configKey} />
            <input type="hidden" name="url" value={url} />
            <button className="text-xs text-faint hover:text-bad">Remove</button>
          </form>
        )}
      </div>
    </div>
  );
}
