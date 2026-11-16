import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    target: "es2022",
    // Hashed bundles go to /static/ so nginx can cache them for a year, while
    // the hand-named files in public/assets/ keep a short cache.
    assetsDir: "static",
  },
  ssr: {
    // Bundle MUI for the prerender so Node does not resolve its deep icon imports.
    noExternal: [/^@mui\//, /^@emotion\//],
  },
});
