import { useEffect, useMemo, useRef, useState } from "react";
import { HELP, type HelpEntry, type HelpSection } from "./help";
import { Tex } from "./Results";

// `code`, $math$ and *emphasis* inside help text.
function Rich({ text }: { text: string }) {
  const parts = text.split(/(`[^`]+`|\$[^$]+\$|\*[^*]+\*)/g);
  return (
    <>
      {parts.map((p, i) =>
        p.startsWith("`") ? (
          <code key={i}>{p.slice(1, -1)}</code>
        ) : p.startsWith("$") ? (
          <Tex key={i} latex={p.slice(1, -1)} />
        ) : p.startsWith("*") ? (
          <em key={i}>{p.slice(1, -1)}</em>
        ) : (
          <span key={i}>{p}</span>
        ),
      )}
    </>
  );
}

function Snippet({ source, label, onInsert }: { source: string; label: string; onInsert(text: string): void }) {
  return (
    <div className="snippet">
      <pre>{source}</pre>
      <button className="snippet-insert" onClick={() => onInsert(source)} title="Insert at the cursor in the editor">
        {label}
      </button>
    </div>
  );
}

function Entry({ entry, onInsert }: { entry: HelpEntry; onInsert(text: string): void }) {
  return (
    <div className="help-entry">
      <div className="help-syntax">
        <code>{entry.syntax}</code>
        {entry.tex && (
          <div className="help-tex">
            <Tex latex={entry.tex} />
          </div>
        )}
      </div>
      <div className="help-text">
        <Rich text={entry.text} />
        {entry.example && <Snippet source={entry.example} label="Insert" onInsert={onInsert} />}
      </div>
    </div>
  );
}

const matches = (q: string, ...texts: (string | undefined)[]) =>
  texts.some((t) => t !== undefined && t.toLowerCase().includes(q));

function filter(sections: HelpSection[], query: string): HelpSection[] {
  const q = query.trim().toLowerCase();
  if (!q) return sections;
  return sections.flatMap((s) => {
    if (matches(q, s.title, s.intro)) return [s];
    const entries = (s.entries ?? []).filter((e) => matches(q, e.syntax, e.text, e.tex, e.example));
    return entries.length ? [{ ...s, intro: undefined, tryIt: undefined, entries }] : [];
  });
}

export function Help({
  onClose,
  onInsert,
  initialSection,
}: {
  onClose(): void;
  onInsert(text: string): void;
  initialSection?: string;
}) {
  const [query, setQuery] = useState("");
  const search = useRef<HTMLInputElement>(null);
  const body = useRef<HTMLDivElement>(null);
  const sections = useMemo(() => filter(HELP, query), [query]);

  useEffect(() => {
    if (initialSection) body.current?.querySelector(`#help-${initialSection}`)?.scrollIntoView();
  }, [initialSection]);

  useEffect(() => {
    search.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const jump = (id: string) => body.current?.querySelector(`#help-${id}`)?.scrollIntoView({ behavior: "smooth" });

  return (
    <div className="help-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <aside className="help" role="dialog" aria-modal="true" aria-labelledby="help-title">
        <header className="help-head">
          <h2 id="help-title">Landau reference</h2>
          <input
            ref={search}
            className="help-search"
            type="search"
            placeholder="Search: solve, curl, vector…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search the reference"
          />
          <button className="help-close" onClick={onClose} aria-label="Close help" title="Close (Esc)">
            ×
          </button>
        </header>
        <div className="help-main">
          <nav className="help-nav" aria-label="Sections">
            {sections.map((s) => (
              <button key={s.id} onClick={() => jump(s.id)}>
                {s.title}
              </button>
            ))}
          </nav>
          <div className="help-body" ref={body}>
            {sections.length === 0 && <p className="empty">Nothing matches “{query}”.</p>}
            {sections.map((s) => (
              <section key={s.id} id={`help-${s.id}`} className="help-section">
                <h3>{s.title}</h3>
                {s.intro && (
                  <p className="help-intro">
                    <Rich text={s.intro} />
                  </p>
                )}
                {s.entries?.map((e, i) => <Entry key={i} entry={e} onInsert={onInsert} />)}
                {s.tryIt && (
                  <div className="help-try">
                    <span className="meta-label">Try it</span>
                    <Snippet source={s.tryIt} label="Insert into editor" onInsert={onInsert} />
                  </div>
                )}
              </section>
            ))}
          </div>
        </div>
      </aside>
    </div>
  );
}
