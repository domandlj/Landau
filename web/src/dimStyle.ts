import { createContext, useContext } from "react";
import type { DimRendered } from "./report";

/** How dimensions are written: L/T, or L T^{-1}. */
export type DimStyle = "fraction" | "powers";
/** Whether to show dimensions (M L T^{-2}) or units (N), where units are known. */
export type DimMode = "dims" | "units";

export const DimStyleContext = createContext<{ style: DimStyle; mode: DimMode }>({ style: "fraction", mode: "dims" });

/** The LaTeX of a dimension in the chosen style; in units when asked and known. */
export function useDimTex(): (d: DimRendered) => string {
  const { style, mode } = useContext(DimStyleContext);
  return (d) => {
    if (mode === "units" && d.units !== undefined) return style === "powers" ? d.units_powers! : d.units;
    return style === "powers" ? d.powers : d.latex;
  };
}

/** How derivatives are written: dx/dt, ẋ (time derivatives only) or x′. */
export type DerivStyle = "leibniz" | "newton" | "lagrange";

export const DerivStyleContext = createContext<DerivStyle>("leibniz");

// landau writes a derivative as \landauderiv{ẍ}{x''}{d²x/dt²} (see tex in
// lib/pretty.ml); each style keeps one argument. Every body names #1 to #3,
// since KaTeX counts a macro's arguments from the highest one it uses.
export const DERIV_MACROS: Record<DerivStyle, string> = {
  leibniz: "\\@secondoftwo{#1#2}{#3}",
  newton: "\\@firstoftwo{#1}{#2#3}",
  lagrange: "\\@secondoftwo{#1}{\\@firstoftwo{#2}{#3}}",
};
