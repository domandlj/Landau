// text ... end blocks render as prose: paragraphs, math, bold and italic.
import { renderToStaticMarkup } from "react-dom/server";
import { expect, test } from "vitest";
import type { Report } from "../src/report";
import { Results } from "../src/Results";
import { katexErrors } from "./katex";

const render = (content: string, theory = "Notes") => {
  const report: Report = { ok: true, errors: [], theories: [{ name: theory, items: [{ kind: "text", line: 3, content }] }] };
  let html = "";
  const errors = katexErrors(() => (html = renderToStaticMarkup(<Results report={report} goTo={() => {}} />)));
  expect(errors).toEqual([]);
  return html;
};

test("blank lines separate paragraphs", () => {
  expect(render("one\nstill one\n\ntwo").match(/<p>/g)).toHaveLength(2);
});

test("$...$ is inline math and $$...$$ display math", () => {
  const html = render("speed $v_0$ and\n$$E = m c^2$$");
  expect(html).toContain('class="tex"');
  expect(html).toContain("tex tex-display");
});

test("**bold** and *italic*, but not inside math", () => {
  const html = render("**strong** and *soft*, $a*b*c$");
  expect(html).toContain("<strong>strong</strong>");
  expect(html).toContain("<em>soft</em>");
  expect(html.match(/<em>/g)).toHaveLength(1);
});

test("\\$ is a dollar sign", () => {
  const html = render("costs \\$5, not $x$");
  expect(html).toContain("costs $5, not ");
});

test("text before any theory is shown without a Main heading", () => {
  expect(render("a preface", "Main")).not.toContain("theory-kw");
  expect(render("a note")).toContain("theory-kw");
});

test("an empty block shows nothing", () => {
  expect(render("", "Notes")).not.toContain("prose");
});

test("![caption](src) on its own line is a figure with a caption", () => {
  const html = render("Before.\n![the *throw*, $v_0$](media/projectile.gif)\nAfter.");
  expect(html).toMatch(/<img src="[^"]*projectile[^"]*\.gif"/);
  expect(html).toContain("<figcaption>the <em>throw</em>, ");
  expect(html.match(/<p>/g)).toHaveLength(2);
});

test("videos play in place and YouTube links become a player", () => {
  expect(render("![](https://example.org/drop.mp4)")).toContain('<video src="https://example.org/drop.mp4"');
  expect(render("![](https://www.youtube.com/watch?v=dQw4w9WgXcQ)")).toContain(
    'src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"',
  );
  expect(render("![](https://youtu.be/dQw4w9WgXcQ)")).toContain("youtube-nocookie.com/embed/dQw4w9WgXcQ");
  expect(render("![](https://vimeo.com/76979871)")).toContain("player.vimeo.com/video/76979871");
});

test("a file that is not in modules/ says where to put it", () => {
  const html = render("![](media/nowhere.png)");
  expect(html).toContain("figure-missing");
  expect(html).not.toContain("<img");
});

test("an image in the middle of a line stays text", () => {
  expect(render("see ![x](media/projectile.gif) here")).not.toContain("<img");
});

test("text outside theories shows where it was written, between theories", () => {
  const report: Report = {
    ok: true,
    errors: [],
    theories: [
      { name: "Main", items: [{ kind: "text", line: 1, content: "FIRST" }, { kind: "text", line: 20, content: "LAST" }] },
      { name: "Middle", items: [{ kind: "text", line: 10, content: "MIDDLE" }] },
    ],
  };
  const html = renderToStaticMarkup(<Results report={report} goTo={() => {}} />);
  const at = (s: string) => html.indexOf(s);
  expect(at("FIRST")).toBeLessThan(at("MIDDLE"));
  expect(at("MIDDLE")).toBeLessThan(at("LAST"));
});
