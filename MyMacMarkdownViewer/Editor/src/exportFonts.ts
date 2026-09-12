// Loaded only while exporting math. Inline data avoids fetch() on native
// custom URL schemes and keeps font bytes out of the initial editor script.
export const fontURLs = import.meta.glob('/node_modules/katex/dist/fonts/*.woff2', {
  query: '?inline', import: 'default', eager: true,
}) as Record<string, string>;
