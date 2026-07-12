import "./globals.css";

export const metadata = { title: "Fructa Admin" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      {/*
        Browser extensions (ColorZilla writes cz-shortcut-listen, Grammarly and
        LastPass do the same thing) mutate <body> before React hydrates, which
        React then reports as a hydration mismatch it cannot patch. The markup is
        correct; the attribute is not ours. suppressHydrationWarning silences that
        one node's attribute diff and nothing else: mismatches in the tree below
        are still reported normally.
      */}
      <body suppressHydrationWarning>
        <div className="min-h-screen">{children}</div>
      </body>
    </html>
  );
}
