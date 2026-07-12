"use client";

import { useState } from "react";
import { SignalBank, type Template } from "./SignalBank";
import { MarketTab, type MarketData } from "./MarketTab";

export function InsightsTabs({ market, templates }: { market: MarketData; templates: Template[] }) {
  const [tab, setTab] = useState<"market" | "signal">("market");

  const tabBtn = (k: "market" | "signal", label: string) => (
    <button
      onClick={() => setTab(k)}
      className={"mr-6 -mb-px border-b-2 pb-2.5 text-sm font-semibold " +
        (tab === k ? "border-gold text-ink" : "border-transparent text-mute hover:text-ink")}
    >
      {label}
    </button>
  );

  return (
    <div>
      <div className="mb-5 flex items-center border-b border-line">
        {tabBtn("market", "Market")}
        {tabBtn("signal", "Signal bank")}
        <span className="ml-auto mb-2 font-mono text-[11px] text-faint">
          {tab === "market" ? `${market.mmfCount} MMF tracked` : `${templates.length} phrasings`}
        </span>
      </div>

      {tab === "market" ? <MarketTab data={market} /> : <SignalBank rows={templates} />}
    </div>
  );
}
