import type { CompletionContext, CompletionResult } from "@codemirror/autocomplete";

// Letters a name can use, by their LaTeX command: typing \theta in the editor
// inserts θ. Mirrors `greek` in lib/pretty.ml, which turns them back into
// LaTeX for the results; test/symbols.test.tsx checks the two agree.
export const SYMBOLS: [string, string][] = [
  ["alpha", "α"], ["beta", "β"], ["gamma", "γ"], ["delta", "δ"], ["epsilon", "ϵ"], ["varepsilon", "ε"],
  ["zeta", "ζ"], ["eta", "η"], ["theta", "θ"], ["vartheta", "ϑ"], ["iota", "ι"], ["kappa", "κ"],
  ["lambda", "λ"], ["mu", "μ"], ["nu", "ν"], ["xi", "ξ"], ["pi", "π"], ["rho", "ρ"], ["varrho", "ϱ"],
  ["sigma", "σ"], ["varsigma", "ς"], ["tau", "τ"], ["upsilon", "υ"], ["phi", "ϕ"], ["varphi", "φ"],
  ["chi", "χ"], ["psi", "ψ"], ["omega", "ω"],
  ["Gamma", "Γ"], ["Delta", "Δ"], ["Theta", "Θ"], ["Lambda", "Λ"], ["Xi", "Ξ"], ["Pi", "Π"],
  ["Sigma", "Σ"], ["Phi", "Φ"], ["Psi", "Ψ"], ["Omega", "Ω"],
  ["hbar", "ħ"], ["ell", "ℓ"],
];

const OPTIONS = SYMBOLS.map(([name, char]) => ({ label: `\\${name}`, detail: char, apply: char, type: "constant" }));

/** Completes \name to its letter, from the moment \ is typed. */
export function symbolCompletions(context: CompletionContext): CompletionResult | null {
  const word = context.matchBefore(/\\[A-Za-z]*/);
  if (!word) return null;
  return { from: word.from, options: OPTIONS, validFor: /^\\[A-Za-z]*$/ };
}
