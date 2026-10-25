# Landau

A small language for encoding physics as **definitions, laws and derivations**,
with static **dimension checking** and a CAS (SymPy) for simplifying and solving.

Every law is checked for dimensional consistency. Every derivation step is
re-checked, and each derived law records which axioms it rests on and which
assumptions the CAS was allowed to use.

Try it in the browser, nothing to install: https://domandlj.github.io/Landau/

```
$ ./landau -v modules/projectile.lan
...
  derive range : R = v0^2*sin(2*θ)/g   [L]
      from    Kinematics.position
      assumes t > 0, g > 0
      via     instantiate, instantiate, solve for t, subst, simplify
```

## Setup

Needs the opam switch `landau` (OCaml 5.2 with dune, menhir, zarith, yojson)
and a `.venv` with SymPy in this folder:

```
opam switch create landau 5.2.1
opam install --switch=landau dune menhir zarith yojson
python3 -m venv .venv && .venv/bin/pip install sympy scipy
```

Then `./landau [-v] file.lan` builds if needed and runs. `-v` prints every
derivation step. Set `LANDAU_PYTHON` to use another Python.

## Web frontend

`web/` is a React + TypeScript app (Vite): an editor with Landau highlighting
and inline errors next to the results, with laws rendered as math (KaTeX),
dimension badges and expandable derivations. It checks as you type, or on
Ctrl+Enter. The ⚙ settings in the header choose the theme (dark by default or
light), how dimensions are written (L/T or L·T⁻¹, dimensions or units) and
derivatives: dx/dt, Newton's dots ẋ, ẍ (for
derivatives by a variable of dimension T; others stay dx/dy) or primes x′, x″.
Partial derivatives are always ∂u/∂x. Needs Node 18+:

```
cd web && npm install && npm run dev      # http://127.0.0.1:5173
npm run build                             # a static site in web/dist
```

