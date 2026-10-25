"""SymPy worker for Landau.

Reads one JSON request per line on stdin and answers one JSON line on
stdout: {"ok": [expr, ...]} or {"error": "message"}.

Expressions are JSON trees:
  {"num": "3/2"}  {"sym": "s0"}  {"const": "pi" | "I" | "E" | "oo"}
  {"add": [...]}  {"mul": [...]}  {"pow": [base, exp]}
  {"fn": "sin", "args": [...]}
"""

import json
import sys
from decimal import ROUND_HALF_UP, Decimal, localcontext

import sympy as sp
from sympy.calculus.euler import euler_equations

FUNCS = {
    "sin": sp.sin, "cos": sp.cos, "tan": sp.tan,
    "asin": sp.asin, "acos": sp.acos, "atan": sp.atan, "atan2": sp.atan2,
    "sinh": sp.sinh, "cosh": sp.cosh, "tanh": sp.tanh,
    "exp": sp.exp, "log": sp.log, "sqrt": sp.sqrt,
    "abs": sp.Abs, "conj": sp.conjugate,
}
# sqrt is not a class in SymPy (it becomes a power), so it has no reverse entry.
NAMES = {f: name for name, f in FUNCS.items() if name != "sqrt"}
CONSTS = {"pi": sp.pi, "I": sp.I, "E": sp.E, "oo": sp.oo}


def holds(c):
    """True or False when the condition is decided, else None. exp(-b) < 1
    for b > 0 is decided by comparing logarithms: -b < 0."""
    if c in (sp.true, sp.false):
        return bool(c)
    if isinstance(c, (sp.StrictLessThan, sp.LessThan, sp.StrictGreaterThan, sp.GreaterThan)):
        small, big = (c.lhs, c.rhs) if isinstance(c, (sp.StrictLessThan, sp.LessThan)) else (c.rhs, c.lhs)
        for d in (small - big, sp.log(small) - sp.log(big) if small.is_positive and big.is_positive else None):
            if d is not None and d.is_negative:
                return True
            if d is not None and d.is_positive:
                return False
    return None


def summation(f, k, a, b):
    """SymPy's summation, with two helps. exp(c*k + d) is summed as the
    geometric series exp(d)*w**k, w = exp(c), which SymPy 1.14 misses. And a
    case split (r = 1 or not, |w| < 1 or not) is resolved when the conditions
    can be decided; otherwise the sum is left as it is, since Landau cannot
    write cases."""
    ws = {}

    def geometric(e):
        x = sp.expand(e.args[0])
        c = x.coeff(k)
        rest = sp.expand(x - c * k)
        if c == 0 or rest.has(k):
            return e
        w = sp.Dummy("w", positive=True) if c.is_real else sp.Dummy("w")
        ws[w] = sp.exp(c)
        return sp.exp(rest) * w**k

    g = f.replace(lambda e: isinstance(e, sp.exp) and e.args[0].has(k), geometric)
    s = sp.summation(g, (k, a, b)).subs(ws)
    undecided = []

    def resolve(p):
        for value, cond in p.args:
            decided = holds(cond)
            if decided:
                return value
            if decided is None:
                break
        undecided.append(p)
        return p

    # the case split may sit inside a product: exp(-b/2)*Piecewise(...)
    s = s.replace(lambda e: isinstance(e, sp.Piecewise), resolve)
    if undecided:
        return sp.Sum(f, (k, a, b))
    # zeta(3) or harmonic(N): functions Landau has no name for
    unknown = [e for e in s.atoms(sp.Function) if e.func not in NAMES and not isinstance(e.func, sp.core.function.UndefinedFunction)]
    return sp.Sum(f, (k, a, b)) if unknown else s


