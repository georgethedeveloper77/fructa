import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pdf-parse v2 wraps pdfjs, which loads its worker off disk at runtime. The
  // bundler cannot trace that, so the package stays external or the first PDF
  // upload fails in production with a missing worker.
  serverExternalPackages: ["pdf-parse"],

  experimental: {
    serverActions: {
      // Server Actions cap request bodies at 1 MB by default, which blocks
      // essentially every real fact sheet: they run 2 to 10 MB, and the failure
      // surfaces as a stack trace naming a React component with no mention of
      // file size.
      //
      // Keep this in step with MAX_PDF_BYTES in lib/factsheet/limits.ts. Set
      // slightly above it on purpose: the multipart envelope adds a little to
      // the raw file, so a PDF exactly at the app's limit must not be rejected
      // by the framework before the app's own message can explain why.
      bodySizeLimit: "14mb",
    },
  },
};

export default nextConfig;
