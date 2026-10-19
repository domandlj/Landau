import { Tex } from "./Results";
import type { DiagramItem } from "./report";

// A free-body diagram as in a textbook: the body on its plane, every force as
// an arrow from the body's center, all the same length (directions, not
// sizes), labeled as vectors, and the acceleration as a dashed arrow.

const SIZE = 320;
const C = SIZE / 2;
const ARROW = 92;
const BOX = 40;

// An arc of radius r around (cx, cy) between two directions (y up), the
// short way round, and where its label goes.
function arc(cx: number, cy: number, r: number, a: [number, number], b: [number, number]) {
  const ta = Math.atan2(a[1], a[0]);
  let d = Math.atan2(b[1], b[0]) - ta;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d <= -Math.PI) d += 2 * Math.PI;
  const p = (t: number, rr: number) => [cx + rr * Math.cos(t), cy - rr * Math.sin(t)] as const;
  const [x1, y1] = p(ta, r);
  const [x2, y2] = p(ta + d, r);
  // in SVG, y points down, so counterclockwise is sweep 0
  return { path: `M${x1},${y1} A${r},${r} 0 0 ${d > 0 ? 0 : 1} ${x2},${y2}`, label: p(ta + d / 2, r + 15) };
}

export function FreeBody({ item }: { item: DiagramItem }) {
  const drawable = item.forces.every((f) => f.dir !== null) && (!item.acceleration || item.acceleration.dir !== null);
  if (!drawable) {
    return (
      <p className="fbd-note">
        To draw it, give values for {item.missing.map((m, i) => <code key={m}>{(i ? ", " : "") + m}</code>)} with a{" "}
        <code>draw</code> line, such as <code>draw {item.missing[0] ?? "α"} = 0.5</code>.
      </p>
    );
  }
  // SVG's y grows downward
  const at = ([x, y]: [number, number], len: number) => [C + x * len, C - y * len] as const;
  const plane = item.plane;
  const tilt = plane ? (Math.atan2(plane[1], plane[0]) * 180) / Math.PI : 0;
  // the body rests on the plane: its center sits half a box above the line
  const up: [number, number] = plane ? [-plane[1], plane[0]] : [0, 1];
  const [lx, ly] = [C - up[0] * (BOX / 2), C + up[1] * (BOX / 2)];
  const labels: { x: number; y: number; latex: string; accent?: boolean }[] = [];
  const arrows = item.forces.map((f) => {
    const [x2, y2] = at(f.dir!, ARROW);
    const [tx, ty] = at(f.dir!, ARROW + 18);
    labels.push({ x: tx, y: ty, latex: `\\vec{${f.symbol}}` });
    return <line key={f.name} x1={C} y1={C} x2={x2} y2={y2} className="fbd-force" markerEnd="url(#fbd-head)" />;
  });
  // the slope's foot is its lower end on screen
  const half = 140;
  const ends = plane ? [[lx - plane[0] * half, ly + plane[1] * half], [lx + plane[0] * half, ly - plane[1] * half]] : [];
  const marks = item.marks.flatMap((m, i) => {
    if (!m.from || !m.to) return [];
    if (m.at === "foot" && plane) {
      const [fx, fy] = ends[0][1] > ends[1][1] ? ends[0] : ends[1];
      // from the foot, up the slope and along the ground underneath it
      const upSlope: [number, number] = ends[0][1] > ends[1][1] ? [plane[0], plane[1]] : [-plane[0], -plane[1]];
      const ground: [number, number] = [Math.sign(upSlope[0]) || 1, 0];
      const a = arc(fx, fy, 46, ground, upSlope);
      labels.push({ x: a.label[0], y: a.label[1], latex: m.label.latex });
      return [
        <g key={i}>
          <line x1={fx} y1={fy} x2={fx + ground[0] * 90} y2={fy} className="fbd-ground" />
          <path d={a.path} className="fbd-arc" />
        </g>,
      ];
    }
    const a = arc(C, C, 34, m.from, m.to);
    labels.push({ x: a.label[0], y: a.label[1], latex: m.label.latex });
    // an end that is no arrow (up, the horizontal, ...) gets a dashed guide
    const arrowsAt = [...item.forces.map((f) => f.dir), item.acceleration?.dir].filter((d): d is [number, number] => !!d);
    const isArrow = (d: [number, number]) => arrowsAt.some((v) => Math.abs(v[0] - d[0]) + Math.abs(v[1] - d[1]) < 1e-6);
    const guides = [m.from, m.to].filter((d) => !isArrow(d)).map((d, k) => {
      const [x2, y2] = at(d, 62);
      return <line key={k} x1={C} y1={C} x2={x2} y2={y2} className="fbd-ground" />;
    });
    return [
      <g key={i}>
        {guides}
        <path d={a.path} className="fbd-arc" />
      </g>,
    ];
  });
  let accel = null;
  if (item.acceleration?.dir) {
    // beside the body, offset sideways so it does not sit on a force
    const d = item.acceleration.dir;
    // beside the body on the side away from the plane, so it stays clear of
    // the slope and of the angle at its foot
    let side: [number, number] = [-d[1], d[0]];
    if (side[0] * up[0] + side[1] * up[1] < 0) side = [d[1], -d[0]];
    const ox = side[0] * 34, oy = -side[1] * 34;
    const [x2, y2] = at(d, 62);
    labels.push({ x: x2 + ox + d[0] * 14, y: y2 + oy - d[1] * 14, latex: `\\vec{a}`, accent: true });
    accel = (
      <line x1={C + ox + d[0] * 26} y1={C + oy - d[1] * 26} x2={x2 + ox} y2={y2 + oy} className="fbd-accel" markerEnd="url(#fbd-head-accent)" />
    );
  }
  return (
    <div className="fbd">
      <div className="fbd-canvas" style={{ width: SIZE, height: SIZE }}>
        <svg width={SIZE} height={SIZE} role="img" aria-label={`Free-body diagram: ${item.forces.map((f) => f.name).join(", ")}`}>
          <defs>
            <marker id="fbd-head" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
              <path d="M0,0 L10,5 L0,10 z" className="fbd-head" />
            </marker>
            <marker id="fbd-head-accent" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
              <path d="M0,0 L10,5 L0,10 z" className="fbd-head-accent" />
            </marker>
          </defs>
          {plane && (
            <line
              x1={lx - plane[0] * 140} y1={ly + plane[1] * 140} x2={lx + plane[0] * 140} y2={ly - plane[1] * 140}
              className="fbd-plane"
            />
          )}
          <rect x={C - BOX / 2} y={C - BOX / 2} width={BOX} height={BOX} rx={3} className="fbd-body" transform={`rotate(${-tilt} ${C} ${C})`} />
          {marks}
          {arrows}
          {accel}
          <circle cx={C} cy={C} r={2.5} className="fbd-center" />
        </svg>
        {labels.map((l, i) => (
          <span key={i} className={l.accent ? "fbd-label accent" : "fbd-label"} style={{ left: l.x, top: l.y }}>
            <Tex latex={l.latex} />
          </span>
        ))}
      </div>
      {/* sizes that are expressions; N = N says nothing */}
      <dl className="fbd-legend">
        {item.forces
          .filter((f) => f.magnitude.text !== f.name)
          .map((f) => (
            <div key={f.name}>
              <Tex latex={`${f.symbol} = ${f.magnitude.latex}`} />
            </div>
          ))}
        {item.acceleration && item.acceleration.magnitude.text !== "a" && (
          <div className="accent">
            <Tex latex={`a = ${item.acceleration.magnitude.latex}`} />
          </div>
        )}
      </dl>
    </div>
  );
}
