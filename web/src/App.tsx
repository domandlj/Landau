import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Editor, type EditorHandle } from "./Editor";
import { Help } from "./Help";
import { DerivStyleContext, DimStyleContext, type DerivStyle, type DimMode, type DimStyle } from "./dimStyle";
import { Results } from "./Results";
import { Settings } from "./Settings";
import { applyTheme, loadTheme, type Theme } from "./theme";
import {
  checkSource,
  deleteModule,
  fetchModules,
  importersOf,
  MODULE_NAME,
  saveModule,
  type Module,
  type Report,
} from "./report";

const DRAFT_KEY = "landau.draft";
const MODULE_KEY = "landau.module"; // the name of the module being edited
const DIM_STYLE_KEY = "landau.dimStyle";
const DIM_MODE_KEY = "landau.dimMode";
const DERIV_STYLE_KEY = "landau.derivStyle";

function loadSetting<T extends string>(key: string, values: readonly T[]): T {
  try {
    const v = localStorage.getItem(key);
    return values.find((x) => x === v) ?? values[0];
  } catch {
    return values[0];
  }
}

function saveSetting(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // storage may be unavailable; the choice lasts for this visit
  }
}
const DEBOUNCE_MS = 700;

function loadDraft(): string | null {
  try {
    return localStorage.getItem(DRAFT_KEY);
  } catch {
    return null;
  }
}

function saveDraft(text: string) {
  try {
    localStorage.setItem(DRAFT_KEY, text);
  } catch {
    // storage may be unavailable (private window); the draft just isn't kept
  }
}

type Status = { state: "idle" } | { state: "checking" } | { state: "failed"; message: string };

