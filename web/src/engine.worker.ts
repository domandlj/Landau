// Landau without a server: the checker compiled to JavaScript (js/landau.ml,
// served as engine/landau.bc.js) and cas/worker.py running in Pyodide. Both
// live in this worker, so a check never blocks the page, and Python stays
// loaded between checks.
//
// In:  { id, source, module, modules: { name: source } }
// Out: { id, report }, and { status } while something loads

import workerPy from "../../cas/worker.py?raw";

const PYODIDE = "https://cdn.jsdelivr.net/pyodide/v314.0.7/full/";

interface Landau {
  setCas(f: (line: string) => string): void;
  addModule(name: string, source: string): void;
  check(source: string, module: string | null): string;
}

interface Request {
  id: number;
  source: string;
  module: string | null;
  modules: Record<string, string>;
}

interface Pyodide {
  loadPackage(names: string | string[], options?: { messageCallback?: (m: string) => void }): Promise<void>;
  pyimport(name: string): { answer: (line: string) => string };
  FS: { writeFile(path: string, data: string): void };
}

const post = (msg: unknown) => (self as unknown as Worker).postMessage(msg);
const quiet = { messageCallback: () => {} };

async function start(): Promise<{ py: Pyodide; landau: Landau }> {
  post({ status: "loading Python" });
  const { loadPyodide } = await import(/* @vite-ignore */ `${PYODIDE}pyodide.mjs`);
  // the hash seed must be fixed before Python starts, as the native worker does
  const py: Pyodide = await loadPyodide({ indexURL: PYODIDE, env: { PYTHONHASHSEED: "0" } });
  post({ status: "loading SymPy" });
  await py.loadPackage("sympy", quiet);
  py.FS.writeFile("/home/pyodide/worker.py", workerPy);
  const answer = py.pyimport("worker").answer;

  post({ status: "loading the checker" });
  const code = await (await fetch(`${import.meta.env.BASE_URL}engine/landau.bc.js`)).text();
  (0, eval)(code); // a classic script that sets globalThis.landau
  const landau = (globalThis as unknown as { landau: Landau }).landau;
  landau.setCas((line) => {
    // SciPy is large, so it is loaded for the first simulation: until then a
    // simulation fails, and the check runs again once SciPy is there
    if (!scipy && line.startsWith('{"op":"simulate"')) {
      wantsScipy = true;
      return JSON.stringify({ error: "SciPy is loading" });
    }
    return answer(line);
  });
  return { py, landau };
}

let engine: ReturnType<typeof start> | null = null;
let scipy = false;
let wantsScipy = false;

self.onmessage = async (e: MessageEvent<Request>) => {
  const { id, source, module, modules } = e.data;
  let report;
  try {
    engine ??= start().catch((err) => {
      engine = null; // try again on the next check
      throw err;
    });
    const { py, landau } = await engine;
    for (const [name, text] of Object.entries(modules)) landau.addModule(name, text);
    report = JSON.parse(landau.check(source, module));
    if (wantsScipy && !scipy) {
      post({ status: "loading SciPy" });
      await py.loadPackage("scipy", quiet);
      scipy = true;
      report = JSON.parse(landau.check(source, module));
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    report = { ok: false, errors: [], theories: [], fatal: `the in-browser checker failed: ${message}` };
  }
  post({ id, report });
};
