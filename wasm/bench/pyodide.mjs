// Runs replay.py under Pyodide (CPython in wasm) and compares it with the
// native run saved in native.json: time per module and whether the replies
// are the same.
//
//   PYTHONHASHSEED=0 ../.venv/bin/python bench/replay.py > bench/native.json
//   npm run bench

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadPyodide } from "pyodide";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");

let t = performance.now();
// the hash seed must be fixed before Python starts, as the native worker does
const py = await loadPyodide({ env: { PYTHONHASHSEED: "0" } });
const boot = (performance.now() - t) / 1000;

t = performance.now();
await py.loadPackage(["sympy", "scipy"]);
const download = (performance.now() - t) / 1000;

py.FS.mkdirTree("/landau");
py.FS.mount(py.FS.filesystems.NODEFS, { root }, "/landau");
const out = py.runPython(`
import runpy, json
json.dumps(runpy.run_path("/landau/wasm/bench/replay.py")["run"]())
`);
const wasm = { boot_seconds: +boot.toFixed(3), sympy_load_seconds: +download.toFixed(3), ...JSON.parse(out) };
writeFileSync(resolve(here, "pyodide.json"), JSON.stringify(wasm, null, 2) + "\n");

const native = JSON.parse(readFileSync(resolve(here, "native.json"), "utf8"));
console.log(`native Python ${native.python}, SymPy ${native.sympy}; Pyodide Python ${wasm.python}, SymPy ${wasm.sympy}`);
console.log(`Pyodide start ${wasm.boot_seconds}s, SymPy+SciPy load ${wasm.sympy_load_seconds}s, import ${wasm.import_seconds}s (native import ${native.import_seconds}s)\n`);
console.log("module".padEnd(16) + "native".padStart(9) + "wasm".padStart(9) + "ratio".padStart(8) + "  same");
let tn = 0, tw = 0;
for (const [name, n] of Object.entries(native.modules)) {
  const w = wasm.modules[name];
  tn += n.seconds;
  tw += w.seconds;
  const ratio = n.seconds > 0.05 ? (w.seconds / n.seconds).toFixed(1) + "x" : "-";
  console.log(name.padEnd(16) + `${n.seconds}s`.padStart(9) + `${w.seconds}s`.padStart(9) + ratio.padStart(8) + "  " + (n.hash === w.hash ? "yes" : "NO"));
}
console.log("total".padEnd(16) + `${tn.toFixed(2)}s`.padStart(9) + `${tw.toFixed(2)}s`.padStart(9) + `${(tw / tn).toFixed(1)}x`.padStart(8));
