import type { Config } from "tailwindcss";

// Values aligned 1:1 with fructa_admin_v2.html + admin-theme.css so Tailwind
// utilities (text-mute, bg-panel, border-line …) match the design-system
// classes exactly. Existing keys kept; a few v2 surfaces added.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0B0C0F",
        panel: "#0F1114",
        raise: "#13161B",
        panel2: "#191D24", // === raise2
        raise2: "#191D24",
        line: "#1D2129",
        line2: "#282D37",
        ink: "#EEF0F4",
        mute: "#8B93A2",
        faint: "#575E6C",
        gold: "#E7B24C",
        live: "#3DDC97", // === ok
        ok: "#3DDC97",
        warn: "#F0B542",
        bad: "#FF6B6B",
        blue: "#4E8FE8",
        violet: "#9A8BF3",
        teal: "#2FB5A0",
      },
      fontFamily: {
        mono: ["'Space Grotesk'", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
