// The JSON report printed by `landau --json` (see run_file_json in lib/check.ml).

/** "scalar", or "2-vector", "3-vector", ... */
export type Shape = string;

export interface Rendered {
  text: string;
  latex: string;
}

/** A dimension, as L/T (`latex`) and as L T^{-1} (`powers`), and the same in
 *  units (m/s, m s^{-1}) when units are declared for it. */
export interface DimRendered extends Rendered {
  powers: string;
  units_text?: string;
  units?: string;
  units_powers?: string;
}

interface Base {
  line: number;
}

export interface ImportItem extends Base {
  kind: "import";
  name: string;
}
export interface DimItem extends Base {
  kind: "dim";
  names: string[];
  /** How each is shown: dim Time (T) has the symbol T. */
  symbols: string[];
}
export interface ConstItem extends Base {
  kind: "const";
  consts: { name: string; symbol: string; dim: DimRendered; value: Rendered }[];
}
export interface ComputeItem extends Base {
  kind: "compute";
  /** Set when the result is named: compute E1 = ... */
  name?: string;
  symbol?: string;
  expr: Rendered;
  value: Rendered;
  dim: DimRendered;
}
export interface SimSeries {
  name: string;
  symbol: string;
  unit: { text: string; latex: string };
  dim: string;
  values: (number | null)[];
}
export interface SimulateItem extends Base {
  kind: "simulate";
  name: string;
  solver: string;
  equations: string[];
  t: SimSeries;
  series: SimSeries[];
}
export interface DiagramItem extends Base {
  kind: "diagram";
  name: string;
  eq: Rendered;
  dim: DimRendered;
  shape: Shape;
  body: Rendered;
  /** dir: a unit vector [x, y], or null when it cannot be drawn */
  forces: { name: string; symbol: string; magnitude: Rendered; dir: [number, number] | null }[];
  acceleration: { magnitude: Rendered; dir: [number, number] | null } | null;
  plane: [number, number] | null;
  /** what the picture needs values for (`draw α = 0.5`) */
  missing: string[];
  /** angles to show: at the body's center, or at the foot of the plane */
  marks: { label: Rendered; from: [number, number] | null; to: [number, number] | null; at: "center" | "foot" }[];
}
/** eigen name: A, or eigen name: K, M for K v = λ M v. */
export interface EigenItem extends Base {
  kind: "eigen";
  name: string;
  a: Rendered;
  b: Rendered | null;
  /** the eigenvalues' dimension: [A], or [K]/[M] */
  dim: DimRendered;
  /** each eigenvalue with its multiplicity and eigenvectors (first nonzero entry 1) */
  values: { value: Rendered; multiplicity: number; vectors: Rendered[] }[];
}

/** groups name: T from L, g -- the dimensionless groups (Buckingham π). */
export interface GroupsItem extends Base {
  kind: "groups";
  name: string;
  target: { name: string; symbol: string } | null;
  vars: { name: string; symbol: string }[];
  groups: Rendered[];
  /** T = sqrt(L/g)·Φ(θ0), when a target is given */
  solved: Rendered | null;
  /** variables no group can contain, with the dimension nothing cancels */
  absent: { name: string; symbol: string; dim: DimRendered }[];
}
export interface UnitsItem extends Base {
  kind: "units";
  /** factor: 1000, 1.602176634e-19 or pi/180; factor_latex: the same as LaTeX */
  units: { name: string; latex: string; dim: DimRendered; factor: string; factor_latex: string; base: boolean }[];
}
export interface AliasItem extends Base {
  kind: "alias";
  name: string;
  dim: DimRendered;
}
export interface VarItem extends Base {
  kind: "var";
  names: string[];
  symbols: string[];
  dim: DimRendered;
  attrs: string[];
  shape: Shape;
}
export interface DefItem extends Base {
  kind: "def";
  name: string;
  params: string[];
  latex: string;
  body: Rendered;
  scheme: { text: string; params: DimRendered[]; result: DimRendered };
  /** Accepted argument shapes; only present when vectors are in scope. */
  shapes?: string;
}
export interface LawItem extends Base {
  kind: "law";
  name: string;
  eq: Rendered;
  dim: DimRendered;
  shape: Shape;
}
export interface Step {
  name: string | null;
  op: string;
  line: number;
  eq: Rendered;
}
export interface DeriveItem extends Base {
  kind: "derive";
  name: string;
  eq: Rendered;
  dim: DimRendered;
  shape: Shape;
  /** The result reads x = x: the derivation proved an identity. */
  identity: boolean;
  uses: string[];
  assumes: string[];
  /** Integration constants introduced by solving a differential equation. */
  constants: { name: string; latex: string; dim: DimRendered }[];
  steps: Step[];
}
export interface ErrorItem extends Base {
  kind: "error";
  col: number | null;
  message: string;
  theory: string | null;
}

export type Item = ImportItem | DimItem | UnitsItem | ConstItem | ComputeItem | GroupsItem | EigenItem | SimulateItem | DiagramItem | AliasItem | VarItem | DefItem | LawItem | DeriveItem | ErrorItem;

export interface Theory {
  name: string;
  items: Item[];
}

export interface Report {
  ok: boolean;
  errors: ErrorItem[];
  theories: Theory[];
  /** Set when landau itself failed (did not build, crashed, timed out). */
  fatal?: string;
}

export interface Module {
  name: string;
  source: string;
}

/** Valid module names: what `import` can name. */
export const MODULE_NAME = /^[A-Za-z_][A-Za-z0-9_]{0,63}$/;

/** `module`: the module being edited, so its imports resolve as that file's. */
export async function checkSource(source: string, module: string | null, signal: AbortSignal): Promise<Report> {
  const res = await fetch("/api/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source, module }),
    signal,
  });
  if (!res.ok) throw new Error(`server error ${res.status}: ${await res.text()}`);
  return res.json();
}

export async function fetchModules(): Promise<Module[]> {
  const res = await fetch("/api/modules");
  if (!res.ok) throw new Error(`server error ${res.status}`);
  return res.json();
}

export async function saveModule(name: string, source: string): Promise<void> {
  const res = await fetch(`/api/modules/${encodeURIComponent(name)}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source }),
  });
  if (!res.ok) throw new Error((await res.json().catch(() => null))?.error ?? `server error ${res.status}`);
}

/** Moves the module to modules/.trash; returns where it went. */
export async function deleteModule(name: string): Promise<string> {
  const res = await fetch(`/api/modules/${encodeURIComponent(name)}`, { method: "DELETE" });
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new Error(body?.error ?? `server error ${res.status}`);
  return body.trashed;
}

/** The modules whose source imports `name`, as a file or as one of its theories.
 *  A module that defines a theory of the same name imports its own. */
export function importersOf(name: string, theories: string[], modules: Module[]): string[] {
  const targets = new Set([name, ...theories]);
  return modules
    .filter((m) => m.name !== name)
    .filter((m) => {
      const own = new Set([...m.source.matchAll(/^\s*theory\s+(\w+)/gmu)].map((t) => t[1]));
      return [...m.source.matchAll(/^\s*import\s+(\w+)(?:\s+from\s+(\w+))?/gmu)].some(
        ([, what, from]) => (from ? from === name : targets.has(what) && !own.has(what)),
      );
    })
    .map((m) => m.name);
}