export function App() {
  const editor = useRef<EditorHandle>(null);
  const [initial] = useState(() => loadDraft());
  const source = useRef(initial ?? "");
  const [modules, setModules] = useState<Module[]>([]);
  // The module being edited (null for a new, unsaved one), and its text as
  // last opened or saved, to tell whether there are unsaved changes.
  const [current, setCurrent] = useState<string | null>(() => {
    try {
      return localStorage.getItem(MODULE_KEY);
    } catch {
      return null;
    }
  });
  const currentRef = useRef(current);
  const saved = useRef<string | null>(null);
  const [dirty, setDirty] = useState(false);
  const dirtyRef = useRef(dirty);
  dirtyRef.current = dirty;
  const [saveAs, setSaveAs] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [report, setReport] = useState<Report | null>(null);
  const [status, setStatus] = useState<Status>({ state: "idle" });
  const [dimStyle, setDimStyle] = useState<DimStyle>(() => loadSetting(DIM_STYLE_KEY, ["fraction", "powers"] as const));
  const [dimMode, setDimMode] = useState<DimMode>(() => loadSetting(DIM_MODE_KEY, ["dims", "units"] as const));
  const chooseDimStyle = (style: DimStyle) => {
    setDimStyle(style);
    saveSetting(DIM_STYLE_KEY, style);
  };
  const chooseDimMode = (mode: DimMode) => {
    setDimMode(mode);
    saveSetting(DIM_MODE_KEY, mode);
  };
  const [derivStyle, setDerivStyle] = useState<DerivStyle>(() =>
    loadSetting(DERIV_STYLE_KEY, ["leibniz", "newton", "lagrange"] as const),
  );
  const chooseDerivStyle = (style: DerivStyle) => {
    setDerivStyle(style);
    saveSetting(DERIV_STYLE_KEY, style);
  };
  const [theme, setTheme] = useState<Theme>(loadTheme);
  const chooseTheme = (next: Theme) => {
    applyTheme(next);
    setTheme(next);
  };
  // #help opens the reference; #help/integrals opens it at that section
  const [helpOpen, setHelpOpen] = useState(() => location.hash.startsWith("#help"));
  const helpButton = useRef<HTMLButtonElement>(null);
  const inflight = useRef<AbortController | null>(null);
  const timer = useRef<number>();

  const run = useCallback(async () => {
    window.clearTimeout(timer.current);
    inflight.current?.abort();
    const ctrl = new AbortController();
    inflight.current = ctrl;
    setStatus({ state: "checking" });
    try {
      const r = await checkSource(source.current, currentRef.current, ctrl.signal);
      if (ctrl.signal.aborted) return;
      setReport(r);
      setStatus({ state: "idle" });
    } catch (e) {
      if (ctrl.signal.aborted) return;
      setStatus({ state: "failed", message: e instanceof Error ? e.message : String(e) });
    }
  }, []);

  const onChange = useCallback(
    (text: string) => {
      source.current = text;
      saveDraft(text);
      setDirty(text !== saved.current);
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(run, DEBOUNCE_MS);
    },
    [run],
  );

  const setModule = useCallback((name: string | null, text: string | null) => {
    currentRef.current = name;
    setCurrent(name);
    saved.current = text;
    setDirty(text === null || source.current !== text);
    try {
      if (name === null) localStorage.removeItem(MODULE_KEY);
      else localStorage.setItem(MODULE_KEY, name);
    } catch {
      // storage may be unavailable
    }
  }, []);

  const openModule = useCallback(
    (m: Module | null) => {
      if (dirtyRef.current && !window.confirm(`Discard the unsaved changes${currentRef.current ? ` to ${currentRef.current}` : ""}?`)) {
        return false;
      }
      const text = m ? m.source : "theory New\n  import SI\n\nend\n";
      source.current = text;
      setModule(m ? m.name : null, m ? m.source : null);
      editor.current?.setText(text);
      return true;
    },
    [setModule],
  );
  const save = useCallback(
    async (name: string) => {
      setSaveError(null);
      try {
        await saveModule(name, source.current);
        setModule(name, source.current);
        setSaveAs(false);
        setModules(await fetchModules());
        run();
      } catch (e) {
        setSaveError(e instanceof Error ? e.message : String(e));
      }
    },
    [run, setModule],
  );

  // The editor keeps the text, now as an unsaved, untitled module.
  const remove = useCallback(async (name: string) => {
    try {
      const trashed = await deleteModule(name);
      setDeleting(false);
      setModule(null, null);
      setModules(await fetchModules());
      setNotice(`${name}.lan was moved to ${trashed}`);
    } catch (e) {
      setDeleting(false);
      setSaveError(e instanceof Error ? e.message : String(e));
    }
  }, [setModule]);

  useEffect(() => {
    fetchModules()
      .then((ms) => {
        setModules(ms);
        // `#maxwell` in the URL opens that module; a first visit starts from projectile
        const linked = ms.find((m) => m.name === decodeURIComponent(location.hash.slice(1)));
        const open = (m: Module) => {
          source.current = m.source;
          setModule(m.name, m.source);
          editor.current?.setText(m.source);
        };
        if (linked) open(linked);
        else if (initial === null) {
          const first = ms.find((m) => m.name === "projectile") ?? ms[0];
          if (first) open(first);
        } else {
          // the draft from last time: unsaved if it differs from its module
          const m = ms.find((x) => x.name === currentRef.current);
          setModule(m ? m.name : null, m ? m.source : null);
          run();
        }
      })
      .catch((e) => setStatus({ state: "failed", message: String(e) }));
  }, [initial, run, setModule]);

  const goTo = useCallback((line: number) => editor.current?.goToLine(line), []);

  const closeHelp = useCallback(() => {
    setHelpOpen(false);
    helpButton.current?.focus();
  }, []);
  const insertFromHelp = useCallback((text: string) => {
    setHelpOpen(false);
    editor.current?.insert(text);
  }, []);

  // F1 anywhere, or ? when not typing, opens the reference; Ctrl+S saves
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        if (currentRef.current) save(currentRef.current);
        else setSaveAs(true);
        return;
      }
      const typing = e.target instanceof HTMLElement && (e.target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName));
      if (e.key === "F1" || (e.key === "?" && !typing)) {
        e.preventDefault();
        setHelpOpen(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [save]);

  // Leaving the page with unsaved changes asks first.
  useEffect(() => {
    const onLeave = (e: BeforeUnloadEvent) => {
      if (dirtyRef.current) e.preventDefault();
    };
    window.addEventListener("beforeunload", onLeave);
    return () => window.removeEventListener("beforeunload", onLeave);
  }, []);
  const errorCount = report ? report.errors.length + (report.fatal ? 1 : 0) : 0;

  return (
    <div className="app">
      <header className="topbar">
        <h1>Landau</h1>
        <span className="tagline">dimension-checked physics</span>
        <label className="examples">
          <select
            aria-label="Modules"
            value=""
            onChange={(e) => {
              if (e.target.value === "\u0000new") openModule(null);
              else {
                const m = modules.find((x) => x.name === e.target.value);
                if (m) openModule(m);
              }
            }}
          >
            <option value="" disabled>
              Modules…
            </option>
            <option value={"\u0000new"}>+ New module</option>
            {modules.map((m) => (
              <option key={m.name} value={m.name}>
                {m.name}
              </option>
            ))}
          </select>
        </label>
        <span className={dirty ? "module-name dirty" : "module-name"} title={dirty ? "unsaved changes" : "saved"}>
          {current ? `${current}.lan` : "untitled"}
          {dirty && <span aria-label="unsaved changes"> ●</span>}
        </span>
        <button
          className="save"
          onClick={() => (current ? save(current) : setSaveAs(true))}
          title={current ? `Save to modules/${current}.lan (Ctrl+S)` : "Save as a module (Ctrl+S)"}
        >
          Save
        </button>
        <button className="save" onClick={() => setSaveAs(true)} title="Save under another name">
          Save as…
        </button>
        {current && modules.some((m) => m.name === current) && (
          <button className="save danger" onClick={() => setDeleting(true)} title={`Delete modules/${current}.lan`}>
            Delete
          </button>
        )}
        <div className="spacer" />
        <StatusPill status={status} report={report} errors={errorCount} />
        <Settings
          values={{ dimMode, dimStyle, derivStyle, theme }}
          set={{ setDimMode: chooseDimMode, setDimStyle: chooseDimStyle, setDerivStyle: chooseDerivStyle, setTheme: chooseTheme }}
        />
        <button
          ref={helpButton}
          className="help-button"
          onClick={() => setHelpOpen(true)}
          aria-label="Help"
          title="Reference: syntax, steps and functions (F1)"
        >
          ?
        </button>
        <button className="run" onClick={run} title="Check now (Ctrl+Enter)">
          Check <kbd>Ctrl ↵</kbd>
        </button>
      </header>
      <main className="panes">
        <section className="pane pane-editor" aria-label="Source">
          <Editor ref={editor} initial={initial ?? ""} errors={report?.errors ?? []} onChange={onChange} onRun={run} />
        </section>
        <section className={status.state === "checking" ? "pane pane-results stale" : "pane pane-results"} aria-label="Results">
          {status.state === "failed" && <div className="banner">Could not reach the checker: {status.message}</div>}
          {report && (
            <DimStyleContext.Provider value={{ style: dimStyle, mode: dimMode }}>
              <DerivStyleContext.Provider value={derivStyle}>
                <Results report={report} goTo={goTo} />
              </DerivStyleContext.Provider>
            </DimStyleContext.Provider>
          )}
        </section>
      </main>
      {saveError && !saveAs && (
        <div className="toast" role="alert" onClick={() => setSaveError(null)}>
          {saveError}
        </div>
      )}
      {notice && (
        <div className="toast toast-info" role="status" onClick={() => setNotice(null)}>
          {notice}
        </div>
      )}
      {deleting && current && (
        <DeleteDialog
          name={current}
          importers={importersOf(
            current,
            [...(modules.find((m) => m.name === current)?.source ?? "").matchAll(/^\s*theory\s+(\w+)/gmu)].map((m) => m[1]),
            modules,
          )}
          onDelete={() => remove(current)}
          onCancel={() => setDeleting(false)}
        />
      )}
      {saveAs && (
        <SaveDialog
          initial={current ?? ""}
          existing={modules.map((m) => m.name)}
          error={saveError}
          onSave={save}
          onCancel={() => {
            setSaveAs(false);
            setSaveError(null);
          }}
        />
      )}
      {helpOpen && (
        <Help onClose={closeHelp} onInsert={insertFromHelp} initialSection={location.hash.split("/")[1]} />
      )}
    </div>
  );
}

