/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** "server": check with the native landau on the dev server instead of in the page (src/engine.ts) */
  readonly VITE_ENGINE?: string;
}
