// \name completions: every letter they insert is one landau renders back as
// \name, and the completion starts at the backslash.
import { CompletionContext } from "@codemirror/autocomplete";
import { EditorState } from "@codemirror/state";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test } from "vitest";
import type { LawItem } from "../src/report";
import { Tex } from "../src/Results";
import { SYMBOLS, symbolCompletions } from "../src/symbols";
import { katexErrors } from "./katex";
import { check, errorLines } from "./landau";

test("landau renders each letter as its command", async () => {
  const names = SYMBOLS.map(([, char]) => char);
  const r = await check(`theory S\n  dim L\n  var ${names.join(", ")} : L\n  law l: ${names.join(" + ")} = 0\nend\n`);
  expect(errorLines(r)).toEqual([]);
  const law = r.theories[0].items.find((i) => i.kind === "law");
  const latex = law?.kind === "law" ? law.eq.latex : "";
  for (const [name] of SYMBOLS) expect(latex, name).toMatch(new RegExp(`\\\\${name}(?![A-Za-z])`));
}, 120_000);

function complete(doc: string) {
  const state = EditorState.create({ doc });
  return symbolCompletions(new CompletionContext(state, doc.length, false));
}

test("completes from the backslash", () => {
  const r = complete("law l: x = \\th")!;
  expect(r.from).toBe("law l: x = ".length);
  expect(r.options.find((o) => o.label === "\\theta")?.apply).toBe("θ");
  expect(r.validFor).toBeInstanceOf(RegExp);
  expect((r.validFor as RegExp).test("\\theta")).toBe(true);
});

test("a lone backslash offers every letter", () => {
  expect(complete("var \\")!.options).toHaveLength(SYMBOLS.length);
});

test("nothing to complete without a backslash", () => {
  expect(complete("var theta")).toBeNull();
});

test("commands are unique", () => {
  expect(new Set(SYMBOLS.map(([n]) => n)).size).toBe(SYMBOLS.length);
  expect(new Set(SYMBOLS.map(([, c]) => c)).size).toBe(SYMBOLS.length);
});

// How names with subscripts are written in LaTeX (Pretty.name in lib/pretty.ml).
test("subscripts", async () => {
  const cases: [string, string][] = [
    ["x0", "x_{0}"],
    ["θ1", "\\theta _{1}"],
    ["v_max", "v_{\\mathrm{max}}"],
    ["v_θ", "v_{\\theta }"],
    ["v_θmax", "v_{\\theta \\mathrm{max}}"],
    ["a_b_c", "a_{\\mathrm{b\\_c}}"],
    ["E_kin'", "E_{\\mathrm{kin}}'"],
    ["vx", "\\mathit{vx}"],
  ];
  const names = cases.map(([n]) => n);
  const r = await check(`theory S\n  dim L\n  var ${names.join(", ")} : L\n  law l: ${names.join(" + ")} = 0\nend\n`);
  expect(errorLines(r)).toEqual([]);
  const law = r.theories[0].items.find((i) => i.kind === "law");
  expect(law?.kind === "law" && law.eq.latex).toBe(`${cases.map(([, tex]) => tex).join(" + ")} = 0`);
  expect(katexErrors(() => renderToStaticMarkup(<Tex latex={(law as LawItem).eq.latex} />))).toEqual([]);
}, 120_000);
