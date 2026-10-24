// Checks modules with the js_of_ocaml build of Landau and cas/worker.py in
// Pyodide, all inside Node, and compares each report with the native
// `landau --json`. No server and no Python process: what the browser will run.
//
//   dune build ./js/landau.bc.js && node wasm/smoke.mjs [module ...]

import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadPyodide } from "pyodide";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);

const py = await loadPyodide({ env: { PYTHONHASHSEED: "0" } });
await py.loadPackage(["sympy", "scipy"], { messageCallback: () => {} });
py.FS.writeFile("/home/pyodide/worker.py", readFileSync(resolve(root, "cas/worker.py"), "utf8"));
const answer = py.pyimport("worker").answer;

const { landau } = require(resolve(root, "_build/default/js/landau.bc.js"));
landau.setCas((line) => answer(line));
const names = readdirSync(resolve(root, "modules")).filter((f) => f.endsWith(".lan")).map((f) => f.slice(0, -4));
for (const n of names) landau.addModule(n, readFileSync(resolve(root, `modules/${n}.lan`), "utf8"));

let same = 0;
const wanted = process.argv.slice(2);
for (const n of wanted.length ? wanted : names) {
  const source = readFileSync(resolve(root, `modules/${n}.lan`), "utf8");
  const t = performance.now();
  const report = landau.check(source, n);
  const secs = ((performance.now() - t) / 1000).toFixed(2);
  let native;
  try {
    native = execFileSync(resolve(root, "landau"), ["--json", "--modules", resolve(root, "modules"), "--as", resolve(root, `modules/${n}.lan`), "-"], { input: source, cwd: root, encoding: "utf8" });
  } catch (e) {
    native = e.stdout; // landau exits 1 when the file has errors
  }
  const ok = report === native.trim();
  if (ok) same++;
  console.log(`${n.padEnd(16)} ${secs.padStart(6)}s  ${ok ? "same as native" : "DIFFERENT"}`);
}
console.log(`\n${same} of ${(wanted.length ? wanted : names).length} reports identical`);
