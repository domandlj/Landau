import { spawn } from "node:child_process";
import { mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import type { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig, type Connect, type Plugin } from "vite";

// The Landau project root: the `landau` launcher and `modules/` live there.
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MODULES = path.join(ROOT, "modules");
// A module name is a file name and what `import` names, so an identifier.
const MODULE_NAME = /^[A-Za-z_][A-Za-z0-9_]{0,63}$/;
const TIMEOUT_MS = 60_000;

function send(res: ServerResponse, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.setEncoding("utf8");
    req.on("data", (chunk: string) => (data += chunk));
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

// Run `landau --json -` on the source and return its report. A report with a
// `fatal` field means landau itself failed (build error, crash, timeout).
// `module` is the module being edited, so its imports resolve as if the
// source were that file.
function check(source: string, module: string | undefined, res: ServerResponse): Promise<unknown> {
  return new Promise((resolve) => {
    const as = module && MODULE_NAME.test(module) ? ["--as", path.join(MODULES, `${module}.lan`)] : [];
    const child = spawn(path.join(ROOT, "landau"), ["--json", "--modules", MODULES, ...as, "-"], { cwd: ROOT });
    let stdout = "";
    let stderr = "";
    const fatal = (message: string) => resolve({ ok: false, errors: [], theories: [], fatal: message });
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      fatal(`landau took longer than ${TIMEOUT_MS / 1000}s and was stopped`);
    }, TIMEOUT_MS);
    // The browser cancels stale checks while you type; stop their processes too.
    res.on("close", () => {
      if (!res.writableEnded && child.exitCode === null) child.kill("SIGKILL");
    });
    child.stdout.on("data", (d: Buffer) => (stdout += d));
    child.stderr.on("data", (d: Buffer) => (stderr += d));
    child.on("error", (e) => {
      clearTimeout(timer);
      fatal(`could not start landau: ${e.message}`);
    });
    child.on("close", () => {
      clearTimeout(timer);
      try {
        resolve(JSON.parse(stdout));
      } catch {
        fatal(stderr.trim() || "landau produced no report");
      }
    });
    child.stdin.end(source);
  });
}

const api: Connect.NextHandleFunction = async (req, res, next) => {
  try {
    if (req.url === "/api/check" && req.method === "POST") {
      const { source, module } = JSON.parse(await readBody(req)) as { source?: unknown; module?: unknown };
      if (typeof source !== "string") return send(res, 400, { error: "expected { source: string }" });
      return send(res, 200, await check(source, typeof module === "string" ? module : undefined, res));
    }
    if (req.url === "/api/modules" && req.method === "GET") {
      const files = (await readdir(MODULES)).filter((f) => f.endsWith(".lan")).sort();
      const modules = await Promise.all(
        files.map(async (f) => ({ name: f.replace(/\.lan$/, ""), source: await readFile(path.join(MODULES, f), "utf8") })),
      );
      return send(res, 200, modules);
    }
    // PUT /api/modules/<name> { source }: save a module file
    // DELETE /api/modules/<name>: move it to modules/.trash, where it can be recovered
    const one = req.url?.match(/^\/api\/modules\/([^/?]+)$/);
    if (one && req.method === "DELETE") {
      const name = decodeURIComponent(one[1]);
      if (!MODULE_NAME.test(name)) return send(res, 400, { error: "not a module name" });
      const trash = path.join(MODULES, ".trash");
      await mkdir(trash, { recursive: true });
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      try {
        await rename(path.join(MODULES, `${name}.lan`), path.join(trash, `${name}-${stamp}.lan`));
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === "ENOENT") return send(res, 404, { error: `there is no module ${name}` });
        throw e;
      }
      return send(res, 200, { name, trashed: `modules/.trash/${name}-${stamp}.lan` });
    }
    if (one && req.method === "PUT") {
      const name = decodeURIComponent(one[1]);
      if (!MODULE_NAME.test(name)) {
        return send(res, 400, { error: "a module name starts with a letter or _ and has only letters, digits and _" });
      }
      const { source } = JSON.parse(await readBody(req)) as { source?: unknown };
      if (typeof source !== "string") return send(res, 400, { error: "expected { source: string }" });
      // write next to it and rename, so a failed write never leaves half a file
      const file = path.join(MODULES, `${name}.lan`);
      const tmp = `${file}.${process.pid}.tmp`;
      await writeFile(tmp, source, "utf8");
      await rename(tmp, file);
      return send(res, 200, { name });
    }
  } catch (e) {
    return send(res, 500, { error: String(e) });
  }
  next();
};

function landauApi(): Plugin {
  return {
    name: "landau-api",
    configureServer: (server) => void server.middlewares.use(api),
    configurePreviewServer: (server) => void server.middlewares.use(api),
  };
}

export default defineConfig({
  // The API exists only with VITE_ENGINE=server; by default checks run in the page.
  plugins: [react(), ...(process.env.VITE_ENGINE === "server" ? [landauApi()] : [])],
  // Keep the app local: with VITE_ENGINE=server the API runs code on this machine.
  server: { host: "127.0.0.1" },
  preview: { host: "127.0.0.1" },
});
