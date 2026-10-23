import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "katex/dist/katex.min.css";
import "./styles.css";
import { App } from "./App";
import { applyTheme, loadTheme } from "./theme";

// before the first render, so the page never flashes the other theme
applyTheme(loadTheme(), false);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
