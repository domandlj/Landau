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
    if isinstance(e, sp.Subs):
        out = t(e.expr)
        for v, p in zip(e.variables, e.point):
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
    """Plain symbols first, then the variables that depend on them: x(t)."""
    syms = {}
    for name, flags in spec.items():
        if "deps" not in flags:
            syms[name] = sp.Symbol(name, **flags)
    for name, flags in spec.items():
        if "deps" in flags:
            flags = dict(flags)
            deps = [syms[d] for d in flags.pop("deps")]
            syms[name] = sp.Function(name, **flags)(*deps)
    funcs = {n: syms[n].args for n, f in spec.items() if "deps" in f}
    return syms, funcs


def handle(req):
    syms, funcs = make_symbols(req["syms"])
    if req["op"] == "simplify":
        return [to_json(sp.simplify(from_json(req["expr"], syms)), funcs)]
    if req["op"] == "solve":
        lhs = from_json(req["lhs"], syms)
        rhs = from_json(req["rhs"], syms)
        return [to_json(s, funcs) for s in sp.solve(lhs - rhs, syms[req["for"]])]
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


def main():
    for line in sys.stdin:
        try:
            reply = {"ok": handle(json.loads(line))}
        except Exception as e:  # report every failure back to Landau
            reply = {"error": f"{type(e).__name__}: {e}"}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
