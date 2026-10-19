import { useContext, useMemo, useState, type ReactNode } from "react";
import katex from "katex";
import { DERIV_MACROS, DerivStyleContext, useDimTex } from "./dimStyle";
import { FreeBody } from "./FreeBody";
import { SimPlot } from "./SimPlot";
import type {
  ComputeItem,
  DiagramItem,
  GroupsItem,
  SimulateItem,
  DefItem,
  DeriveItem,
  DimRendered,
  ErrorItem,
  Item,
  LawItem,
  Report,
  Shape,
  Theory,
  VarItem,
} from "./report";

export function Tex({ latex, display = false }: { latex: string; display?: boolean }) {
  const deriv = useContext(DerivStyleContext);
  const html = useMemo(
    () =>
      katex.renderToString(latex, {
        throwOnError: false,
        displayMode: display,
        strict: "ignore",
        macros: { "\\landauderiv": DERIV_MACROS[deriv] },
      }),
    [latex, display, deriv],
  );
  return <span className={display ? "tex tex-display" : "tex"} dangerouslySetInnerHTML={{ __html: html }} />;
}

// landau quotes code in messages with backticks: `v*t` [L]
function Message({ text }: { text: string }) {
  const parts = text.split(/(`[^`]*`|\[[^\]]*\])/g);
  return (
    <>
      {parts.map((p, i) =>
        p.startsWith("`") ? (
          <code key={i}>{p.slice(1, -1)}</code>
        ) : p.startsWith("[") ? (
          <span key={i} className="dim-text">{p}</span>
        ) : (
          <span key={i}>{p}</span>
        ),
      )}
    </>
  );
}

type GoTo = (line: number) => void;

// 1.602176634e-19 as 1.602176634 × 10^{-19}
const factorTex = (f: string) => f.replace(/^(.*)e\+?(-?\d+)$/, (_, m, e) => `${m} \\times 10^{${e}}`);

function LineLink({ line, goTo }: { line: number; goTo: GoTo }) {
  return (
    <button className="line-link" onClick={() => goTo(line)} title="Show in editor">
      line {line}
    </button>
  );
}

function Card({ kind, name, line, goTo, error, children }: {
  kind: string; name?: string; line: number; goTo: GoTo; error?: boolean; children: ReactNode;
}) {
  return (
    <article className={error ? "card card-error" : "card"}>
      <header className="card-head">
        <span className={`kind kind-${kind}`}>{kind}</span>
        {name && <span className="card-name">{name}</span>}
        <LineLink line={line} goTo={goTo} />
      </header>
      {children}
    </article>
  );
}

function DimBadge({ dim, shape }: { dim: DimRendered; shape: Shape }) {
  const latex = useDimTex()(dim);
  return (
    <span className="dim-badge" title={shape === "scalar" ? "dimension" : `a ${shape} whose components have this dimension`}>
      {shape !== "scalar" && <span className="shape-tag">{shape}</span>}
      <Tex latex={latex} />
    </span>
  );
}

function Law({ item, goTo }: { item: LawItem; goTo: GoTo }) {
  return (
    <Card kind="law" name={item.name} line={item.line} goTo={goTo}>
      <div className="equation">
        <Tex latex={item.eq.latex} display />
        <DimBadge dim={item.dim} shape={item.shape} />
      </div>
    </Card>
  );
}

function Def({ item, goTo }: { item: DefItem; goTo: GoTo }) {
  const dimTex = useDimTex();
  const sig = `\\left(${item.scheme.params.map(dimTex).join(",\\ ")}\\right) \\to ${dimTex(item.scheme.result)}`;
  return (
    <Card kind="def" name={item.name} line={item.line} goTo={goTo}>
      <div className="equation">
        <Tex latex={`${item.latex} = ${item.body.latex}`} display />
      </div>
      <div className="meta">
        <span className="meta-label">dimensions</span>
        <Tex latex={sig} />
      </div>
      {item.shapes && (
        <div className="meta">
          <span className="meta-label">shapes</span>
          <span className="shapes">{item.shapes.replace(/->/g, "→")}</span>
        </div>
      )}
    </Card>
  );
}

