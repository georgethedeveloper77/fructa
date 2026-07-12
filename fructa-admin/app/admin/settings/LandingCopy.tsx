"use client";

import { useState } from "react";
import { saveCopy } from "./actions";
import { SettingsForm } from "./SettingsForm";
import { Row, input } from "./ui";

/*
 * Hero copy was being written blind. The preview renders the same lockup the
 * landing does (headline, gold accent line, subhead, buttons, microtrust) from
 * the values in the fields, so what you type is what you ship. Controlled inputs
 * feed the preview; FormData still carries them to the action on submit.
 */
export function LandingCopy({
  initial,
}: {
  initial: {
    hero_headline: string;
    hero_accent: string;
    hero_subhead: string;
    hero_microtrust: string;
    cta_headline: string;
    cta_subhead: string;
  };
}) {
  const [v, setV] = useState(initial);
  const set = (k: keyof typeof initial) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setV((s) => ({ ...s, [k]: e.target.value }));

  return (
    <SettingsForm action={saveCopy}>
      <Row label="Hero headline" hint="Line one, then the gold accent line.">
        <div className="grid grid-cols-2 gap-2.5">
          <input name="hero_headline" value={v.hero_headline} onChange={set("hero_headline")} className={input} />
          <input name="hero_accent" value={v.hero_accent} onChange={set("hero_accent")} className={input} />
        </div>
      </Row>

      <Row label="Hero subhead">
        <textarea name="hero_subhead" rows={3} value={v.hero_subhead} onChange={set("hero_subhead")} className={input} />
      </Row>

      <Row label="Microtrust line" hint="Small print under the store buttons.">
        <input name="hero_microtrust" value={v.hero_microtrust} onChange={set("hero_microtrust")} className={input} />
      </Row>

      <Row label="Closing CTA" hint="Headline and subhead at the foot of the page.">
        <div className="grid grid-cols-2 gap-2.5">
          <input name="cta_headline" value={v.cta_headline} onChange={set("cta_headline")} className={input} />
          <input name="cta_subhead" value={v.cta_subhead} onChange={set("cta_subhead")} className={input} />
        </div>
      </Row>

      <Row label="Preview" hint="The fructa.africa hero.">
        <div className="overflow-hidden rounded-xl border border-line bg-bg">
          <div className="flex items-center gap-1.5 border-b border-line bg-panel2 px-3 py-2">
            <span className="h-1.5 w-1.5 rounded-full bg-line2" />
            <span className="h-1.5 w-1.5 rounded-full bg-line2" />
            <span className="h-1.5 w-1.5 rounded-full bg-line2" />
            <span className="ml-1.5 font-mono text-[10.5px] text-faint">fructa.africa</span>
          </div>
          <div className="px-5 py-7 text-center">
            <h3 className="text-[23px] font-semibold leading-tight tracking-tight text-ink">
              {v.hero_headline || "Headline"}
              <span className="block text-gold">{v.hero_accent || "Accent line"}</span>
            </h3>
            <p className="mx-auto mt-2.5 max-w-[26rem] text-[13px] leading-relaxed text-mute">
              {v.hero_subhead || "Subhead"}
            </p>
            <div className="mt-4 flex justify-center gap-2">
              <span className="rounded-md bg-gold px-3.5 py-1.5 text-[11.5px] font-semibold text-[#191204]">
                Get the app
              </span>
              <span className="rounded-md border border-line2 px-3.5 py-1.5 text-[11.5px] font-semibold text-mute">
                See the rates
              </span>
            </div>
            <div className="mt-3.5 text-[10.5px] text-faint">{v.hero_microtrust}</div>
          </div>
        </div>
      </Row>
    </SettingsForm>
  );
}