def from_json(j, syms):
    if "num" in j:
        return sp.Rational(j["num"])
    if "sym" in j:
        return syms[j["sym"]]
    if "const" in j:
        return CONSTS[j["const"]]
    if "add" in j:
        return sp.Add(*[from_json(t, syms) for t in j["add"]])
    if "mul" in j:
        return sp.Mul(*[from_json(t, syms) for t in j["mul"]])
    if "pow" in j:
        b, e = j["pow"]
        return sp.Pow(from_json(b, syms), from_json(e, syms))
    if "eval" in j:
        # a variable at a point: x(0)
        return syms[j["eval"]].func(*[from_json(a, syms) for a in j["args"]])
    if "fn" in j:
        args = [from_json(a, syms) for a in j["args"]]
        if j["fn"] == "diff":
            return sp.diff(*args)
        if j["fn"] == "integral":
            f, x, *bounds = args
            return sp.integrate(f, (x, *bounds) if bounds else x)
        if j["fn"] == "sum":
            # the index counts: an integer of its own, whatever the name
            # means outside the sum
            f, k, a, b = args
            n = sp.Symbol(k.name, integer=True)
            return summation(f.subs(k, n), n, a, b)
        if j["fn"] == "at":
            e, x, a = args
            return e.subs(x, a)
        # Vector operators (dot, curl, ...) stay opaque: SymPy only moves them around.
        f = FUNCS.get(j["fn"]) or sp.Function(j["fn"])
        return f(*args)
    raise ValueError(f"bad term {j}")


def to_json(e, funcs={}):
    """funcs: the variables that are functions, like x(t), with their arguments."""
    def t(a):
        return to_json(a, funcs)
    if e.is_Symbol:
        return {"sym": e.name}
    if isinstance(e.func, sp.core.function.UndefinedFunction) and e.func.__name__ in funcs:
        name = e.func.__name__
        if tuple(e.args) == funcs[name]:
            return {"sym": name}
        return {"eval": name, "args": [t(a) for a in e.args]}  # x(0)
    if isinstance(e, sp.Integral):
        out = t(e.function)
        for lim in e.limits:
            out = {"fn": "integral", "args": [out] + [t(a) for a in lim]}
        return out
    if isinstance(e, sp.Sum):
        out = t(e.function)
        for lim in e.limits:
            out = {"fn": "sum", "args": [out] + [t(a) for a in lim]}
        return out
    if isinstance(e, sp.Subs):
        # h'(θ) at θ = ω*t: SymPy writes the derivative with a dummy (_xi)
        # in place of θ; put back the argument h was declared with
        expr, variables = e.expr, list(e.variables)
        own = {}
        for f in expr.atoms(sp.core.function.AppliedUndef):
            for a, arg in zip(f.args, funcs.get(f.func.__name__, ())):
                if a in variables:
                    own[a] = arg
        if own:
            expr = expr.subs(own)
            variables = [own.get(v, v) for v in variables]
        out = t(expr)
        for v, p in zip(variables, e.point):
            out = {"fn": "at", "args": [out, t(v), t(p)]}
        return out
    if isinstance(e, sp.Derivative):
        out = t(e.expr)
        for v, n in e.variable_count:
            for _ in range(n):
                out = {"fn": "diff", "args": [out, t(v)]}
        return out
    if e is sp.S.NegativeInfinity:
        return {"mul": [{"num": "-1"}, {"const": "oo"}]}
    if e is sp.S.ComplexInfinity or e is sp.nan:
        raise ValueError(f"the result is {e}: the expression is undefined or diverges")
    for name, c in CONSTS.items():
        if e is c:
            return {"const": name}
    if e.is_Rational:
        return {"num": str(e)}
    if e.is_Float:
        return {"num": str(sp.nsimplify(e, rational=True))}
    if e.is_Add:
        return {"add": [t(a) for a in e.args]}
    if e.is_Mul:
        return {"mul": [t(a) for a in e.args]}
    if e.is_Pow:
        return {"pow": [t(e.base), t(e.exp)]}
    if e.func in NAMES:
        return {"fn": NAMES[e.func], "args": [t(a) for a in e.args]}
    if isinstance(e.func, sp.core.function.UndefinedFunction):
        return {"fn": e.func.__name__, "args": [t(a) for a in e.args]}
    raise ValueError(f"cannot translate {e} back to Landau")


# ---- numerical integration ----


