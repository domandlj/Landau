// The app renders with throwOnError: false, so a bad formula still renders:
// a parse error as red source, an unknown command as red text with no error
// marker at all. To catch both, watch every call the app makes and render the
// same formula again with throwOnError: true.
import katex from "katex";
import { vi } from "vitest";

/** Runs `render` and returns each formula KaTeX rejected, with the reason. */
export function katexErrors(render: () => void): string[] {
  const errors: string[] = [];
  const original = katex.renderToString;
  const spy = vi.spyOn(katex, "renderToString").mockImplementation((latex, options) => {
    try {
      original(latex, { ...options, throwOnError: true });
    } catch (e) {
      errors.push(`${(e as Error).message}\n    in: ${latex}`);
    }
    return original(latex, options);
  });
  try {
    render();
  } finally {
    spy.mockRestore();
  }
  return errors;
}

