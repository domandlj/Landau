// The in-app reference: its formulas render, and its programs check.
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test } from "vitest";
import { HELP } from "../src/help";
import { Help } from "../src/Help";
import { katexErrors } from "./katex";
import { check, errorLines } from "./landau";

test("every formula in the reference renders", () => {
  let html = "";
  expect(katexErrors(() => (html = renderToStaticMarkup(<Help onClose={() => {}} onInsert={() => {}} />)))).toEqual([]);
  // every section is shown, so none of them was skipped
  for (const s of HELP) expect(html).toContain(`id="help-${s.id}"`);
});

// $...$ in help text is cut out by a regex; an odd number of $ would show raw
// LaTeX and swallow the text around it.
test.each(HELP.map((s) => [s.id, s] as const))("section %s pairs its $ signs", (_, s) => {
  for (const text of [s.intro, ...(s.entries ?? []).map((e) => e.text)]) {
    if (text) expect((text.match(/\$/g) ?? []).length % 2, text).toBe(0);
  }
});

const programs = HELP.filter((s) => s.tryIt).map((s) => [s.id, s.tryIt!] as const);

test("most sections have a program to try", () => {
  expect(programs.length).toBeGreaterThan(5);
});

// "Try it" promises a complete program that checks cleanly.
test.each(programs)("the %s program checks", async (_, source) => {
  const r = await check(source);
  expect(errorLines(r)).toEqual([]);
  expect(r.ok).toBe(true);
  expect(r.theories.length).toBeGreaterThan(0);
}, 120_000);

// In an ordinary string, "$\\pi$" loses its backslash ("\p" is just "p"), and
// what is left still renders, as the word pi. So read the source: outside
// raw strings (r`...`), a backslash before a letter must be doubled.
test("help text doubles its LaTeX backslashes", () => {
  const source = readFileSync(new URL("../src/help.ts", import.meta.url), "utf8").replace(/r`[^`]*`/g, "");
  const strings = source.match(/"(?:[^"\\\n]|\\.)*"/g) ?? [];
  const lost = strings.filter((s) => /(?<!\\)\\(?!n)[A-Za-z]/.test(s));
  expect(lost).toEqual([]);
});
