"use client";

import { useState } from "react";
import { uploadCompanyLogo, removeCompanyLogo } from "./actions";
import { IconCheck } from "../_icons";

// The house standard, enforced softly here and rendered identically on web + app:
//   512×512 PNG (square), the brand MARK/icon (not the wordmark), on its own
//   background. The app shows it on a white circular chip so it reads on both
//   light and dark themes; square keeps it from being cropped oddly.
const STANDARD = "512×512 PNG · square · brand mark, not wordmark";
const chip =
  "h-9 w-9 rounded-full border border-line bg-white object-contain p-0.5";

export function LogoCell({
  id,
  type,
  logoUrl,
}: {
  id: string;
  type: string;
  logoUrl: string | null;
}) {
  const [preview, setPreview] = useState<string | null>(null);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    setNote(null);
    setPreview(null);
    if (!f) return;
    if (f.size > 2 * 1024 * 1024) setNote({ ok: false, text: "Over 2 MB" });
    const url = URL.createObjectURL(f);
    setPreview(url);
    const img = new Image();
    img.onload = () => {
      const square = Math.abs(img.width - img.height) <= 2;
      if (!square) {
        setNote({ ok: false, text: `Not square (${img.width}×${img.height}) — will centre-crop` });
      } else if (img.width < 256) {
        setNote({ ok: false, text: `Small (${img.width}px) — 512px recommended` });
      } else {
        setNote({ ok: true, text: `${img.width}×${img.height}` });
      }
    };
    img.src = url;
  }

  if (logoUrl) {
    return (
      <div className="flex items-center gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={logoUrl} alt="" className={chip} />
        <form action={removeCompanyLogo}>
          <input type="hidden" name="id" value={id} />
          <input type="hidden" name="logo_url" value={logoUrl} />
          <button className="text-xs text-faint hover:text-bad">Remove</button>
        </form>
      </div>
    );
  }

  return (
    <form action={uploadCompanyLogo} className="flex items-center gap-2">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="type" value={type} />
      {preview ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={preview} alt="" className={chip} />
      ) : (
        <div className="h-9 w-9 rounded-full border border-dashed border-line" />
      )}
      <div className="flex flex-col gap-0.5">
        <input
          type="file"
          name="file"
          accept="image/png,image/webp,image/jpeg,image/svg+xml"
          required
          onChange={onPick}
          className="w-36 text-xs text-faint file:mr-2 file:rounded file:border file:border-line file:bg-panel2 file:px-2 file:py-1 file:text-xs file:text-mute"
        />
        {note ? (
          <span className={"inline-flex items-center gap-1 text-[10px] " + (note.ok ? "text-live" : "text-warn")}>
            {note.ok && <IconCheck size={11} />}
            {note.text}
          </span>
        ) : (
          <span className="text-[10px] text-faint" title={STANDARD}>
            {STANDARD}
          </span>
        )}
      </div>
      <button className="rounded-md border border-gold/50 bg-gold/10 px-2 py-1 text-xs font-medium text-gold hover:bg-gold/20">
        Upload
      </button>
    </form>
  );
}