def simulate(req, syms):
    """Reduce the ODEs to a first-order system and integrate it."""
    t = syms[req["t"]]
    funcs = [syms[x] for x in req["for"]]
    eqs = [from_json(e, syms) for e in req["eqs"]]
    stray = set().union(*(e.free_symbols for e in eqs)) - {t}
    if stray:
        raise ValueError("these still need values: " + ", ".join(sorted(map(str, stray))))
    # each unknown's highest derivative, which the equations are solved for
    order = {f: max([d.derivative_count for e in eqs for d in e.atoms(sp.Derivative) if d.expr == f] or [0]) for f in funcs}
    for x, f in zip(req["for"], funcs):
        if order[f] == 0:
            raise ValueError(f"{x} is never differentiated, so it is not an unknown of the differential equations")
    tops = [sp.Derivative(f, (t, order[f])) for f in funcs]
    sols = sp.solve(eqs, tops, dict=True)
    if not sols:
        raise ValueError("the equations cannot be solved for the highest derivatives")
    top = sols[0]
    # state variables: each unknown and its derivatives below the highest
    state = {(f, k): sp.Symbol(f"y{i}_{k}") for i, f in enumerate(funcs) for k in range(order[f])}
    def to_state(e):
        for f in funcs:
            for k in range(order[f] - 1, 0, -1):
                e = e.xreplace({sp.Derivative(f, (t, k)): state[(f, k)]})
            e = e.xreplace({f: state[(f, 0)]})
        return e
    names = [state[key] for key in state]
    rhs = []
    for f in funcs:
        for k in range(order[f]):
            rhs.append(state[(f, k + 1)] if k + 1 < order[f] else to_state(top[tops[funcs.index(f)]]))
    if any(e.has(sp.Derivative) or (e.free_symbols - {t} - set(names)) for e in rhs):
        raise ValueError("the equations could not be put in first-order form")
    try:
        from scipy.integrate import solve_ivp
    except ImportError:
        raise ValueError("simulate needs SciPy: run .venv/bin/pip install scipy")
    fn = sp.lambdify([t] + names, rhs, modules="numpy")
    f = lambda tt, y: fn(tt, *y)
    # initial values: x(t0), x'(t0), ... for each unknown
    # numbers come exact from Landau, as "6/5" or "1.5e11"
    num = lambda v: float(sp.Rational(v))
    given = {(req["for"].index(ic["var"]), ic["order"]): num(ic["value"]) for ic in req["ics"]}
    missing = [
        req["for"][i] + "'" * k + "(t0)" for i, fn_ in enumerate(funcs) for k in range(order[fn_]) if (i, k) not in given
    ]
    if missing:
        raise ValueError("initial values are needed for " + ", ".join(missing))
    extra = [req["for"][i] + "'" * k for (i, k) in given if k >= order[funcs[i]]]
    if extra:
        raise ValueError("these initial values are not needed: " + ", ".join(extra))
    y0 = [given[(i, k)] for i, fn_ in enumerate(funcs) for k in range(order[fn_])]
    t0, t1, n = num(req["t0"]), num(req["t1"]), req["points"]
    times = [t0 + (t1 - t0) * i / (n - 1) for i in range(n)]
    # Quantities are in base units, so their sizes vary wildly (1e-19 C,
    # 1e11 m): give each component an absolute tolerance from its own size.
    big = max([abs(v) for v in y0] + [1e-300])
    atol = [1e-10 * (abs(v) or big) for v in y0]
    # DOP853 for accuracy; Radau if the system turns out to be stiff
    for method in ("DOP853", "Radau"):
        sol = solve_ivp(f, (t0, t1), y0, method=method, t_eval=times, rtol=1e-9, atol=atol)
        if sol.success:
            break
    else:
        raise ValueError(f"the integration failed: {sol.message}")
    # only the unknowns themselves, not their derivatives
    first = [sum(order[g] for g in funcs[:i]) for i in range(len(funcs))]
    return {
        "t": times,
        "series": [[float(v) for v in sol.y[j]] for j in first],
        "steps": int(sol.nfev),
        "method": method,
    }


def make_symbols(spec):
    """Plain symbols first, then the variables that depend on them: x(t), and
    x(θ(t)) once θ(t) is made, so that diff(x, t) follows the chain rule."""
    syms = {}
    for name, flags in spec.items():
        if "deps" not in flags:
            syms[name] = sp.Symbol(name, **flags)
    waiting = {n: f for n, f in spec.items() if "deps" in f}
    while waiting:
        ready = [n for n, f in waiting.items() if all(d in syms for d in f["deps"])]
        if not ready:
            raise ValueError("the variables' dependencies go in a circle: " + ", ".join(waiting))
        for name in ready:
            flags = dict(waiting.pop(name))
            deps = [syms[d] for d in flags.pop("deps")]
            syms[name] = sp.Function(name, **flags)(*deps)
    funcs = {n: syms[n].args for n, f in spec.items() if "deps" in f}
    return syms, funcs


