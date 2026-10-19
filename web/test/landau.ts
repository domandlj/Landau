// Runs `landau --json -` as the Vite server does (see check in vite.config.ts).
import { spawn } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { Report } from "../src/report";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const MODULES = path.join(ROOT, "modules");

/** Every module file, as the app's Modules menu lists them. */
export const modules = readdirSync(MODULES)
  .filter((f) => f.endsWith(".lan"))
  .sort()
  .map((f) => ({ name: f.replace(/\.lan$/, ""), source: readFileSync(path.join(MODULES, f), "utf8") }));

/** `as`: the module file the source is, so its imports resolve as that file's. */
export function check(source: string, as?: string): Promise<Report> {
  const args = ["--json", "--modules", MODULES, ...(as ? ["--as", as] : []), "-"];
  return new Promise((resolve, reject) => {
    const child = spawn(path.join(ROOT, "landau"), args, { cwd: ROOT });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d: Buffer) => (stdout += d));
    child.stderr.on("data", (d: Buffer) => (stderr += d));
    child.on("error", reject);
    child.on("close", () => {
      try {
        resolve(JSON.parse(stdout));
      } catch {
        reject(new Error(`landau produced no report: ${stderr.trim()}`));
      }
    });
    child.stdin.end(source);
  });
}

/** One line per error, to show in a failed assertion. */
export const errorLines = (r: Report) => [r.fatal, ...r.errors.map((e) => `${e.line}: ${e.message}`)].filter(Boolean);
