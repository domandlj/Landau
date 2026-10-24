// The browser engine (VITE_ENGINE=browser): checks run in engine.worker.ts
// instead of on the server, the modules of modules/ are built into the app,
// and modules you save or delete are kept in this browser's localStorage.

import type { Module, Report } from "./report";

const BUILT_IN: Record<string, string> = Object.fromEntries(
  Object.entries(import.meta.glob("../../modules/*.lan", { query: "?raw", import: "default", eager: true })).map(
    ([path, source]) => [path.replace(/^.*\/(.*)\.lan$/, "$1"), source as string],
  ),
);

// { name: source } for saved modules, null for deleted ones
const STORE_KEY = "landau.modules";
type Store = Record<string, string | null>;

function load(): Store {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY) ?? "{}");
  } catch {
    return {};
  }
}

function store(s: Store) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(s));
  } catch {
    throw new Error("this browser does not let the page store modules");
  }
}

function modules(): Record<string, string> {
  const all: Record<string, string | null> = { ...BUILT_IN, ...load() };
  return Object.fromEntries(Object.entries(all).filter((e): e is [string, string] => e[1] !== null));
}

export async function fetchModules(): Promise<Module[]> {
  return Object.entries(modules())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([name, source]) => ({ name, source }));
}

export async function saveModule(name: string, source: string): Promise<void> {
  store({ ...load(), [name]: source });
}

export async function deleteModule(name: string): Promise<string> {
  store({ ...load(), [name]: null });
  return "this browser's storage (gone; the built-in copy, if any, is hidden)";
}

// ---- checks ----

interface Job {
  source: string;
  module: string | null;
  signal: AbortSignal;
  resolve: (r: Report) => void;
  reject: (e: unknown) => void;
}

let worker: Worker | null = null;
let running: Job | null = null;
let waiting: Job | null = null;
let nextId = 0;
const statusListeners = new Set<(s: string | null) => void>();

/** Calls f with what the engine is loading ("loading SymPy"), or null. */
export function onEngineStatus(f: (s: string | null) => void): () => void {
  statusListeners.add(f);
  return () => statusListeners.delete(f);
}

function getWorker(): Worker {
  if (worker) return worker;
  worker = new Worker(new URL("./engine.worker.ts", import.meta.url), { type: "module" });
  worker.onmessage = (e: MessageEvent<{ id?: number; report?: Report; status?: string }>) => {
    if (e.data.status) return statusListeners.forEach((f) => f(e.data.status!));
    statusListeners.forEach((f) => f(null));
    const job = running;
    running = null;
    job?.resolve(e.data.report!);
    pump();
  };
  return worker;
}

const aborted = () => new DOMException("superseded by a newer check", "AbortError");

// A check runs to the end once started, so while one runs only the newest
// request waits: typing fast does not pile up checks.
function pump() {
  if (running || !waiting) return;
  const job = waiting;
  waiting = null;
  if (job.signal.aborted) return job.reject(aborted());
  running = job;
  getWorker().postMessage({ id: nextId++, source: job.source, module: job.module, modules: modules() });
}

export function checkSource(source: string, module: string | null, signal: AbortSignal): Promise<Report> {
  return new Promise((resolve, reject) => {
    waiting?.reject(aborted());
    waiting = { source, module, signal, resolve, reject };
    pump();
  });
}