function Derive({ item, goTo }: { item: DeriveItem; goTo: GoTo }) {
  const dimTex = useDimTex();
  const [open, setOpen] = useState(false);
  return (
    <Card kind="derive" name={item.name} line={item.line} goTo={goTo}>
      <div className="equation">
        <Tex latex={item.eq.latex} display />
        {item.identity && <span className="identity" title="the derivation reduced the law to x = x">holds identically ✓</span>}
        <DimBadge dim={item.dim} shape={item.shape} />
      </div>
      <dl className="provenance">
        <dt>from</dt>
        <dd>{item.uses.map((u) => <span key={u} className="chip">{u}</span>)}</dd>
        {item.assumes.length > 0 && (
          <>
            <dt>assumes</dt>
            <dd>{item.assumes.map((a) => <span key={a} className="chip chip-assume">{a}</span>)}</dd>
          </>
        )}
        {item.constants.length > 0 && (
          <>
            <dt>constants</dt>
            <dd>
              {item.constants.map((c) => (
                <span key={c.name} className="chip" title="integration constant, with its inferred dimension">
                  <Tex latex={`${c.latex} : ${dimTex(c.dim)}`} />
                </span>
              ))}
            </dd>
          </>
        )}
      </dl>
      <button className="steps-toggle" onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? "▾" : "▸"} {item.steps.length} step{item.steps.length === 1 ? "" : "s"}
      </button>
      {open && (
        <ol className="steps">
          {item.steps.map((s, i) => (
            <li key={i}>
              <span className="step-name">{s.name ?? "result"}</span>
              <button className="step-op" onClick={() => goTo(s.line)} title={`line ${s.line}`}>{s.op}</button>
              <Tex latex={s.eq.latex} />
            </li>
          ))}
        </ol>
      )}
    </Card>
  );
}

function Compute({ item, goTo }: { item: ComputeItem; goTo: GoTo }) {
  const lhs = item.symbol ? `${item.symbol} = ` : "";
  return (
    <Card kind="compute" name={item.name} line={item.line} goTo={goTo}>
      <div className="equation">
        <Tex latex={`${lhs}${item.expr.latex} = ${item.value.latex}`} display />
        <DimBadge dim={item.dim} shape="scalar" />
      </div>
    </Card>
  );
}

function Groups({ item, goTo }: { item: GroupsItem; goTo: GoTo }) {
  const dimTex = useDimTex();
  return (
    <Card kind="groups" name={item.name} line={item.line} goTo={goTo}>
      {item.groups.length === 0 && <p className="groups-note">No dimensionless groups.</p>}
      <div className="groups">
        {item.groups.map((g, i) => (
          <Tex key={i} latex={`\\Pi_{${i + 1}} = ${g.latex}`} />
        ))}
      </div>
      {item.solved && (
        <div className="equation">
          <Tex latex={item.solved.latex} display />
        </div>
      )}
      {item.solved && item.groups.length === 1 && (
        <p className="groups-note">
          <Tex latex="C" /> is a dimensionless constant.
        </p>
      )}
      {item.absent.map((a) => (
        <p key={a.name} className="groups-note">
          <Tex latex={a.symbol} /> cannot appear: no product of the others has its dimension, <Tex latex={dimTex(a.dim)} />.
        </p>
      ))}
    </Card>
  );
}

function Diagram({ item, goTo }: { item: DiagramItem; goTo: GoTo }) {
  return (
    <Card kind="diagram" name={item.name} line={item.line} goTo={goTo}>
      <div className="equation">
        <Tex latex={item.eq.latex} display />
        <DimBadge dim={item.dim} shape={item.shape} />
      </div>
      <FreeBody item={item} />
    </Card>
  );
}

function Simulate({ item, goTo }: { item: SimulateItem; goTo: GoTo }) {
  return (
    <Card kind="simulate" name={item.name} line={item.line} goTo={goTo}>
      <SimPlot item={item} />
    </Card>
  );
}

function ErrorCard({ item, goTo }: { item: ErrorItem; goTo: GoTo }) {
  return (
    <Card kind="error" line={item.line} goTo={goTo} error>
      <p className="error-message"><Message text={item.message} /></p>
    </Card>
  );
}

