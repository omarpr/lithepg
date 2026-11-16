import { renderToString } from "react-dom/server";
import createCache from "@emotion/cache";
import Root from "./Root.jsx";

// Compat mode keeps Emotion from writing inline <style> tags into the markup.
// The site's CSP blocks inline styles, and the client inserts MUI's styles
// itself when it hydrates.
export function render() {
  const cache = createCache({ key: "css", prepend: true });
  cache.compat = true;
  return renderToString(<Root styleCache={cache} />);
}
