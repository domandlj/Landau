import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import { basicSetup } from "codemirror";
import { EditorState, Prec } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { HighlightStyle, StreamLanguage, syntaxHighlighting } from "@codemirror/language";
import { setDiagnostics, type Diagnostic } from "@codemirror/lint";
import { tags } from "@lezer/highlight";
import type { ErrorItem } from "./report";
import { symbolCompletions } from "./symbols";

const KEYWORDS = new Set([
  "theory", "end", "import", "dim", "var", "def", "law", "derive",
  "solve", "for", "subst", "into", "simplify", "unfold", "root", "component", "of", "expand", "differentiate", "by",
  "apply", "to", "integrate", "from", "with", "unit", "const", "evaluate", "in", "digits", "compute",
  "approximate", "where", "order", "limit", "as", "numerically", "near", "simulate", "points",
  "diagram", "body", "force", "toward", "accelerates", "plane", "draw", "mark", "between", "and", "groups",
]);
const ATTRIBUTES = new Set(["positive", "nonzero", "real", "complex", "vector", "position"]);
const BUILTINS = new Set([
  "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh", "tanh",
  "exp", "log", "sqrt", "abs", "conj", "pi", "im",
  "dot", "cross", "norm", "grad", "div", "curl", "lap", "diff", "vec", "integral", "at",
  "line", "loop", "surface", "volume", "inf",
]);

// Mirrors lib/lexer.mll. Identifiers may contain any non-ASCII letter (θ, ψ, ħ).
const landau = StreamLanguage.define<{ afterDecl: boolean }>({
  startState: () => ({ afterDecl: false }),
  token(stream, state) {
    if (stream.eatSpace()) return null;
    if (stream.match("--") || stream.match("#")) {
      stream.skipToEnd();
      return "comment";
    }
    if (stream.match(/^\d+(\.\d+)?/)) return "number";
    if (stream.match(/^[A-Za-z_\u0080-￿][\w'\u0080-￿]*/)) {
      const word = stream.current();
      const wasDecl = state.afterDecl;
      state.afterDecl = ["theory", "law", "derive", "def"].includes(word);
      if (KEYWORDS.has(word)) return "keyword";
      if (wasDecl) return "definition";
      if (ATTRIBUTES.has(word)) return "modifier";
      if (BUILTINS.has(word)) return "builtin";
      return "variableName";
    }
    state.afterDecl = false;
    if (stream.match(":=")) return "operator";
    stream.next();
    return /[=+\-*/^]/.test(stream.current()) ? "operator" : "punctuation";
  },
  languageData: { commentTokens: { line: "--" } },
});

const highlight = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--syn-keyword)", fontWeight: "600" },
  { tag: tags.comment, color: "var(--syn-comment)", fontStyle: "italic" },
  { tag: tags.number, color: "var(--syn-number)" },
  { tag: tags.definition(tags.variableName), color: "var(--syn-def)", fontWeight: "600" },
  { tag: tags.modifier, color: "var(--syn-attr)" },
  { tag: tags.standard(tags.variableName), color: "var(--syn-builtin)" },
  { tag: tags.operator, color: "var(--syn-op)" },
]);

const theme = EditorView.theme({
  "&": { height: "100%", fontSize: "14px", backgroundColor: "var(--editor-bg)", color: "var(--text)" },
  ".cm-scroller": { fontFamily: "var(--mono)", lineHeight: "1.6" },
  ".cm-content": { caretColor: "var(--accent)" },
  ".cm-cursor": { borderLeftColor: "var(--accent)" },
  ".cm-gutters": { backgroundColor: "var(--editor-bg)", color: "var(--muted)", border: "none" },
  ".cm-activeLine, .cm-activeLineGutter": { backgroundColor: "var(--active-line)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    backgroundColor: "var(--selection) !important",
  },
  ".cm-tooltip": { backgroundColor: "var(--surface)", border: "1px solid var(--border)", color: "var(--text)" },
  ".cm-diagnostic-error": { borderLeftColor: "var(--error)" },
  ".cm-flash": { backgroundColor: "var(--flash)", transition: "background-color 1.2s" },
});

export interface EditorHandle {
  setText(text: string): void;
  insert(text: string): void;
  goToLine(line: number): void;
}

interface Props {
  initial: string;
  errors: ErrorItem[];
  onChange(text: string): void;
  onRun(): void;
}

// Turn landau's line (1-based) and optional column (0-based) into a range.
function toDiagnostic(state: EditorState, e: ErrorItem): Diagnostic {
  const line = state.doc.line(Math.min(Math.max(e.line, 1), state.doc.lines));
  let from = line.from + (line.text.length - line.text.trimStart().length);
  let to = line.to;
  if (e.col !== null) {
    from = Math.min(line.from + e.col, line.to);
    const rest = line.text.slice(from - line.from);
    to = from + Math.max(1, rest.match(/^\S+/)?.[0].length ?? 1);
  }
  return { from, to: Math.max(to, from), severity: "error", message: e.message };
}

export const Editor = forwardRef<EditorHandle, Props>(function Editor({ initial, errors, onChange, onRun }, ref) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView>();
  const callbacks = useRef({ onChange, onRun });
  callbacks.current = { onChange, onRun };

  useEffect(() => {
    const v = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: initial,
        extensions: [
          Prec.highest(
            keymap.of([{ key: "Mod-Enter", run: () => (callbacks.current.onRun(), true) }]),
          ),
          basicSetup,
          landau,
          landau.data.of({ autocomplete: symbolCompletions }),
          syntaxHighlighting(highlight),
          theme,
          EditorView.updateListener.of((u) => {
            if (u.docChanged) callbacks.current.onChange(u.state.doc.toString());
          }),
        ],
      }),
    });
    view.current = v;
    return () => v.destroy();
    // The editor owns its document after creation; `initial` only seeds it.
  }, []);

  useEffect(() => {
    const v = view.current;
    if (v) v.dispatch(setDiagnostics(v.state, errors.map((e) => toDiagnostic(v.state, e))));
  }, [errors]);

  useImperativeHandle(ref, () => ({
    insert(text) {
      // on a line of its own, at the cursor
      const v = view.current!;
      const at = v.state.doc.lineAt(v.state.selection.main.head).to;
      const insert = (at > 0 ? "\n" : "") + text.replace(/\n$/, "") + "\n";
      v.dispatch({ changes: { from: at, insert }, selection: { anchor: at + insert.length } });
      v.dispatch({ effects: EditorView.scrollIntoView(at, { y: "center" }) });
      v.focus();
    },
    setText(text) {
      const v = view.current!;
      v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: text }, selection: { anchor: 0 } });
      v.scrollDOM.scrollTop = 0;
    },
    goToLine(n) {
      const v = view.current!;
      const line = v.state.doc.line(Math.min(Math.max(n, 1), v.state.doc.lines));
      v.dispatch({ selection: { anchor: line.from }, effects: EditorView.scrollIntoView(line.from, { y: "center" }) });
      v.focus();
      const el = v.domAtPos(line.from).node;
      const lineEl = (el instanceof HTMLElement ? el : el.parentElement)?.closest(".cm-line");
      if (lineEl) {
        lineEl.classList.add("cm-flash");
        setTimeout(() => lineEl.classList.remove("cm-flash"), 1200);
      }
    },
  }));

  return <div className="editor" ref={host} />;
});
