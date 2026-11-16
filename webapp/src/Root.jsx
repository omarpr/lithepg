import React from "react";
import { CacheProvider } from "@emotion/react";
import {
  CssBaseline,
  StyledEngineProvider,
  ThemeProvider,
  createTheme,
} from "@mui/material";
import App from "./App.jsx";

const theme = createTheme({
  palette: {
    mode: "dark",
    primary: { main: "#3c88ff" },
    background: { default: "#030914", paper: "#0a1932" },
  },
  typography: {
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
  },
  shape: { borderRadius: 12 },
  components: {
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: {
          minWidth: 0,
          textTransform: "none",
          letterSpacing: 0,
        },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: { fontWeight: 750 },
      },
    },
  },
});

// The prerender passes its own Emotion cache; StyledEngineProvider would
// replace it with one that writes inline <style> tags into the markup.
export default function Root({ styleCache }) {
  const content = (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <App />
    </ThemeProvider>
  );
  return (
    <React.StrictMode>
      {styleCache ? (
        <CacheProvider value={styleCache}>{content}</CacheProvider>
      ) : (
        <StyledEngineProvider injectFirst>{content}</StyledEngineProvider>
      )}
    </React.StrictMode>
  );
}