Checks run in the page, with no server: the checker is compiled to JavaScript
with js_of_ocaml (`js/landau.ml`; `npm run engine` builds it into
`web/public/engine`, and `dev` and `build` do that first) and `cas/worker.py`
runs in Pyodide, CPython compiled to WebAssembly, loaded from jsdelivr. Both
live in a Web Worker (`web/src/engine.worker.ts`). The first check loads
Python and SymPy, about 15 s; after that Python stays loaded. SciPy is loaded
on the first `simulate`. The modules of `modules/` are built into the app, and
modules you save or delete are kept in the browser's localStorage. `npm run
build` needs the opam switch for the checker; `web/dist` can then be served by
any static file server.
`./deploy-pages` publishes it on GitHub Pages: it builds `main` (not the
working tree) with the repository name as the base path and force-pushes the
result as the only commit of the `gh-pages` branch.

`npm run dev:server` checks with the native `landau` instead: the Vite server
runs `landau --json -` for each check (see `web/vite.config.ts`), so it only
listens on localhost, and saving writes `modules/*.lan`.
`#name` in the URL opens that module; a first visit opens the tour, `#landau`.

`wasm/smoke.mjs` checks every module with the browser engine in Node and
compares each report with the native one; `wasm/bench` times SymPy natively
and in Pyodide.

The **?** button (or F1) opens a searchable reference of the whole language,
with formulas, examples to insert and a short program to try for each topic;
`#help` and `#help/integrals` open it from a link. Its content is in
`web/src/help.ts`.

`landau --json file.lan` (or `-` for stdin) prints the whole report as one JSON
object: theories with their items (`law`, `derive`, `def`, `var`, ...), each with
its line and both text and LaTeX forms, plus a list of errors.

## Tests

`./run-tests` runs everything; `./run-tests lang` or `./run-tests web` runs one
suite.

- **Language** (`test/`, `dune test`): cram tests, each a transcript of `landau`
  commands and their expected output. `modules.t` holds the full output of every
  module, the other files cover one feature each with small programs in
  `test/cases/`. A failure prints the difference; after an intended change,
  `dune promote` makes the new output the expected one. Dune reruns a test only
  when its inputs change (the binary, the SymPy worker, the modules, the cases).
- **Web app** (`web/test/`, `npm test` in `web/`, Vitest): every module's report
  renders in the results panel with every formula accepted by KaTeX, in all four
  dimension displays, derivation steps included; every formula in the help panel
  renders, and every "Try it" program checks with no errors; `importersOf` finds
  the modules that a delete would break. The app renders with
  `throwOnError: false`, so the tests check each formula again with errors on:
  an unknown command would otherwise only show up as red text.

A full cold run takes about a minute per suite, mostly SymPy.

## Language

```
theory Name ... end          -- group declarations; top-level ones go to `Main`
import Other                 -- bring in a theory: from this file, built in, or a module
import maxwell               -- every theory of the module file modules/maxwell.lan
import Kinematics from projectile   -- one theory of a module

dim L, T                     -- base dimensions
dim Energy = M*L^2/T^2       -- alias; exponents may be rational: L^(-3/2)

var x, x0 : L                -- quantities with their dimension
var t : T, positive          -- attributes: positive, nonzero, real, complex
var θ : 1                    -- dimensionless (variables are real by default)
var F : N                    -- in units, after `import SI` or `unit` declarations
var E : M*L/(T^3*I), vector  -- a 3-vector whose components have this dimension
var p : L, vector(2)         -- vectors of any size: vector(2), vector(4), ...
var r : L, position          -- the position vector grad/div/curl/lap differentiate by
var x(t) : L                 -- x depends on t; undeclared variables are constants
var E(r, t) : M*L/(T^3*I), vector   -- a field: depends on position and time

def vx(v, θ) = v*cos(θ)      -- definition; its dimension scheme is inferred:
                             --   vx : ('a, 1) -> 'a
def f(d : L, t) = d/t        -- parameters can be annotated

law position: x = x0 + v0*t + a*t^2/2

text                         -- notes, shown with the results where they are
  The position is a parabola, $x(t) = x_0 + v_0 t + \frac{a t^2}{2}$.
end

derive range:                -- a new law, built from existing ones
  hx := position[x0 := 0, x := R]   -- instantiate: substitute variables
  tf := solve hy for t              -- SymPy solve (use `, root k` if several)
  u  := solve p, e for u1, u2       -- a system: gives u1, with u2 eliminated
  x  := solve ode for x with x(0) = x0, at(diff(x, t), t, 0) = v0
                                    -- a differential equation, if x(t) is differentiated
  r  := subst tf into hx            -- `x = e` replaces x; `curl(B) = e` replaces curl(B)
  simplify r                        -- SymPy simplify
  unfold r                          -- expand definitions
  hx := component x of m            -- one component of a vector equation
  expand w                          -- write dot, norm, cross, grad, div, curl, lap in components
  d  := differentiate p by t        -- d/dt of both sides
  c  := apply curl to faraday       -- any one-argument function, on both sides
  i  := integrate v by t from 0 to T  -- integral of both sides
  a  := approximate e where v << c order 2   -- series in the small ratio v/c
  l  := limit e as t -> inf         -- limit of both sides
  m  := euler_lagrange lag for x    -- equation of motion from L = ...
  E  := conserved lag for t         -- energy (for t) or momentum (for a coordinate)
end                          -- the last step is the derived law
```

Notes: a `text` block holds prose that the results show where it is written,
to explain a theory step by step. `text` stands alone on its line, and the
block runs to a line holding only `end` (a comment may follow); inside it
nothing is Landau, so keywords and `--` are plain words. The block loses its
common indentation. In the web app it is rendered: `$inline$` and
`$$display$$` math in LaTeX, `**bold**`, `*italic*`, blank lines between
paragraphs, `\$` for a dollar sign. Double-click a note to jump to it.
A line `![caption](src)` shows a picture (PNG, JPG, GIF, SVG, WebP), a video
(MP4, WebM, looping, with controls), or a player for a YouTube or Vimeo link.
`src` is a web address or a path into `modules/`, like `media/projectile.gif`:
the pictures and videos in `modules/media/` are built into the app.
`modules/projectile.lan` shows one, drawn by `modules/media/projectile.py`.

Expressions: `+ - * / ^`, numbers (`9.81` is exact), `pi`, `im` (imaginary
unit) and the functions `sin cos tan asin acos atan atan2 sinh cosh tanh exp
log sqrt abs conj`. Transcendental functions require dimensionless arguments;
`0` is the only literal that has every dimension. Comments start with `--`.

Vectors: every expression is a scalar or an n-vector, checked alongside its
dimension; all components of a vector share one dimension. `+` and `=` need
equal shapes, `*` allows at most one vector, and you cannot divide by or raise
a vector to a power. `vec(a, b, c)` builds a vector and `v.x`, `v.y`, `v.z` (or
`v.1`, `v.2`, ...) take a component. The operations are `dot(a, b)`,
`cross(a, b)` and `curl(F)` (3D only), `norm(a)`, `grad(f)`, `div(F)`, `lap(f)`
and `diff(f, t)` (partial derivative by a variable or a component such as
`r.x`). `0` has every shape, so `curl(E) = 0` is fine. Built-in names cannot be
reused by `def`. Definitions are checked at each use, so they work for any size.

Derivatives: `diff(f, t)` is computed by SymPy. What depends on what is
declared with `var x(t)`: a variable depends only on what it lists, so
`diff(x0 + v0*t, t)` is `v0`. A derivative of something that depends on
nothing in it, like `diff(B, t)` for an undeclared `B`, or `div(B)` when `B`
does not depend on the position, is reported as an error rather than taken
as 0. A variable may depend on another dependent one: with `var θ(t)` and
`var h(θ)`, `diff(h, t)` is `diff(h, θ)*diff(θ, t)` (the chain rule), and
putting `θ := ω*t` into a law makes h the value `h(ω*t)`.

Units: `import SI` brings the SI units (kg m s A K mol cd; N J W Pa C V Ω F S
Wb T H Hz Bq Gy Sv rad sr deg; g km cm mm nm min h ms kJ eV atm bar), and a
variable can be declared in units: `var F : N`, `var v : km/h`. Checking stays
dimensional; units are for reading, and the web app can show results in
dimensions or in units. SI's dimensions are named `Mass`, `Length`, `Time`,
`Current`, `Temperature`, `Amount`, `Luminosity` and shown as M, L, T, I, Θ,
N, J, because T, N and J are units there. Your own units:

```
dim Time (T)                     -- a dimension shown as T
unit s : Time                    -- a base unit: results are shown in these
unit N = kg*m/s^2                -- a named unit, used when it is shorter
unit ft = 0.3048*m               -- a scaled unit; the factor is kept for numbers
```

Angles are dimensionless, as in the SI: `rad` is 1 and `deg` is exactly
`pi/180*rad` (a unit's factor may contain `pi`, as in `unit rev = 2*pi*rad`).
`sin(30 [deg])` is 1/2, and a lone angle keeps its unit: `compute th = 45 [deg]`
shows 45 deg. A variable declared in degrees needs its unit when given a
value, `θ := 30 [deg]`: a bare `θ := 30` (or `θ(0 [s]) = 30` in `simulate`)
is an error, since it would be read as 30 rad. Because a radian and a cycle are both the number 1, the dimension
check cannot tell rad/s from Hz, though 1 Hz is 2π rad/s; converting a value
given in one into the other (`compute 3 [rad/s] in Hz`) is therefore an error
that asks for the 2π. Only such direct conversions are caught: a law like
`ω = f` still checks.

Numbers: a quantity is a number with a unit in brackets, `2 [kg]`,
`9.81 [m/s^2]`, `1.6e-19 [C]`. `const g = 9.81 [m/s^2]` declares a variable
with a value; it stays `g` in algebra. Put values in with instantiation and
use `evaluate`:

```
derive weight_of_2kg:
  w := weight[m := 2 [kg]]
  evaluate w in N digits 3       -- W = 19.6 [N]
end
```

`compute` gives the value of any expression, such as a definition with
numbers put in; a named one becomes a constant for later lines:

```
def kinetic(m : kg, v : m/s) = m*v^2/2     -- parameters with units check arguments
compute kinetic(1500 [kg], 100 [km/h]) in kJ digits 3     -- = 579 [kJ]
compute E1 = kinetic(2 [kg], 3 [m/s])                     -- E1 = 9 [J]
compute E1/(2 [s]) in W                                   -- = 4.5 [W]
```

A definition without dimensions on its parameters works for any dimension, so
it cannot reject arguments. Results are rounded half up to `digits`
significant figures (6 by default) from a precise value.

`evaluate` needs `x = ...` with everything on the right known (constants
count); it converts units with their scale factors and gives `x` in the unit
asked for, in its declared unit, or in units picked for it. If every variable
has a value it checks the equation to the given digits instead. In symbolic
steps quantities stay as they are. `import Constants` brings c, G, h, ħ, e,
k_B, N_A, R_gas, ε0, μ0, k_e, m_e, m_p, m_n, σ_SB and g, with the SI units.

A unit cannot share a name with a dimension. A variable keeps the unit it was
declared in for display, so torque in `N*m` is not shown as `J`.

Integrals: `integral(f, t)` (an antiderivative, without the constant) and
`integral(f, t, a, b)`; bounds may be `inf` or `-inf`, which, like `0`, fit any
dimension. Over curves, surfaces and regions of space, with the curve, surface
or region given by a parametrization:

```
line(F, p, s, a, b)                          -- ∫ F·dr along p(s), or ∫ f dl for a scalar f
loop(F, p, s, a, b)                          -- the same, written ∮, for a closed path
surface(F, q, u, u1, u2, w, w1, w2)          -- ∬ F·dA through q(u, w), or ∬ f dA
volume(f, q, u, u1, u2, v, v1, v2, w, w1, w2)   -- ∭ f dV over the region q(u, v, w)
```

The tangent dp/ds, the normal dq/du × dq/dw and the Jacobian are worked out;
order the parameters so that the normal points outward and the Jacobian is
positive (ρ, θ, φ in spherical coordinates). The field is evaluated on the
region after any derivatives in it are taken, so `volume(div(F), ...)` works.
Dimensions: a line integral adds the dimension of the position, a surface
integral its square, a volume its cube. A variable that depends on something can be evaluated
at a point: `x(0)` is x at t = 0, and `at(e, t, 0)` sets t = 0 in any
expression, such as a derivative.

Free-body diagrams: list the forces on a body and Landau writes Newton's
second law for it, as a law named after the diagram, and the web app draws it:

```
diagram sliding:
  body m                                   -- its mass
  force W = m*g toward down                -- size and direction
  force N toward angle(α + pi/2)           -- no size: the variable N
  force f = μ*N toward angle(α)
  accelerates a toward angle(α + pi)       -- without it, the body is at rest
  plane angle(α)                           -- the surface, for the picture
  draw α = 0.5                             -- values for the picture only
  mark α between plane and right           -- show an angle (and check it)
  mark α between N and up
end
```

A `mark` draws an arc between two of: a force (by name), the acceleration,
`plane`, or a direction. With the `draw` values Landau computes the actual
angle between them and rejects a label that does not match, so a mark that
says α where the picture has 90° − α is an error.

Directions are `up`, `down`, `left`, `right`, `angle(θ)` (from +x,
counterclockwise) or any vector, made unit length. All forces must have the
same dimension. The picture follows textbook style: arrows from the body's
center, all the same length, the acceleration dashed beside it.

Numerical solutions, for equations with no formula for the answer:

```
solve k for E numerically near 1 digits 5        -- a root, by SymPy's nsolve
simulate swing: exact, small for θ, φ from t = 0 [s] to 10 [s]
  with θ(0) = 1.2, at(diff(θ, t), t, 0) = 0, φ(0) = 1.2, at(diff(φ, t), t, 0) = 0
```

`simulate` integrates one or several coupled differential equations of any
order with SciPy's `solve_ivp` (DOP853, or Radau if the system is stiff).
Each unknown is declared `var x(t)`, and needs a starting value for itself and
for each derivative below its highest; everything else needs a value. Values
are converted to base units for the integration and back for display. The CLI
prints a summary; the web app plots each unit in its own panel, with a
crosshair, and has a table view. `points 1000` sets the resolution (400 by
default). SciPy is only loaded by `simulate`.

Approximations: `approximate e where v << c order 2` expands both sides in
the small ratio v/c and keeps terms up to (v/c)^2 (order 1 if not given):
every small variable is multiplied by a bookkeeping ε, the sides are expanded
in ε, and ε is set to 1, so several small quantities (`where x << L, θ << 1`)
count as the same order. The ratio must be dimensionless, so `v << 1` for a
speed is an error. The derived law records the approximation and the first
term it left out, as in `v ≪ c (to order 2); left out: 3*m*v^4/(8*c^2)`.
`limit e as t -> inf` takes the limit of both sides; a lone `v(t)` becomes
`v(inf)`.

Lagrangian mechanics: give the Lagrangian as a law `L = ...` in coordinates
declared with their time, `var x(t)`. `euler_lagrange lag for x` gives the
equation of motion d/dt ∂L/∂ẋ - ∂L/∂x = 0 (SymPy's `euler_equations`), which
`solve` then integrates; its dimension is that of L over that of x.
`conserved lag for t` gives the energy E = Σ ẋ ∂L/∂ẋ - L, summed over the
coordinates in L, and `conserved lag for φ` the momentum p_φ = ∂L/∂φ̇. Each
names a new constant, `E` or `p_φ`, and is an error when Noether's theorem
does not apply: when L depends on t itself, or on φ. `modules/lagrange.lan`
has a spring, a pendulum and the Kepler problem.

Systems: `solve e1, e2, ... for x, y, ...` solves the equations together and
gives the equation for the first unknown, with the others eliminated; list
another unknown first to get that one. A vector equation counts as its
components. When there are several solution sets, all are listed with every
unknown, and `, root k` picks one. Systems of differential equations are not
supported yet.

Differential equations: `solve eq for x` uses SymPy's `dsolve` when x is a
function, `x(t)`, that the equation differentiates. Initial conditions follow
`with`. The constants of a general solution (C1, C2, ...) become variables of
the theory, and their dimensions are inferred: in `x = C1 + C2*t - g*t^2/2`,
C1 is [L] and C2 is [L/T].

Matrices: `var K : M/T^2, matrix(2)` is a square matrix whose entries all
have one dimension; `mat(vec(a, b), vec(c, d))` writes one row by row, and
`identity(n)` is the identity. Shapes are checked (a 2x2 matrix times a
3-vector is an error), products keep their order, `det` of an n x n matrix has
n times its dimension and `inv` the inverse one; `trace`, `transpose` and
`entry(A, i, j)` complete the set. SymPy's symbols commute, so Landau writes
every product with a matrix out entry by entry before SymPy sees it, and asks
SymPy only for determinants, inverses and eigenvalues, all symbolic.
`eigen name: A` lists A's eigenvalues and eigenvectors; `eigen name: K, M`
solves K v = λ M v (normal modes, λ = ω²), with λ's dimension that of K over M.
A matrix variable stands for the law defining it. `modules/matrices.lan` has
coupled oscillators, an inertia tensor and a spin in a magnetic field.

Sums and integers: `sum(f, k, a, b)` adds f for k = a, ..., b (`b` may be
`inf`). The counter k belongs to the sum, needs no `var`, and is a whole
number; it and the bounds are dimensionless, and the sum has f's dimension.
`simplify` closes sums SymPy can do (Σ1/k² = π²/6, geometric series, including
exponential ones like a partition function Σe^(−βħω(k+1/2))); one with no closed
form, or whose closed form splits into cases Landau cannot decide (r = 1 or
not), stays a sum, and `compute` evaluates it numerically. `var n : 1,
integer, positive` declares a count, so that sin(nπ) = 0 and cos(nπ) = (−1)ⁿ:
the particle in a box and Fourier coefficients come out right.
`modules/series.lan` has these.

Dimensional analysis (Buckingham π): `groups name: P, ℓ, g, m, θ0` lists the
dimensionless products of the variables, one per variable beyond the number of
independent dimensions; earlier variables are used to cancel the later ones'
dimensions. `groups name: P from ℓ, g, m, θ0` also writes P as a product of the
others times an unknown function of the remaining groups,
`P = sqrt(ℓ/g)*Φ(θ0)`, or times a constant C when none remain. A variable that
no product of the others matches in dimension (`m`, the only one with M) cannot
appear, and is reported. SymPy finds the groups as the nullspace of the matrix
of exponents; Landau makes the exponents whole numbers and checks that each
group is dimensionless. `modules/dimensional.lan` has the pendulum, drag
(Reynolds number), Taylor's blast wave, Kepler's third law, deep water waves
and the Planck length.

After `apply`, `subst` and `simplify`, `grad`, `div`, `curl` and `lap` are
linear, pass through constants, commute with derivatives by time, and
`div(curl F)` and `curl(grad f)` are 0. A law whose two sides `simplify` to
the same thing, in every component, becomes `0 = 0` and is marked as holding
identically.

`component x of eq` pushes the component inside: `(a + s*b).x` becomes
`a.x + s*b.x`, `vec(p, q).y` becomes `q`, and `cross` and `curl` get their
textbook component formulas. Before `simplify` and `solve`, `dot`, `norm` and
`cross` of concrete vectors are written out, so `norm(vec(3, 4))` gives `5`.

## How it works

- **Dimensions** are sparse vectors of rational exponents (`lib/dim.ml`).
- **Inference** (`lib/infer.ml`): every operator imposes a linear constraint on
  those vectors, so solving them is Gaussian elimination over Q. Unsolved
  variables in a definition become its polymorphic dimension variables.
- **Derivations** (`lib/check.ml`): instantiate, `subst` and `unfold` are done in
  OCaml; `solve` and `simplify` go to SymPy (`lib/cas.ml` ↔ `cas/worker.py`)
  as JSON trees, with variables renamed and their assumptions attached.
- **Shapes** (`lib/shape.ml`): scalar or vector, inferred separately from
  dimensions. A definition's accepted shapes are found by trying every
  combination of scalar and vector arguments.
- **Vectors in the CAS**: vector variables go to SymPy as plain symbols and the
  vector operators as opaque functions, which is sound for the linear algebra
  `solve` and `simplify` do. Components (`E.x`) are symbols of their own, and a
  variable with dependencies is a function, `x(t)`, so derivatives work. A
  derivative through a vector operation or the position is first written in
  components, because SymPy cannot see inside an opaque vector. Identities
  such as `div(curl(F)) = 0` are checked with `expand` and `simplify`.
- **Trust**: dimensions, shapes and derivation structure are checked; the
  CAS's algebra is trusted. Physical laws are only applied explicitly by the user.

## Modules

Every `.lan` file is a module, and `import` finds what it names in this order:
a theory of the same file, a built-in theory (`SI`, `Constants`), a module file
of that name (all its theories), or a theory of that name in one of the module
files (name the file with `from` if several have it). Module files are looked
for next to the checked file, in any `--modules DIR`, and in `modules/`. Modules
can import each other, but not in a circle; an error in an imported module is
reported at the `import` with its file and line. `--as FILE` checks stdin as if
it were FILE, for its imports (the web app uses it).

In the web app, the Modules menu opens a module or starts a new one, and Save
(Ctrl+S) or Save as… writes `modules/name.lan`; module names are identifiers,
since they are what `import` names. Delete moves the module to
`modules/.trash/` (with the time in its name), where it can be recovered; it
warns first if other modules import it.

The modules that come with Landau:

- `modules/landau.lan`: a tour of the language, with a photo of Lev Landau at the blackboard (linked, not copied); the web app opens it on a first visit
- `modules/projectile.lan`: projectile range from one 2D vector law, by components
- `modules/energy.lan`: free fall from energy conservation, with definitions
- `modules/quantum.lan`: rational exponents (ψ : L^(-3/2)), complex values; a plane wave gives the dispersion relation
- `modules/maxwell.lan`: Maxwell's equations and the Lorentz force; the continuity and wave equations; a plane wave gives the speed of light
- `modules/approximations.lan`: the classical limit of E = γmc², the small-angle pendulum, gravity near the surface, terminal velocity
- `modules/forces.lan`: free-body diagrams: a block on an incline with friction, a hanging knot, an Atwood machine
- `modules/numerical.lan`: Kepler's equation, the exact pendulum against the small-angle one, the Earth's orbit
- `modules/numbers.lan`: putting in numbers, converting units, checking answers
- `modules/units.lan`: SI units, declared units, and showing results in units
- `modules/systems.lan`: elastic collisions, an Atwood machine, Kirchhoff's rules
- `modules/work.lan`: work along a line and along a path through a force field
- `modules/integrals.lan`: areas, volumes, a cone's mass, improper integrals; Gauss's and Stokes's theorems checked
- `modules/motion.lan`: velocity and acceleration as derivatives; differential equations and integrals; vector calculus identities
- `modules/errors.lan`: what dimension errors look like
