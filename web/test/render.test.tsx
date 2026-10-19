// Every module's report renders: each formula the results panel shows goes
// through KaTeX without an error, in every dimension style and mode.
import { renderToStaticMarkup } from "react-dom/server";
import { beforeAll, describe, expect, test } from "vitest";
import { DerivStyleContext, DimStyleContext, type DerivStyle, type DimMode, type DimStyle } from "../src/dimStyle";
import type { Report } from "../src/report";
import { Results, Tex } from "../src/Results";
import { katexErrors } from "./katex";
import { check, errorLines, MODULES, modules } from "./landau";

const MODES: [DimStyle, DimMode][] = [
  ["fraction", "dims"],
  ["powers", "dims"],
  ["fraction", "units"],
  ["powers", "units"],
];

const reports = new Map<string, Report>();

beforeAll(async () => {
  await Promise.all(
    modules.map(async (m) => reports.set(m.name, await check(m.source, `${MODULES}/${m.name}.lan`))),
  );
}, 300_000);

describe.each(modules.map((m) => m.name))("module %s", (name) => {
  test("produces a report", () => {
    const r = reports.get(name)!;
    expect(r.fatal).toBeUndefined();
    expect(r.theories.length).toBeGreaterThan(0);
  });

  test.each(MODES)("renders with dimensions as %s, %s", (style, mode) => {
    let html = "";
    const errors = katexErrors(() => {
      html = renderToStaticMarkup(
        <DimStyleContext.Provider value={{ style, mode }}>
          <Results report={reports.get(name)!} goTo={() => {}} />
        </DimStyleContext.Provider>,
      );
    });
    expect(html).toContain('class="katex"');
    expect(errors).toEqual([]);
  });

  test.each(["leibniz", "newton", "lagrange"] as DerivStyle[])("renders with derivatives in %s notation", (deriv) => {
    const errors = katexErrors(() =>
      renderToStaticMarkup(
        <DerivStyleContext.Provider value={deriv}>
          <Results report={reports.get(name)!} goTo={() => {}} />
        </DerivStyleContext.Provider>,
      ),
    );
    expect(errors).toEqual([]);
  });

  // The steps are collapsed in the results, so render them as the open list does.
  test("renders every derivation step", () => {
    const steps = reports.get(name)!.theories.flatMap((t) => t.items).flatMap((i) => (i.kind === "derive" ? i.steps : []));
    expect(katexErrors(() => steps.forEach((s) => renderToStaticMarkup(<Tex latex={s.eq.latex} />)))).toEqual([]);
  });
});

// errors.lan shows error messages on purpose; the others should check cleanly,
// or a broken module would only be noticed by opening it.
test.each(modules.filter((m) => m.name !== "errors").map((m) => m.name))("module %s has no errors", (name) => {
  expect(errorLines(reports.get(name)!)).toEqual([]);
});

// What each notation shows, as the characters in KaTeX's MathML.
test.each([
  ["leibniz", "a=d2xdt2+dθdy"],
  ["newton", "a=x¨+dθdy"],
  ["lagrange", "a=x′′+θ′"],
] as [DerivStyle, string][])("derivatives in %s notation", async (deriv, shown) => {
  const r = await check(
    "theory D\n  dim L, T\n  var t : T\n  var y : L\n  var x(t) : L\n  var θ(y) : 1\n  var a : L/T^2\n" +
      "  law l: a = diff(diff(x, t), t) + diff(θ, y)*x*y/t^2\nend\n",
  );
  expect(errorLines(r)).toEqual([]);
  const law = r.theories[0].items.find((i) => i.kind === "law");
  const html = renderToStaticMarkup(
    <DerivStyleContext.Provider value={deriv}>
      <Tex latex={law?.kind === "law" ? law.eq.latex : ""} />
    </DerivStyleContext.Provider>,
  );
  const math = html.match(/<semantics>(.*?)<annotation/)![1].replace(/<[^>]+>/g, "");
  expect(math.startsWith(shown), math).toBe(true);
}, 120_000);
