import type { Config } from "tailwindcss";

// Hex values mirror app/tokens.css, which mirrors lib/core/theme.dart, so a
// Tailwind utility (bg-panel, text-mute, border-line) paints the same colour
// as the app. Kept as hex rather than var() so opacity modifiers such as
// bg-gold/10 keep working. Change a value in all three places together.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#060709",
        panel: "#0D0F13",
        raise: "#13161C",
        panel2: "#1A1E26", // === raise2
        raise2: "#1A1E26",
        line: "#1B1F27",
        line2: "#282D37",
        ink: "#F3F5F8",
        mute: "#9AA2B2",
        faint: "#7A8290",
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
        sans: ["var(--font-inter)", "Inter", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "'Space Grotesk'", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