def hidden_sums(e):
    """The expression with each sum that is left (one summation could not
    close) replaced by a symbol, and the way back. simplify and solve would
    otherwise evaluate it again, into a case split or a function Landau
    cannot write."""
    back = {}
    for t in e.atoms(sp.Sum):
        d = sp.Dummy("sum", real=True) if t.is_real else sp.Dummy("sum")
        back[d] = t
    return e.subs({t: d for d, t in back.items()}), back


def handle(req):
    syms, funcs = make_symbols(req["syms"])
    if req["op"] == "simplify":
        e, back = hidden_sums(from_json(req["expr"], syms))
        return [to_json(sp.simplify(e).subs(back), funcs)]
    if req["op"] == "solve":
        e, back = hidden_sums(from_json(req["lhs"], syms) - from_json(req["rhs"], syms))
        return [to_json(s.subs(back), funcs) for s in sp.solve(e, syms[req["for"]])]
    if req["op"] == "solve_system":
        # every solution set, with each unknown's value or None when the
        # equations leave it free
        eqs = [from_json(l, syms) - from_json(r, syms) for l, r in req["eqs"]]
        unknowns = [syms[v] for v in req["for"]]
        sets = sp.solve(eqs, unknowns, dict=True)
        return [[to_json(sp.simplify(s[x]), funcs) if x in s else None for x in unknowns] for s in sets]
    if req["op"] == "evaluate":
        # A number with the requested significant figures, as a decimal string.
        # sp.N(e, 3) computes with 3 digits of precision and can round wrongly
        # (6864.655 -> 6.87e3), so compute precisely, then round in decimal.
        v = sp.N(from_json(req["expr"], syms), req["digits"] + 20)
        if v.free_symbols:
            raise ValueError("the expression still has unknowns: " + ", ".join(sorted(map(str, v.free_symbols))))
        if not v.is_real:
            if v.is_finite is False:
                raise ValueError("the value is infinite or undefined")
            raise ValueError(f"the value {v} is not a real number")
        with localcontext() as ctx:
            ctx.prec = req["digits"]
            ctx.rounding = ROUND_HALF_UP
            return [str(+Decimal(str(v)))]
    if req["op"] == "series":
        # The expansion in the bookkeeping symbol to the given order, with that
        # symbol then set to 1, and the first term left out (None if none is
        # found in the next few orders).
        e, eps, n = from_json(req["expr"], syms), syms[req["eps"]], req["order"]
        kept = sp.series(e, eps, 0, n + 1).removeO()
        more = sp.expand(sp.series(e, eps, 0, n + 6).removeO() - kept)
        nxt = next((more.coeff(eps, k) for k in range(n + 1, n + 6) if more.coeff(eps, k) != 0), None)
        # expanded, term by term: m*c^2 + m*v^2/2 shows the series
        return [to_json(sp.expand(kept.subs(eps, 1)), funcs), None if nxt is None else to_json(sp.simplify(nxt), funcs)]
    if req["op"] == "limit":
        e = from_json(req["expr"], syms)
        v = sp.limit(e, syms[req["var"]], from_json(req["point"], syms))
        if v.has(sp.Limit):
            raise ValueError("SymPy could not find this limit")
        if v.has(sp.zoo) or v.has(sp.nan):
            raise ValueError(f"the limit is undefined ({v})")
        return [to_json(v, funcs)]
    if req["op"] == "euler_lagrange":
        # SymPy gives ∂L/∂x - d/dt ∂L/∂ẋ = 0; the usual sign is the other one
        L = from_json(req["expr"], syms)
        (eq,) = euler_equations(L, [syms[req["for"]]], [syms[req["by"]]])
        return [to_json(-eq.lhs, funcs)]
    if req["op"] == "conserved":
        # Noether: for the time t, the energy Σ ẋ ∂L/∂ẋ - L, conserved when
        # ∂L/∂t = 0; for a coordinate x, the momentum ∂L/∂ẋ, conserved when
        # ∂L/∂x = 0. The reply is that derivative of L, then the quantity.
        L = from_json(req["expr"], syms)
        t = syms[req["by"]]
        coords = [syms[c] for c in req["coords"]]
        if req["for"] == req["by"]:
            # hold the coordinates and velocities still to see t on its own
            held = {sp.diff(q, t): sp.Dummy() for q in coords}
            held.update({q: sp.Dummy() for q in coords})
            back = {v: k for k, v in held.items()}
            partial = sp.diff(L.subs(held), t).subs(back)
            quantity = sum(sp.diff(q, t) * sp.diff(L, sp.diff(q, t)) for q in coords) - L
        else:
            q = syms[req["for"]]
            partial = sp.diff(L, q)
            quantity = sp.diff(L, sp.diff(q, t))
        return [to_json(sp.simplify(partial), funcs), to_json(sp.expand(quantity), funcs)]
    if req["op"] == "simulate":
        return [simulate(req, syms)]
    if req["op"] == "nsolve":
        e = from_json(req["expr"], syms)
        x = syms[req["for"]]
        stray = e.free_symbols - {x}
        if stray:
            raise ValueError("these still need values: " + ", ".join(sorted(map(str, stray))))
        guess = from_json(req["guess"], syms)
        try:
            root = sp.nsolve(e, x, guess, prec=30)
        except (ValueError, ZeroDivisionError) as err:
            raise ValueError(f"no root was found near {sp.N(guess, 6)}: {err}")
        if not root.is_real:
            raise ValueError(f"the root found, {sp.N(root, 6)}, is not real")
        return [str(sp.Float(root, 30))]
    if req["op"] == "matrix":
        # det, inv and eigen of matrices given entry by entry; Landau keeps
        # matrices out of SymPy otherwise, since its symbols commute and
        # A*B - B*A would come out 0
        ms = [sp.Matrix([[from_json(x, syms) for x in row] for row in m]) for m in req["matrices"]]
        a = ms[0]
        if req["fn"] == "det":
            return [to_json(sp.factor(sp.simplify(a.det())), funcs)]
        if req["fn"] == "inv":
            if sp.simplify(a.det()) == 0:
                raise ValueError("the matrix has determinant 0, so it has no inverse")
            return [[[to_json(sp.simplify(x), funcs) for x in row] for row in a.inv().tolist()]]
        if req["fn"] == "eigen":
            # K v = λ M v when a second matrix is given: M^-1 K v = λ v
            if len(ms) > 1:
                if sp.simplify(ms[1].det()) == 0:
                    raise ValueError("the second matrix has determinant 0")
                a = ms[1].inv() * a
            out = []
            for value, mult, vectors in a.eigenvects(simplify=True):
                vs = []
                for v in vectors:
                    v = sp.simplify(v)
                    # scaled so that its first nonzero entry is 1
                    first = next((x for x in v if x != 0), 1)
                    vs.append([to_json(sp.simplify(x / first), funcs) for x in v])
                out.append([to_json(sp.simplify(value), funcs), mult, vs])
            return [out]
        raise ValueError(f"unknown matrix function {req['fn']}")
    if req["op"] == "nullspace":
        # A basis of the exponent vectors that make a product dimensionless:
        # the rows are base dimensions, the columns variables. SymPy's basis
        # comes from the reduced row echelon form, so each vector has a 1 at
        # its own free column and 0 at the other free columns.
        rows = [[sp.Rational(x) for x in row] for row in req["matrix"]]
        m = sp.Matrix(rows) if rows else sp.zeros(1, req["cols"])
        return [[str(x) for x in v] for v in m.nullspace()]
    if req["op"] == "dsolve":
        eq = sp.Eq(from_json(req["lhs"], syms), from_json(req["rhs"], syms))
        ics = {from_json(l, syms): from_json(r, syms) for l, r in req["ics"]}
        sols = sp.dsolve(eq, syms[req["for"]], ics=ics or None)
        return [to_json(s.rhs, funcs) for s in (sols if isinstance(sols, list) else [sols])]
    raise ValueError(f"unknown op {req['op']}")


def answer(line):
    """The reply line to one request line (Pyodide calls this directly)."""
    try:
        reply = {"ok": handle(json.loads(line))}
    except Exception as e:  # report every failure back to Landau
        reply = {"error": f"{type(e).__name__}: {e}"}
    return json.dumps(reply)


def main():
    for line in sys.stdin:
        sys.stdout.write(answer(line) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
