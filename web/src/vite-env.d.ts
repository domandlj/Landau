/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** "browser": check in the page (src/engine.ts) instead of on the dev server */
  readonly VITE_ENGINE?: string;
}
