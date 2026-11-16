import ReactDOM from "react-dom/client";
import Root from "./Root.jsx";
import "./styles.css";

// The build prerenders the page into #root (see scripts/prerender.mjs), so
// crawlers and link previews get the full text. Hydrate that markup when it is
// there and fall back to a fresh render in `npm run dev`.
const container = document.getElementById("root");
if (container.hasChildNodes()) {
  ReactDOM.hydrateRoot(container, <Root />);
} else {
  ReactDOM.createRoot(container).render(<Root />);
}
