import { useEffect, useMemo, useRef, useState } from "react";
import type { SimSeries, SimulateItem } from "./report";

// Line charts for a simulation: small multiples, one panel per unit, at most
// three series in a panel (the palette is validated for three), a crosshair
// with one tooltip for every series, direct labels at the line ends, and a
// table view.

const HEIGHT = 190;
const PAD = { top: 12, right: 64, bottom: 30, left: 56 };
const MAX_PER_PANEL = 3;

// 1-2-5 ticks covering [lo, hi]
function ticks(lo: number, hi: number, count = 5): number[] {
  if (!(hi > lo)) return [lo];
  const raw = (hi - lo) / count;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? raw;
  const out: number[] = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi + step * 1e-9; v += step) out.push(Math.abs(v) < step * 1e-9 ? 0 : v);
  return out;
}

// 0.25, 1500, and 1.5e11 rather than 1.50e+11
const fmt = (v: number) => {
  if (v === 0) return "0";
  const a = Math.abs(v);
  if (a >= 1e5 || a < 1e-3) {
    const [m, e] = v.toExponential(3).split("e");
    return `${+m}e${+e}`;
  }
  return +v.toPrecision(4) + "";
};

const unitLabel = (s: SimSeries) => (s.unit.text === "1" ? "" : s.unit.text);

function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(600);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setWidth(Math.max(260, e.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, width] as const;
}