// Asks for a module name; saving over another module needs a second click.
function SaveDialog({
  initial,
  existing,
  error,
  onSave,
  onCancel,
}: {
  initial: string;
  existing: string[];
  error: string | null;
  onSave(name: string): void;
  onCancel(): void;
}) {
  const [name, setName] = useState(initial);
  const [confirmed, setConfirmed] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    input.current?.select();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onCancel();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);
  const valid = MODULE_NAME.test(name);
  const overwrite = valid && existing.includes(name) && name !== initial;
  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    if (overwrite && confirmed !== name) {
      setConfirmed(name);
      return;
    }
    onSave(name);
  };
  return (
    <div className="dialog-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onCancel()}>
      <form className="dialog" onSubmit={submit} role="dialog" aria-modal="true" aria-labelledby="save-title">
        <h2 id="save-title">Save as a module</h2>
        <label className="dialog-field">
          <span>Name</span>
          <input ref={input} value={name} onChange={(e) => setName(e.target.value)} spellCheck={false} autoComplete="off" />
          <span className="dialog-suffix">.lan</span>
        </label>
        <p className="dialog-note">
          {!valid && name !== ""
            ? "Use letters, digits and _, starting with a letter: it is what `import` will name."
            : overwrite
              ? confirmed === name
                ? `Click Save again to replace modules/${name}.lan.`
                : `modules/${name}.lan already exists.`
              : `Other files can then use it with import ${name || "name"}.`}
        </p>
        {error && <p className="dialog-error">{error}</p>}
        <div className="dialog-actions">
          <button type="button" onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="run" disabled={!valid}>
            {overwrite && confirmed === name ? "Replace" : "Save"}
          </button>
        </div>
      </form>
    </div>
  );
}

