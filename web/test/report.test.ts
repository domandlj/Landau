// importersOf: which modules break if a module is deleted.
import { expect, test } from "vitest";
import { importersOf, MODULE_NAME } from "../src/report";
import { modules } from "./landau";

const m = (name: string, source: string) => ({ name, source });

test("finds imports of the file and of each of its theories", () => {
  const all = [
    m("mech", "theory Newton\nend\ntheory Kinematics\nend"),
    m("a", "theory A\n  import Newton\nend"),
    m("b", "theory B\n  import Kinematics\nend"),
    m("c", "theory C\n  import Kinematics from mech\nend"),
    m("d", "import mech\n"),
    m("e", "theory E\n  import SI\nend"),
  ];
  expect(importersOf("mech", ["Newton", "Kinematics"], all)).toEqual(["a", "b", "c", "d"]);
});

test("`import X from other` is an import of other, not of X's module", () => {
  const all = [m("mech", "theory Newton\nend"), m("a", "import Newton from elsewhere\n")];
  expect(importersOf("mech", ["Newton"], all)).toEqual([]);
});

test("ignores the module itself, comments and longer names", () => {
  const all = [
    m("mech", "theory Newton\nend\ntheory N2\n  import Newton\nend"),
    m("a", "-- import Newton\ntheory A\nend"),
    m("b", "theory B\n  import NewtonII\nend"),
  ];
  expect(importersOf("mech", ["Newton", "N2"], all)).toEqual([]);
});

test("a module that defines the theory imports its own", () => {
  const all = [m("mech", "theory Newton\nend"), m("a", "theory Newton\nend\ntheory A\n  import Newton\nend")];
  expect(importersOf("mech", ["Newton"], all)).toEqual([]);
});

// The shipped modules import only their own theories and the built-in ones
// (numbers and projectile each define a Kinematics), so any one can be deleted.
test("no shipped module imports another", () => {
  for (const { name, source } of modules) {
    expect(name).toMatch(MODULE_NAME);
    const theories = [...source.matchAll(/^\s*theory\s+(\w+)/gmu)].map((t) => t[1]);
    expect(importersOf(name, theories, modules), name).toEqual([]);
  }
});
