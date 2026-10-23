import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { DerivStyle, DimMode, DimStyle } from "./dimStyle";
import type { Theme } from "./theme";

interface Option<T> {
  value: T;
  label: string;
  title: string;
}

// One setting: a label and its choices, one of them pressed.
function Choice<T extends string>({ label, value, options, onChange }: {
  label: string;
  value: T;
  options: Option<T>[];
  onChange(value: T): void;
}) {
  return (
    <>
      <span className="settings-label">{label}</span>
      <div className="segmented" role="group" aria-label={label}>
        {options.map((o) => (
          <button key={o.value} aria-pressed={value === o.value} onClick={() => onChange(o.value)} title={o.title}>
            {o.label}
          </button>
        ))}
      </div>
    </>
  );
}

export interface SettingsValues {
  dimMode: DimMode;
  dimStyle: DimStyle;
  derivStyle: DerivStyle;
  theme: Theme;
}

export interface SettingsSetters {
  setDimMode(v: DimMode): void;
  setDimStyle(v: DimStyle): void;
  setDerivStyle(v: DerivStyle): void;
  setTheme(v: Theme): void;
}

/** The ⚙ button and its panel with every display setting. */
export function Settings({ values, set }: { values: SettingsValues; set: SettingsSetters }) {
  const [open, setOpen] = useState(false);
  // the panel hangs to the left of ⚙, unless that would leave the window
  // (the header wraps on narrow screens and puts ⚙ near the left edge)
  const [toRight, setToRight] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const panel = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (open && root.current && panel.current) {
      setToRight(root.current.getBoundingClientRect().right - panel.current.offsetWidth < 16);
    }
  }, [open]);

  // close on Escape or a click anywhere else
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    const onDown = (e: MouseEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("mousedown", onDown);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("mousedown", onDown);
    };
  }, [open]);

  return (
    <div className="settings" ref={root}>
      <button
        className="help-button"
        onClick={() => setOpen(!open)}
        aria-label="Settings"
        aria-expanded={open}
        title="Settings: units, notation, theme"
      >
        ⚙
      </button>
      {open && (
        <div ref={panel} className={toRight ? "settings-panel to-right" : "settings-panel"} role="dialog" aria-label="Settings">
          <Choice
            label="Show"
            value={values.dimMode}
            onChange={set.setDimMode}
            options={[
              { value: "dims", label: "Dimensions", title: "Show dimensions: M·L/T²" },
              { value: "units", label: "Units", title: "Show units where they are declared (import SI): N, kg·m/s²" },
            ]}
          />
          <Choice
            label="Write"
            value={values.dimStyle}
            onChange={set.setDimStyle}
            options={[
              { value: "fraction", label: "L/T", title: "As fractions: L/T, M·L/T²" },
              { value: "powers", label: "L·T⁻¹", title: "With negative powers: L·T⁻¹, M·L·T⁻²" },
            ]}
          />
          <Choice
            label="Derivatives"
            value={values.derivStyle}
            onChange={set.setDerivStyle}
            options={[
              { value: "leibniz", label: "dx/dt", title: "Leibniz notation: dx/dt, d²x/dt²" },
              { value: "newton", label: "ẋ", title: "Newton's dots for time derivatives: ẋ, ẍ (others stay dx/dy)" },
              { value: "lagrange", label: "x′", title: "Lagrange's primes: x′, x″" },
            ]}
          />
          <Choice
            label="Theme"
            value={values.theme}
            onChange={set.setTheme}
            options={[
              { value: "dark", label: "Dark", title: "Dark colors" },
              { value: "light", label: "Light", title: "Light colors" },
            ]}
          />
        </div>
      )}
    </div>
  );
}
