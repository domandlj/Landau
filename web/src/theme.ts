// Dark or light, remembered per browser. Dark is the default; styles.css
// switches its colors on <html data-theme="...">.
export type Theme = "dark" | "light";

const KEY = "landau.theme";

export function loadTheme(): Theme {
  try {
    return localStorage.getItem(KEY) === "light" ? "light" : "dark";
  } catch {
    return "dark";
  }
}

export function applyTheme(theme: Theme, remember = true) {
  document.documentElement.dataset.theme = theme;
  if (!remember) return;
  try {
    localStorage.setItem(KEY, theme);
  } catch {
    // private windows and blocked storage: the choice lasts for this page
  }
}
