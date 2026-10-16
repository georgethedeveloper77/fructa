"use client";

import { useState } from "react";

/** Ticks or clears every row checkbox that belongs to the bulk form. */
export function SelectAll({ form }: { form: string }) {
  const [on, setOn] = useState(false);
  return (
    <input
      type="checkbox"
      aria-label="Select all"
      className="accent-gold"
      checked={on}
      onChange={(e) => {
        const next = e.target.checked;
        setOn(next);
        document
          .querySelectorAll<HTMLInputElement>(`input[type="checkbox"][name="ids"][form="${form}"]`)
          .forEach((el) => {
            el.checked = next;
          });
      }}
    />
  );
}
