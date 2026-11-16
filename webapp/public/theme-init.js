// Runs before the page paints so a saved light theme does not flash dark first.
// Kept as a file because the site's CSP does not allow inline scripts.
try {
  if (localStorage.getItem("lithepg-theme") === "light") {
    document.documentElement.dataset.theme = "light";
  }
} catch {
  // Storage can be blocked; the default dark theme still applies.
}