function Panel({ t, series, slots }: { t: SimSeries; series: SimSeries[]; slots: number[] }) {
  const [ref, width] = useWidth();
  const [hover, setHover] = useState<number | null>(null);
  const times = t.values as number[];
  const w = width - PAD.left - PAD.right;
  const h = HEIGHT - PAD.top - PAD.bottom;

  const all = series.flatMap((s) => s.values.filter((v): v is number => v !== null && Number.isFinite(v)));
  let lo = Math.min(...all), hi = Math.max(...all);
  if (!(hi > lo)) { lo -= 1; hi += 1; }
  const yt = ticks(lo, hi);
  lo = Math.min(lo, yt[0]);
  hi = Math.max(hi, yt[yt.length - 1]);
  const t0 = times[0], t1 = times[times.length - 1];
  const x = (v: number) => PAD.left + ((v - t0) / (t1 - t0)) * w;
  const y = (v: number) => PAD.top + (1 - (v - lo) / (hi - lo)) * h;

  const paths = series.map((s) => {
    let d = "", pen = false;
    s.values.forEach((v, i) => {
      if (v === null || !Number.isFinite(v)) { pen = false; return; }
      d += `${pen ? "L" : "M"}${x(times[i]).toFixed(1)},${y(v).toFixed(1)}`;
      pen = true;
    });
    return d;
  });

  const onMove = (e: React.PointerEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    const tv = t0 + ((e.clientX - box.left) / box.width) * (t1 - t0);
    // snap to the nearest sample
    let best = 0;
    for (let i = 1; i < times.length; i++) if (Math.abs(times[i] - tv) < Math.abs(times[best] - tv)) best = i;
    setHover(best);
  };

  const yUnit = unitLabel(series[0]);
  return (
    <div className="sim-panel" ref={ref}>
      {series.length > 1 && (
        <div className="sim-legend" aria-hidden="true">
          {series.map((s, k) => (
            <span key={s.name}>
              <i style={{ background: `var(--series-${slots[k]})` }} /> {s.name}
            </span>
          ))}
        </div>
      )}
      <svg width={width} height={HEIGHT} role="img" aria-label={`${series.map((s) => s.name).join(", ")} against ${t.name}`}>
        {yt.map((v) => (
          <g key={`y${v}`}>
            <line className="sim-grid" x1={PAD.left} x2={PAD.left + w} y1={y(v)} y2={y(v)} />
            <text className="sim-tick" x={PAD.left - 6} y={y(v)} dy="0.32em" textAnchor="end">{fmt(v)}</text>
          </g>
        ))}
        {ticks(t0, t1).map((v) => (
          <text key={`x${v}`} className="sim-tick" x={x(v)} y={PAD.top + h + 16} textAnchor="middle">{fmt(v)}</text>
        ))}
        <line className="sim-axis" x1={PAD.left} x2={PAD.left + w} y1={PAD.top + h} y2={PAD.top + h} />
        <text className="sim-axis-label" x={PAD.left + w} y={PAD.top + h + 28} textAnchor="end">
          {t.name}{unitLabel(t) && ` [${unitLabel(t)}]`}
        </text>
        {yUnit && <text className="sim-axis-label" x={4} y={PAD.top - 2}>[{yUnit}]</text>}
        {paths.map((d, k) => (
          <path key={series[k].name} d={d} className="sim-line" style={{ stroke: `var(--series-${slots[k]})` }} />
        ))}
        {/* direct labels at the line ends */}
        {series.map((s) => {
          const last = [...s.values].reverse().find((v): v is number => v !== null && Number.isFinite(v));
          return last === undefined ? null : (
            <text key={`l${s.name}`} className="sim-end-label" x={PAD.left + w + 6} y={y(last)} dy="0.32em">{s.name}</text>
          );
        })}
        {hover !== null && (
          <g>
            <line className="sim-crosshair" x1={x(times[hover])} x2={x(times[hover])} y1={PAD.top} y2={PAD.top + h} />
            {series.map((s, k) => {
              const v = s.values[hover];
              return v === null || !Number.isFinite(v) ? null : (
                <circle key={s.name} cx={x(times[hover])} cy={y(v)} r={4} className="sim-dot" style={{ fill: `var(--series-${slots[k]})` }} />
              );
            })}
          </g>
        )}
        <rect
          x={PAD.left} y={PAD.top} width={w} height={h} fill="transparent"
          onPointerMove={onMove} onPointerLeave={() => setHover(null)}
        />
      </svg>
      {hover !== null && (
        <div className="sim-tooltip" style={{ left: Math.min(x(times[hover]) + 12, width - 170), top: PAD.top }}>
          <div className="sim-tooltip-head">{t.name} = <strong>{fmt(times[hover])}</strong> {unitLabel(t)}</div>
          {series.map((s, k) => (
            <div key={s.name} className="sim-tooltip-row">
              <i style={{ background: `var(--series-${slots[k]})` }} />
              <strong>{s.values[hover] === null ? "–" : fmt(s.values[hover] as number)}</strong> {unitLabel(s)} <span>{s.name}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function Table({ t, series }: { t: SimSeries; series: SimSeries[] }) {
  const head = (s: SimSeries) => `${s.name}${unitLabel(s) ? ` [${unitLabel(s)}]` : ""}`;
  return (
    <div className="sim-table-wrap">
      <table className="sim-table">
        <thead>
          <tr>
            <th>{head(t)}</th>
            {series.map((s) => <th key={s.name}>{head(s)}</th>)}
          </tr>
        </thead>
        <tbody>
          {(t.values as number[]).map((tv, i) => (
            <tr key={i}>
              <td>{fmt(tv)}</td>
              {series.map((s) => <td key={s.name}>{s.values[i] === null ? "–" : fmt(s.values[i] as number)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function SimPlot({ item }: { item: SimulateItem }) {
  const [table, setTable] = useState(false);
  // one panel per unit, in the order the unknowns were listed; a slot (color)
  // follows the series, so it keeps its color whatever else is shown
  const panels = useMemo(() => {
    const groups: { series: SimSeries[]; slots: number[] }[] = [];
    item.series.forEach((s) => {
      const g = groups.find((p) => p.series[0].unit.text === s.unit.text && p.series.length < MAX_PER_PANEL);
      if (g) { g.series.push(s); g.slots.push(g.slots.length + 1); }
      else groups.push({ series: [s], slots: [1] });
    });
    return groups;
  }, [item.series]);
  return (
    <div className="sim">
      <div className="sim-bar">
        <button className="steps-toggle" onClick={() => setTable(!table)} aria-pressed={table}>
          {table ? "Show plots" : "Show table"}
        </button>
        <span className="meta-label">{item.t.values.length} points · {item.solver}</span>
      </div>
      {table ? <Table t={item.t} series={item.series} /> : panels.map((p, i) => <Panel key={i} t={item.t} series={p.series} slots={p.slots} />)}
    </div>
  );
}
