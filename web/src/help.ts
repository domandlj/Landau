// The in-app reference. Text may contain `code` and $math$; `tex` fields are
// LaTeX shown next to the syntax; `example` and `tryIt` are Landau source.

export interface HelpEntry {
  syntax: string;
  tex?: string;
  text: string;
  example?: string;
}

export interface HelpSection {
  id: string;
  title: string;
  intro?: string;
  entries?: HelpEntry[];
  /** A complete program that checks cleanly, to open in the editor. */
  tryIt?: string;
}

const r = String.raw;

export const HELP: HelpSection[] = [
  {
    id: "start",
    title: "Getting started",
    intro:
      "Landau is a language for physics: you declare dimensions and quantities, state laws, and derive new laws from them. " +
      "Every law is checked for dimensional consistency ($[F] = [m][a]$), every derivation step is checked again, and SymPy " +
      "does the algebra and calculus. The editor checks as you type; press `Ctrl+Enter` to check right away. " +
      "Errors are underlined in the editor and listed in the results, and each card's `line N` link jumps to its source.",
    tryIt: `-- Newton's second law, and what follows from it.
theory Newton
  dim M, L, T
  dim Force = M*L/T^2

  var F : Force
  var m : M, positive
  var a : L/T^2

  law second: F = m*a

  derive accel:          -- a = F/m
    solve second for a
  end
end
`,
  },
  {
    id: "structure",
    title: "Files and theories",
    entries: [
      {
        syntax: "theory Name ... end",
        text: "Groups declarations. Declarations outside any theory belong to a theory called `Main`.",
        example: "theory Kinematics\n  dim L, T\n  var x : L\nend",
      },
      {
        syntax: "import Other",
        text: "Brings in everything from a theory: one defined earlier in this file, a built-in one (`SI`, `Constants`), or one in a module file. Its names can also be written qualified, as `Other.law`.",
      },
      {
        syntax: "import maxwell",
        text: "A module is a file in `modules/`; `import maxwell` brings in all the theories of `maxwell.lan`. If they clash with each other, import one at a time.",
      },
      {
        syntax: "import Kinematics from projectile",
        text: "One theory of a module; needed when several modules have a theory of that name. Modules can import each other, but not in a circle.",
      },
      { syntax: "-- comment", text: "Comments run to the end of the line (`#` works too)." },
    ],
  },
  {
    id: "dims",
    title: "Dimensions",
    intro:
      "A dimension is a product of powers of base dimensions, like $\\mathsf{M\\,L\\,T^{-2}}$. Exponents may be fractions: " +
      "a 3D wavefunction has dimension $\\mathsf{L^{-3/2}}$.",
    entries: [
      { syntax: "dim M, L, T", text: "Declares base dimensions. Any names work; SI uses M, L, T, I (current), Θ, N, J." },
      {
        syntax: "dim Force = M*L/T^2",
        tex: r`\mathsf{Force} = \mathsf{M\,L/T^{2}}`,
        text: "A name for a combination, usable wherever a dimension is expected.",
      },
      { syntax: "L^(-3/2)", tex: r`\mathsf{L}^{-3/2}`, text: "Rational exponents go in parentheses." },
      { syntax: "1", text: "Dimensionless, as in `var θ : 1`." },
    ],
  },
  {
    id: "groups",
    title: "Dimensional analysis",
    intro:
      "Buckingham's π theorem: any law between some quantities can be written as a law between their dimensionless " +
      "products. `groups` finds those products, so you can see what a result can depend on before deriving it.",
    entries: [
      {
        syntax: "groups name: P, ℓ, g, m, θ0",
        tex: r`\Pi_{1} = \frac{g\,P^{2}}{\ell},\quad \Pi_{2} = \theta_{0}`,
        text: "The dimensionless groups $\Pi_1, \Pi_2, \ldots$ of the variables: one for each variable beyond the number of independent dimensions. Earlier variables are the ones used to make the later ones dimensionless. A variable that no product of the others matches in dimension, like `m` here (nothing else has M), cannot appear in any group.",
      },
      {
        syntax: "groups name: P from ℓ, g, m, θ0",
        tex: r`P = \sqrt{\frac{\ell}{g}}\,\Phi(\theta_{0})`,
        text: "Also solves for `P`: it is a product of the others times an unknown function $\Phi$ of the remaining groups, or times a dimensionless constant $C$ when no groups are left. It is an error if no product of the others has `P`'s dimension.",
      },
    ],
    tryIt: `-- What can a pendulum's period depend on?
theory Pendulum
  dim M, L, T
  var P : T        -- the period
  var ℓ : L        -- the length
  var g : L/T^2
  var m : M        -- the mass
  var θ0 : 1       -- the amplitude

  groups period: P from ℓ, g, m, θ0
end
`,
  },
  {
    id: "units",
    title: "Units",
    intro:
      "`import SI` brings the SI units, and a variable can then be declared in units instead of dimensions. " +
      "Checking is still by dimension, so `km/h` and `m/s` are both speeds; units are for reading. The *Dims / Units* " +
      "switch at the top shows results in either. In SI, `T` is the tesla and `N` the newton, so its dimensions are " +
      "named in words, `Mass`, `Length`, `Time`, `Current`, `Temperature`, `Amount`, `Luminosity`, and shown as " +
      "$\\mathsf{M, L, T, I, \\Theta, N, J}$.",
    entries: [
      {
        syntax: "import SI",
        text: "Base units `kg m s A K mol cd`; `N J W Pa C V Ω F S Wb T H Hz Bq Gy Sv rad sr`; and `g km cm mm nm min h ms kJ eV atm bar`.",
      },
      { syntax: "var F : N", tex: r`F \;[\mathrm{N}]`, text: "A variable in units; shown in that unit. Units and dimensions can be mixed: `var p : kg*Length/s`." },
      {
        syntax: "var τ : N*m",
        tex: r`\mathrm{N\,m} 	ext{ vs } \mathrm{J}`,
        text: "Torque and energy have the same dimension; declaring the unit keeps them apart when shown. A law `τ = ...` is shown in τ's unit.",
      },
      { syntax: "unit kg : Mass", text: "A base unit: what results are shown in. One per base dimension." },
      { syntax: "unit N = kg*m/s^2", tex: r`\mathrm{N} = \mathrm{kg\,m/s^{2}}`, text: "A named unit. Results use it when that is shorter than base units: $\\mathrm{F/m}$ rather than $\\mathrm{A^{2}\\,s^{4}/(kg\\,m^{3})}$." },
      { syntax: "unit ft = 0.3048*m", text: "A scaled unit. The factor (`1.6e-19` works too) will matter for numbers; for checking, `ft` is a length." },
      { syntax: "dim Time (T)", text: "A dimension with a display symbol." },
    ],
    tryIt: `theory Fields
  import SI
  var E : V/m
  var Q : C
  var ε0 : F/m, positive
  var R : m, positive

  law coulomb: E = Q/(4*pi*ε0*R^2)

  derive charge:           -- Q = 4*pi*ε0*R^2*E, in C
    solve coulomb for Q
  end
end
`,
  },
  {
    id: "numbers",
    title: "Numbers and constants",
    intro:
      "A quantity is a number with a unit in brackets: `2 [kg]`, `9.81 [m/s^2]`. Put values into a law with instantiation, " +
      "then `evaluate` it: the units are converted with their scale factors and the result comes in the unit you ask for. " +
      "In symbolic steps quantities stay as they are, so `solve` still works and dimensions are still checked.",
    entries: [
      { syntax: "3 [km]", tex: r`3\,\mathrm{km}`, text: "A quantity. Its dimension is its unit's: `3 [km]` can replace a length. `1.6e-19 [C]` works too." },
      {
        syntax: "const g = 9.81 [m/s^2]",
        tex: r`g = 9.81\,\mathrm{m/s^{2}}`,
        text: "A variable with a value. It stays `g` in algebra; `evaluate` uses the value.",
      },
      {
        syntax: "evaluate f",
        tex: r`W = 19.62\,\mathrm{N}`,
        text: "For `x = ...` with everything on the right known: the value of `x`, in its declared unit or in units picked for it.",
      },
      { syntax: "evaluate f in km/h", text: "In a unit of your choice; it must have the right dimension." },
      { syntax: "evaluate f digits 3", text: "To 3 significant figures (6 by default)." },
      {
        syntax: "evaluate newton[F := 29.4 [N], m := 3 [kg], a := 9.8 [m/s^2]] digits 3",
        text: "When every variable has a value, `evaluate` checks the equation to that many digits: it holds, or the error shows both sides.",
      },
      {
        syntax: "compute kinetic(1500 [kg], 100 [km/h]) in kJ digits 3",
        tex: r`\operatorname{kinetic}(1500\,\mathrm{kg},\ 100\,\mathrm{km/h}) = 579\,\mathrm{kJ}`,
        text: "The value of any expression, such as a definition with numbers put in. `in` and `digits` work as in `evaluate`. A definition checks its arguments' dimensions only where its parameters have them: `def kinetic(m : kg, v : m/s) = m*v^2/2`.",
      },
      {
        syntax: "compute E1 = kinetic(2 [kg], 3 [m/s])",
        text: "A named result is a constant: later lines can use `E1`, as in `compute E1/(2 [s]) in W`.",
      },
      {
        syntax: "solve k for E numerically near 1 digits 5",
        text: "A root found numerically, near a first guess with the dimension of the unknown, for equations with no formula for the answer, like Kepler's $M = E - e\\sin E$. Every other quantity needs a value.",
      },
      {
        syntax: "simulate name: laws for x, y from t = 0 [s] to 10 [s] with x(0) = ..., at(diff(x, t), t, 0) = ...",
        tex: r`\ddot\theta = -\tfrac{g}{L}\sin\theta`,
        text: "Integrates differential equations numerically (SciPy), one or several coupled ones, of any order: each unknown, declared `var x(t)`, needs a starting value for itself and each derivative below its highest. The result is plotted, one panel per unit, with a table view. `points 1000` sets the resolution (400 by default).",
      },
      {
        syntax: "import Constants",
        text: "With the SI units: `c G h ħ e k_B N_A R_gas ε0 μ0 k_e m_e m_p m_n σ_SB g` (standard gravity), exact where the SI defines them, CODATA 2018 otherwise.",
      },
    ],
    tryIt: `theory Thrown
  import Constants
  var v, v0 : m/s
  var t : s, positive

  law speed: v = v0 - g*t

  -- thrown up at 15 m/s: when does it stop rising?
  derive top:              -- t = 1.53 s
    s := speed[v := 0 [m/s], v0 := 15 [m/s]]
    t1 := solve s for t
    evaluate t1 digits 3
  end
end
`,
  },
  {
    id: "vars",
    title: "Variables",
    entries: [
      { syntax: "var x, x0 : L", text: "Quantities and their dimension. Variables are real numbers unless declared otherwise." },
      {
        syntax: "var θ0, v_max, E.x",
        tex: r`\theta_{0},\ v_{\mathrm{max}},\ E_{x}`,
        text: "Names may use Greek letters: type `\\theta` (or `\\the`, then Enter) in the editor to insert θ. Trailing digits and the part after `_` are shown as subscripts; `E.x` is a vector's component.",
      },
      {
        syntax: "var t : T, positive",
        text: "Attributes: `positive`, `nonzero`, `real`, `complex`. They tell SymPy what it may assume (and are listed under *assumes*): with `positive`, $\\sqrt{t^2} = t$ and negative roots are discarded.",
      },
      {
        syntax: "var E : M*L/(T^3*I), vector",
        tex: r`\vec{E}`,
        text: "A 3-vector whose components all have this dimension. `vector(2)`, `vector(4)`, ... give other sizes.",
      },
      {
        syntax: "var r : L, position",
        tex: r`\vec{r}`,
        text: "The position vector: `grad`, `div`, `curl`, `lap` and the integrals over regions use it. One per theory; `position(2)` for the plane.",
      },
      {
        syntax: "var x(t) : L",
        tex: r`x(t)`,
        text: "`x` depends on `t`. Undeclared variables are constants, so $\\frac{\\mathrm{d}}{\\mathrm{d}t}(x_0 + v_0 t) = v_0$. A variable may depend only on independent variables (`t`, the position).",
      },
      { syntax: "var E(r, t) : ..., vector", tex: r`\vec{E}(\vec{r}, t)`, text: "A field: depends on position and time." },
    ],
  },
  {
    id: "defs",
    title: "Definitions",
    entries: [
      {
        syntax: "def vx(v, θ) = v*cos(θ)",
        tex: r`\operatorname{vx} : (\alpha,\ 1) \to \alpha`,
        text: "A reusable expression. Its dimensions are inferred: `vx` works for a `v` of any dimension $\\alpha$ and needs a dimensionless `θ`. Definitions are expanded before the CAS sees them.",
      },
      {
        syntax: "def f(d : L, t) = d/t",
        text: "Parameters may be given a dimension. Definitions work for scalars and vectors alike, and cannot reuse a built-in name such as `div`.",
      },
      { syntax: "def Ew() = vec(0, E0*cos(k*r.x - ω*t), 0)", text: "A definition with no parameters names a fixed expression; call it as `Ew()`." },
    ],
  },
  {
    id: "laws",
    title: "Laws",
    entries: [
      {
        syntax: "law second: F = m*a",
        tex: r`F = m\,a \qquad [\mathsf{M\,L/T^{2}}]`,
        text: "An equation that holds in the theory. Both sides must have the same dimension and the same shape (scalar or vector). The badge shows the dimension.",
      },
      {
        syntax: "0, inf",
        text: "The literals `0` and `inf` have every dimension and every shape, so `div(B) = 0` and `integral(f, x, 0, inf)` are fine. Other numbers are dimensionless.",
      },
    ],
  },
  {
    id: "exprs",
    title: "Expressions",
    entries: [
      { syntax: "+  -  *  /  ^", text: "Arithmetic. `^` binds tightest; exponents must be dimensionless." },
      { syntax: "9.81", text: "Numbers are exact: `9.81` is $981/100$." },
      { syntax: "pi, im, inf", tex: r`\pi,\quad i,\quad \infty`, text: "Constants." },
      {
        syntax: "sin cos tan asin acos atan sinh cosh tanh exp log",
        text: "These need a dimensionless argument: `exp(t)` with `t` a time is an error, `exp(-t/τ)` is fine.",
      },
      { syntax: "sqrt(x)", tex: r`\sqrt{x}`, text: "Halves the exponents: $\\sqrt{\\mathsf{L^2}} = \\mathsf{L}$." },
      { syntax: "abs(x), conj(z), atan2(y, x)", tex: r`|x|,\quad \overline{z}`, text: "`atan2` needs two arguments of the same dimension." },
    ],
  },
  {
    id: "vectors",
    title: "Vectors",
    intro:
      "Every expression is a scalar or an $n$-vector. `+` and `=` need equal shapes, `*` allows at most one vector, " +
      "and you cannot divide by a vector or raise one to a power.",
    entries: [
      {
        syntax: "vec(a, b, c)",
        tex: r`\begin{pmatrix} a \\ b \\ c \end{pmatrix}`,
        text: "A vector from its components, which must share one dimension.",
      },
      { syntax: "v.x  v.y  v.z   v.1  v.2 ...", tex: r`v_x,\ v_y,\ v_z`, text: "A component, as a scalar. Vectors longer than 3 use numbers." },
      { syntax: "dot(a, b)", tex: r`\vec{a} \cdot \vec{b}`, text: "Scalar product; the dimensions multiply." },
      { syntax: "cross(a, b)", tex: r`\vec{a} \times \vec{b}`, text: "Vector product, 3D only." },
      { syntax: "norm(a)", tex: r`\lVert \vec{a} \rVert`, text: "Length; same dimension as `a`. (`abs` is for scalars.)" },
    ],
    tryIt: `theory Torque
  dim M, L, T
  var r : L, position
  var F : M*L/T^2, vector
  var τ : M*L^2/T^2, vector

  law torque: τ = cross(r, F)

  derive about_z:          -- τ.z = r.x*F.y - r.y*F.x
    component z of torque
  end
end
`,
  },
  {
    id: "calculus",
    title: "Derivatives",
    intro:
      "SymPy computes derivatives, using what each variable depends on. A derivative of something that does not depend on " +
      "the variable is reported as an error rather than taken as 0, because it usually means a missing `var x(t)`.",
    entries: [
      { syntax: "diff(x, t)", tex: r`\frac{\mathrm{d}x}{\mathrm{d}t}`, text: "Derivative by a variable, or by a component such as `r.x`. Nest it for higher derivatives." },
      { syntax: "diff(diff(x, t), t)", tex: r`\frac{\mathrm{d}^{2}x}{\mathrm{d}t^{2}}`, text: "Shown with $\\mathrm{d}$ when everything depends on one variable, with $\\partial$ otherwise." },
      { syntax: "grad(f)", tex: r`\nabla f`, text: "Gradient of a scalar, by the position." },
      { syntax: "div(F)", tex: r`\nabla \cdot \vec{F}`, text: "Divergence of a vector." },
      { syntax: "curl(F)", tex: r`\nabla \times \vec{F}`, text: "Curl of a 3-vector." },
      { syntax: "lap(f)", tex: r`\nabla^{2} f`, text: "Laplacian of a scalar or a vector." },
      { syntax: "x(0)", tex: r`x(0)`, text: "A variable at a point: `x` with `t = 0`." },
      { syntax: "at(e, t, 0)", tex: r`\left. e \right|_{t = 0}`, text: "Any expression at a point, such as a derivative: `at(diff(x, t), t, 0)`." },
    ],
    tryIt: `theory Motion
  dim L, T
  var t : T
  var x(t) : L
  var v(t) : L/T
  var x0 : L
  var v0 : L/T
  var g : L/T^2, positive

  law position: x = x0 + v0*t - g*t^2/2
  law velocity: v = diff(x, t)

  derive speed:            -- v = v0 - g*t
    s := subst position into velocity
    simplify s
  end
end
`,
  },
  {
    id: "integrals",
    title: "Integrals",
    intro:
      "Over curves, surfaces and regions, you give a parametrization and Landau works out the tangent, the normal " +
      "$\\partial_u \\vec{q} \\times \\partial_w \\vec{q}$ and the Jacobian. Order the parameters so the normal points " +
      "outward and the Jacobian is positive ($\\rho, \\theta, \\varphi$ in spherical coordinates).",
    entries: [
      { syntax: "integral(f, x)", tex: r`\int f\,\mathrm{d}x`, text: "An antiderivative, without the constant." },
      { syntax: "integral(f, x, a, b)", tex: r`\int_a^b f\,\mathrm{d}x`, text: "Definite; the bounds have the dimension of `x` and may be `-inf`, `inf`." },
      {
        syntax: "line(F, p, s, a, b)",
        tex: r`\int \vec{F} \cdot \mathrm{d}\vec{r} = \int_a^b \vec{F}(\vec{p}(s)) \cdot \frac{\mathrm{d}\vec{p}}{\mathrm{d}s}\,\mathrm{d}s`,
        text: "Along the path `p(s)`. For a scalar `f` it is $\\int f\\,\\mathrm{d}\\ell$ (with `f = 1`, the length).",
      },
      { syntax: "loop(F, p, s, a, b)", tex: r`\oint \vec{F} \cdot \mathrm{d}\vec{r}`, text: "The same, for a closed path." },
      {
        syntax: "surface(F, q, u, u1, u2, w, w1, w2)",
        tex: r`\iint \vec{F} \cdot \mathrm{d}\vec{A},\qquad \mathrm{d}\vec{A} = \frac{\partial \vec{q}}{\partial u} \times \frac{\partial \vec{q}}{\partial w}\,\mathrm{d}u\,\mathrm{d}w`,
        text: "Flux through the surface `q(u, w)`; for a scalar, $\\iint f\\,\\mathrm{d}A$.",
      },
      {
        syntax: "volume(f, q, u, u1, u2, v, v1, v2, w, w1, w2)",
        tex: r`\iiint f\,\mathrm{d}V`,
        text: "Over the region `q(u, v, w)`. Bounds may depend on outer parameters, as in a cone.",
      },
    ],
    tryIt: `theory Sphere
  dim L
  var r : L, position
  var R : L, positive
  var θ, φ : 1
  var A : L^2

  law area: A = surface(1, vec(R*sin(θ)*cos(φ), R*sin(θ)*sin(φ), R*cos(θ)), θ, 0, pi, φ, 0, 2*pi)

  derive value:            -- A = 4*pi*R^2
    simplify area
  end
end
`,
  },
  {
    id: "derive",
    title: "Derivations",
    intro:
      "A derivation builds a new law from existing ones, one step per line. `name := step` names a step for later steps; " +
      "the last step is the derived law. Each step is checked for shape and dimension again, and the result records " +
      "the laws it came *from*, what SymPy *assumes*, and any integration *constants*. A law reduced to $0 = 0$ " +
      "is marked *holds identically*.",
    entries: [
      { syntax: "derive name: ... end", text: "Defines the law `name`; later laws and derivations can use it." },
      { syntax: "position   Kinematics.position", text: "Refers to a law, or to an earlier named step." },
      {
        syntax: "position[x0 := 0, a := -g]",
        text: "Instantiate: put expressions in place of variables. Each replacement must match the variable's dimension and shape.",
      },
      {
        syntax: "subst tf into hx",
        text: "If `tf` is `x = e`, replace `x` by `e` in `hx`. If it is `curl(B) = e`, replace the whole expression `curl(B)` wherever it appears.",
      },
      {
        syntax: "solve e for x",
        text: "Solve with SymPy. If there are several solutions they are listed; pick one with `solve e for x, root 2`.",
      },
      {
        syntax: "solve e1, e2 for x, y",
        text: "A system. The result is the equation for the first unknown, with the others eliminated; list another first to get it. A vector equation counts as its components.",
      },
      {
        syntax: "solve ode for x with x(0) = x0, at(diff(x, t), t, 0) = v0",
        tex: r`x = C_1 + C_2\,t - \tfrac{1}{2} g t^2`,
        text: "A differential equation, when `x(t)` is differentiated. Without initial conditions the constants $C_1, C_2$ appear, with their dimensions inferred.",
      },
      { syntax: "simplify e", text: "Simplify both sides with SymPy; derivatives and integrals are computed." },
      { syntax: "unfold e", text: "Expand the definitions used in `e`." },
      {
        syntax: "diagram name: body m  force W = m*g toward down  ...  end",
        tex: r`m\,\vec{a} = \vec{W} + \vec{N} + \vec{f}`,
        text: "A free-body diagram: one `force F = size toward direction` line per force (`force N toward ...` uses the variable `N` as the size), with directions `up`, `down`, `left`, `right`, `angle(θ)` from +x counterclockwise, or any vector. `accelerates a toward d` gives the acceleration; without it the body is at rest. Landau writes Newton's second law as the law `name` and draws the diagram; `plane angle(α)` adds the surface and `draw α = 0.5` gives values for the picture only. `mark α between plane and right` (or between forces, `a`, `up`, ...) draws an angle, and is checked: with the draw values, the angle between the two must be the label's. Then take components and solve.",
      },
      {
        syntax: "approximate e where v << c order 2",
        tex: r`\frac{m c^{2}}{\sqrt{1 - v^{2}/c^{2}}} \approx m c^{2} + \tfrac{1}{2} m v^{2}`,
        text: "Expand in the small ratio $v/c$, keeping terms up to $(v/c)^2$ (order 1 if not given). The ratio must be dimensionless: `v << 1` for a speed is an error. Several small quantities, `where x << L, θ << 1`, count as the same order. The derived law records the approximation and the first term it left out.",
      },
      {
        syntax: "limit e as t -> inf",
        tex: r`v(\infty) = \frac{m g}{b}`,
        text: "The limit of both sides; a lone `v(t)` becomes `v(inf)`. Also `as x -> 0`, or to any value of the right dimension.",
      },
      { syntax: "expand e", text: "Write `dot`, `norm`, `cross`, `grad`, `div`, `curl` and `lap` in components. With `simplify` after it, this proves vector identities." },
      { syntax: "component x of e", tex: r`(\vec{a} + s\,\vec{b})_x = a_x + s\,b_x`, text: "One component of a vector equation." },
      { syntax: "differentiate e by t", tex: r`\frac{\mathrm{d}}{\mathrm{d}t}\text{ of both sides}`, text: "Differentiate both sides." },
      { syntax: "integrate e by t from a to b", tex: r`\int_a^b \ldots\,\mathrm{d}t \text{ of both sides}`, text: "Integrate both sides." },
      {
        syntax: "apply curl to faraday",
        tex: r`\nabla \times (\ldots) \text{ of both sides}`,
        text: "Apply any one-argument function to both sides. Afterwards `curl`, `div`, `grad`, `lap` are linear, commute with $\\partial_t$, and $\\nabla\\cdot(\\nabla\\times\\vec{F}) = 0$.",
      },
    ],
    tryIt: `theory Collision
  dim M, L, T
  var m1, m2 : M, positive
  var v1, v2 : L/T                 -- before
  var u1, u2 : L/T                 -- after

  law momentum: m1*v1 + m2*v2 = m1*u1 + m2*u2
  law energy:   m1*v1^2/2 + m2*v2^2/2 = m1*u1^2/2 + m2*u2^2/2

  -- root 1 is u1 = v1, u2 = v2: no collision
  derive after:
    solve momentum, energy for u1, u2, root 2
  end
end
`,
  },
  {
    id: "errors",
    title: "Reading errors",
    entries: [
      { syntax: "cannot add `v*t` [L] and `v` [L/T]", text: "The two terms have different dimensions; brackets show each one's dimension." },
      { syntax: "the two sides have different shapes", text: "A vector on one side and a scalar on the other." },
      { syntax: "`diff(B, t)` is always 0 ...", text: "`B` was not declared to depend on `t`: write `var B(r, t)`." },
      { syntax: "`x` has 2 solutions; pick one with `, root k`", text: "Choose a solution; declaring variables `positive` often removes the unphysical ones." },
      { syntax: "this step produced a dimensionally inconsistent equation", text: "A step's result failed the re-check. If it came from SymPy, it is a bug in Landau's bridge, never accepted silently." },
    ],
  },
  {
    id: "ui",
    title: "Using the app",
    entries: [
      { syntax: "Ctrl+Enter", text: "Check now. Otherwise the editor checks shortly after you stop typing." },
      { syntax: "line N", text: "On any card, jumps to the declaration in the editor. In a derivation's steps, the operation (such as *solve for t*) jumps to that step's line." },
      { syntax: "Modules menu", text: "Opens a module from `modules/`, or starts a new one. A URL ending in `#maxwell` opens that module directly, `#help` opens this reference, and `#help/integrals` opens it at a section." },
      {
        syntax: "Save   Save as…   Ctrl+S",
        text: "Saves the editor to `modules/name.lan`, so other modules can import it. A ● after the name means unsaved changes; opening another module or leaving asks first.",
      },
      {
        syntax: "Delete",
        text: "Moves the open module to `modules/.trash/`, where it can be recovered; it warns first if other modules import it. The editor keeps the text, unsaved.",
      },
      { syntax: "?  or  F1", text: "Opens this help (when the editor does not have the focus); `Esc` closes it." },
      {
        syntax: "Dims | Units",
        text: "Shows results in dimensions or in units. Units appear where they are known: with `import SI` or your own `unit` declarations.",
      },
      {
        syntax: "dx/dt  |  ẋ  |  x′",
        tex: r`\frac{\mathrm{d}^{2} x}{\mathrm{d} t^{2}} \quad \ddot{x} \quad x''`,
        text: "How derivatives are written: Leibniz, Newton's dots (only for derivatives by a variable of dimension T; others stay $\mathrm{d}y/\mathrm{d}x$) or primes. Partial derivatives are always $\partial u/\partial x$.",
      },
      {
        syntax: "L/T  |  L·T⁻¹",
        tex: r`\mathsf{M\,L/T^{2}} \quad\text{or}\quad \mathsf{M\,L\,T^{-2}}`,
        text: "The switch in the top bar writes dimensions as fractions or with negative powers. Both mean the same, and you can type either: `L/T`, `L*T^-1` and `T^(-1)*L` are equal.",
      },
      { syntax: "Draft", text: "What you type is kept in this browser between visits, even unsaved, and so are the display settings." },
    ],
  },
];
