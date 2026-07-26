# One line needed in next.config.ts

pdf-parse v2 bundles pdfjs, which reads its own worker file off disk at
runtime. Next's bundler cannot trace that, so it must be left external:

```ts
const nextConfig: NextConfig = {
  // ... your existing config
  serverExternalPackages: ["pdf-parse"],
};
```

Without it the build may succeed and then fail at runtime with a missing
worker, which is the worse of the two failure modes because it only shows up
the first time somebody uploads a PDF.