function DeleteDialog({
  name,
  importers,
  onDelete,
  onCancel,
}: {
  name: string;
  importers: string[];
  onDelete(): void;
  onCancel(): void;
}) {
  const cancel = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    cancel.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onCancel();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);
  return (
    <div className="dialog-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onCancel()}>
      <div className="dialog" role="alertdialog" aria-modal="true" aria-labelledby="delete-title">
        <h2 id="delete-title">Delete {name}.lan?</h2>
        {importers.length > 0 && (
          <p className="dialog-error">
            {importers.map((m) => `${m}.lan`).join(", ")} {importers.length === 1 ? "imports" : "import"} it and will stop
            checking.
          </p>
        )}
        <p className="dialog-note">
          The file moves to <code>modules/.trash/</code>, where you can get it back. The editor keeps the text as an
          unsaved module.
        </p>
        <div className="dialog-actions">
          <button type="button" ref={cancel} onClick={onCancel}>
            Cancel
          </button>
          <button type="button" className="run danger" onClick={onDelete}>
            Delete
          </button>
        </div>
      </div>
    </div>
  );
}

function StatusPill({ status, report, errors }: { status: Status; report: Report | null; errors: number }) {
  if (status.state === "checking") return <span className="pill pill-busy">checking…</span>;
  if (status.state === "failed") return <span className="pill pill-bad">offline</span>;
  if (!report) return null;
  if (errors === 0) return <span className="pill pill-ok">✓ dimensions consistent</span>;
  return <span className="pill pill-bad">{errors} error{errors > 1 ? "s" : ""}</span>;
}
