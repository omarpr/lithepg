// Renders the page to static HTML after `vite build` so the shipped index.html
// carries the real content instead of an empty #root.
import { readFile, rm, writeFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const indexPath = path.join(root, "dist", "index.html");
const ssrDir = path.join(root, ".ssr");

const { render } = await import(pathToFileURL(path.join(ssrDir, "entry-server.js")).href);
const html = await readFile(indexPath, "utf8");
const placeholder = '<div id="root"></div>';
if (!html.includes(placeholder)) {
  throw new Error("dist/index.html has no empty #root to prerender into");
}
await writeFile(indexPath, html.replace(placeholder, `<div id="root">${render()}</div>`));
await rm(ssrDir, { recursive: true, force: true });
console.log("prerendered dist/index.html");