// Imports, dimensions and variables, gathered into one compact block.
function Quantities({ items, goTo }: { items: Item[]; goTo: GoTo }) {
  const dimTex = useDimTex();
  const imports = items.flatMap((i) => (i.kind === "import" ? [i] : []));
  const dims = items.flatMap((i) => (i.kind === "dim" ? i.symbols : []));
  const units = items.flatMap((i) => (i.kind === "units" ? i.units : []));
  const aliases = items.flatMap((i) => (i.kind === "alias" ? [i] : []));
  const vars = items.flatMap((i) => (i.kind === "var" ? [i] : []));
  const consts = items.flatMap((i) => (i.kind === "const" ? i.consts.map((c) => ({ ...c, line: i.line })) : []));
  if (!imports.length && !dims.length && !units.length && !aliases.length && !vars.length && !consts.length) return null;
  const row = (v: VarItem, k: number) => (
    <tr key={k} onClick={() => goTo(v.line)}>
      <td><Tex latex={v.symbols.join(",\\ ")} /></td>
      <td><Tex latex={dimTex(v.dim)} /></td>
      <td>{v.attrs.map((a) => <span key={a} className="chip chip-attr">{a}</span>)}</td>
    </tr>
  );
  return (
    <div className="quantities">
      {(imports.length > 0 || dims.length > 0 || units.length > 0 || aliases.length > 0) && (
        <div className="quantity-line">
          {imports.map((i) => <span key={i.name} className="chip chip-import">import {i.name}</span>)}
          {dims.length > 0 && (
            <span className="chip">
              base <Tex latex={dims.map((d) => `\\mathsf{${d}}`).join(",\\ ")} />
            </span>
          )}
          {units.map((u) => (
            <span key={u.name} className="chip chip-unit" title={u.base ? "base unit" : `factor ${u.factor}`}>
              <Tex latex={`${u.latex} ${u.base ? ":" : "="} ${u.base || u.factor === "1" ? "" : factorTex(u.factor) + "\\,"}${dimTex(u.dim)}`} />
            </span>
          ))}
          {aliases.map((a) => (
            <span key={a.name} className="chip">
              {a.name} = <Tex latex={dimTex(a.dim)} />
            </span>
          ))}
        </div>
      )}
      {(vars.length > 0 || consts.length > 0) && (
        <table className="vars">
          <tbody>
            {vars.map(row)}
            {consts.map((c) => (
              <tr key={c.name} onClick={() => goTo(c.line)}>
                <td><Tex latex={c.symbol} /></td>
                <td><Tex latex={dimTex(c.dim)} /></td>
                <td className="const-value"><Tex latex={`= ${c.value.latex}`} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

function TheoryView({ theory, goTo }: { theory: Theory; goTo: GoTo }) {
  const errors = theory.items.filter((i) => i.kind === "error").length;
  return (
    <section className="theory">
      <h2>
        <span className="theory-kw">theory</span> {theory.name}
        {errors > 0 && <span className="theory-errors">{errors} error{errors > 1 ? "s" : ""}</span>}
      </h2>
      <Quantities items={theory.items} goTo={goTo} />
      {theory.items.map((item, k) => {
        switch (item.kind) {
          case "law": return <Law key={k} item={item} goTo={goTo} />;
          case "def": return <Def key={k} item={item} goTo={goTo} />;
          case "derive": return <Derive key={k} item={item} goTo={goTo} />;
          case "compute": return <Compute key={k} item={item} goTo={goTo} />;
          case "simulate": return <Simulate key={k} item={item} goTo={goTo} />;
          case "diagram": return <Diagram key={k} item={item} goTo={goTo} />;
          case "groups": return <Groups key={k} item={item} goTo={goTo} />;
          case "error": return <ErrorCard key={k} item={item} goTo={goTo} />;
          default: return null;
        }
      })}
    </section>
  );
}

export function Results({ report, goTo }: { report: Report; goTo: GoTo }) {
  // Errors outside any theory: syntax errors stop everything else.
  const loose = report.errors.filter((e) => e.theory === null);
  return (
    <div className="results">
      {report.fatal && (
        <article className="card card-error">
          <header className="card-head"><span className="kind kind-error">landau failed</span></header>
          <pre className="fatal">{report.fatal}</pre>
        </article>
      )}
      {loose.map((e, k) => <ErrorCard key={k} item={e} goTo={goTo} />)}
      {report.theories.map((t) => <TheoryView key={t.name} theory={t} goTo={goTo} />)}
      {!report.fatal && !loose.length && !report.theories.length && (
        <p className="empty">Nothing to show yet. Declare a theory, or open a module.</p>
      )}
    </div>
  );
}
