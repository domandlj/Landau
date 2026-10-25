Derivatives, differential equations, approximations and limits, and the
wave and continuity equations from Maxwell's equations.

  $ landau -v cases/calculus/derivatives.lan
  theory Motion
    dim L, T
    var t : T
    var x(t) : L
    var v(t) : L/T
    var a(t) : L/T^2
    var x0 : L
    var v0 : L/T
    var g : L/T^2, positive
    law position : x = x0 + v0*t - g*t^2/2   [L]
    law velocity : v = diff(x, t)   [L/T]
    law accel : a = diff(v, t)   [L/T^2]
    derive speed : v = v0 - t*g   [L/T]
        from    Motion.position, Motion.velocity
        assumes g > 0
        via     subst, simplify
          s := v = diff(x0 + v0*t - g*t^2/2, t)
          v = v0 - t*g
    derive acceleration : a = -g   [L/T^2]
        from    Motion.position, Motion.velocity, Motion.accel
        assumes g > 0
        via     subst, simplify
          s := a = diff(v0 - t*g, t)
          a = -g
    derive d2 : diff(diff(x, t), t) = -g   [L/T^2]
        from    Motion.position
        assumes g > 0
        via     differentiate by t, differentiate by t, simplify
          p := diff(x, t) = diff(x0 + v0*t - g*t^2/2, t)
          q := diff(diff(x, t), t) = diff(diff(x0 + v0*t - g*t^2/2, t), t)
          diff(diff(x, t), t) = -g
    derive top_time : t = v0/g   [T]
        from    Motion.position, Motion.velocity
        assumes g > 0
        via     instantiate, solve for t
          s := 0 = v0 - t*g
          t = v0/g
  
  theory Identities
    dim L
    var r : L, position
    var f(r) : L
    var F(r) : L, vector
    law curl_grad : curl(grad(f)) = 0   [3-vector 1/L]
    law div_curl : div(curl(F)) = 0   [1/L]
    derive check1 : 0 = 0   [any]   (holds identically)
        from    Identities.curl_grad
        via     expand, simplify
          e := vec(diff(diff(f, r.z), r.y) - diff(diff(f, r.y), r.z), diff(diff(f, r.x), r.z) - diff(diff(f, r.z), r.x), diff(diff(f, r.y), r.x) - diff(diff(f, r.x), r.y)) = 0
          0 = 0
    derive check2 : 0 = 0   [any]   (holds identically)
        from    Identities.div_curl
        via     expand, simplify
          e := diff(diff(F.z, r.y) - diff(F.y, r.z), r.x) + diff(diff(F.x, r.z) - diff(F.z, r.x), r.y) + diff(diff(F.y, r.x) - diff(F.x, r.y), r.z) = 0
          0 = 0
  
  theory Bad
    dim L, T
    var t : T
    var x : L
    var y(t) : L
  cases/calculus/derivatives.lan:56: error: `diff(x, t)` is always 0, because `x` does not depend on `t`; declare the dependence, e.g. `var x(t) : ...`
  
  [1]

  $ landau cases/calculus/odes.lan
  theory RC
    import SI
    var t : s   [T], positive
    var q(t) : C   [T*I]
    var R : Ω   [M*L^2/(T^3*I^2)], positive
    var Cap : F   [T^4*I^2/(M*L^2)], positive
    var Q0 : C   [T*I], positive
    law discharge : R*diff(q, t) + q/Cap = 0   [M*L^2/(T^3*I)]
    derive charge : q = Q0*exp(-t/(R*Cap))   [T*I]
        from    RC.discharge
        assumes R > 0, t > 0, Cap > 0
        via     solve for q with initial conditions
  
  theory Damped
    import SI
    var t : s   [T], positive
    var x(t) : m   [L]
    var m : kg   [M], positive
    var k : N/m   [M/T^2], positive
    var b : kg/s   [M/T], positive
    var x0 : m   [L]
    law motion : m*diff(diff(x, t), t) = -k*x - b*diff(x, t)   [M*L/T^2]
    derive general : x = C1*exp(t*(sqrt(b^2 - 4*m*k) - b)/(2*m)) + C2*exp(-t*(b + sqrt(b^2 - 4*m*k))/(2*m))   [L]
        from    Damped.motion
        assumes m > 0, t > 0, k > 0, b > 0
        constants C1 [L], C2 [L]
        via     solve for x
  
  theory Drag
    import SI
    var t : s   [T], positive
    var v(t) : m/s   [L/T]
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var b : kg/s   [M/T], positive
    law falling : m*diff(v, t) = m*g - b*v   [M*L/T^2]
    derive speed : v = m*g/b - m*g*exp(-t*b/m)/b   [L/T]
        from    Drag.falling
        assumes m > 0, t > 0, g > 0, b > 0
        via     solve for v with initial conditions
  

  $ landau -v cases/calculus/ode_and_integrals.lan
  theory Fall
    dim M, L, T
    var t, T1 : T, positive
    var x(t) : L
    var v(t) : L/T
    var g : L/T^2, positive
    var x0 : L
    var v0 : L/T
    var ω : 1/T, positive
    var W : L^2/T
    law newton : diff(diff(x, t), t) = -g   [L/T^2]
    law spring : diff(diff(x, t), t) = -ω^2*x   [L/T^2]
    law velocity : v = diff(x, t)   [L/T]
    law area : W = integral(v0 - g*t, t, 0, T1)*v0   [L^2/T]
    derive general : x = C1 + C2*t - g*t^2/2   [L]
        from    Fall.newton
        assumes t > 0, g > 0
        constants C1 [L], C2 [L/T]
        via     solve for x
          x = C1 + C2*t - g*t^2/2
    derive thrown : x = x0 + v0*t - g*t^2/2   [L]
        from    Fall.newton
        assumes t > 0, g > 0
        via     solve for x with initial conditions
          x = x0 + v0*t - g*t^2/2
    derive oscillator : x = x0*cos(t*ω)   [L]
        from    Fall.spring
        assumes t > 0, ω > 0
        via     solve for x with initial conditions
          x = x0*cos(t*ω)
    derive area_eval : W = v0*T1*(2*v0 - g*T1)/2   [L^2/T]
        from    Fall.area
        assumes g > 0, t > 0, T1 > 0
        via     simplify
          W = v0*T1*(2*v0 - g*T1)/2
    derive displacement : integral(v, t, 0, T1) = -x(0) + x(T1)   [L]
        from    Fall.velocity
        assumes t > 0, T1 > 0
        via     integrate by t from 0 to T1, simplify
          i := integral(v, t, 0, T1) = integral(diff(x, t), t, 0, T1)
          integral(v, t, 0, T1) = -x(0) + x(T1)
    derive antiderivative : 0 = -g   [L/T^2]
        from    Fall.newton
        assumes t > 0, g > 0
        via     simplify
          0 = -g
  

  $ landau cases/calculus/errors.lan
    dim L, T
    var t, T1 : T
    var x(t) : L
    var y : L
    var g : L/T^2
    law a : diff(diff(x, t), t) = -g   [L/T^2]
  cases/calculus/errors.lan:7: error: the bound `y` of `integral` is [L], but the variable is [T]
  cases/calculus/errors.lan:8: error: `x` depends on 1 variable(s), so `x(0, 1)` needs 1 argument(s)
  cases/calculus/errors.lan:9: error: in `x(y)`, `y` is [L] but stands for `t`, which is [T]
  cases/calculus/errors.lan:10: error: `y` is [L], but it is put in place of a variable that is [T]
    law f : y = integral(x, y)*0   [L]
    law ok : y = g*t^2   [L]
  cases/calculus/errors.lan:14: error: initial conditions apply only to a differential equation in `y`
    derive e2 : y = g*(3*T1)^2   [L]
        from    Main.ok
        via     instantiate
  cases/calculus/errors.lan:20: error: cannot replace `t` in `diff(diff(x, t), t)`: it is the variable being differentiated
  cases/calculus/errors.lan:23: error: `apply` needs a function of one argument such as curl, div, grad, lap or sqrt; `atan2` is not one
  cases/calculus/errors.lan:26: error: neither `diff(diff(x, t), t)` nor `-g` appears in `y = g*t^2`
  cases/calculus/errors.lan:29: error: the two sides have different dimensions: `x(0)` is [L] but `g` is [L/T^2]
  [1]

  $ landau cases/calculus/bound_variables.lan
    dim L, T
    var x : L
    var t, t0 : T
    var v : L/T
  cases/calculus/bound_variables.lan:5: error: `diff(x, t)` is always 0, because `x` does not depend on `t`; declare the dependence, e.g. `var x(t) : ...`
    def rate : ('a, 'b) -> 'a/'b
  cases/calculus/bound_variables.lan:7: error: `diff(x, t)` is always 0, because `x` does not depend on `t`; declare the dependence, e.g. `var x(t) : ...`
  cases/calculus/bound_variables.lan:9: error: unknown law `vel`
  cases/calculus/bound_variables.lan:12: error: unknown law `vel`
  [1]

  $ landau cases/calculus/product_rule.lan
    dim M, L, T
    var t : T
    var v(t) : L/T, vector
    var m : M, positive
    var P(t) : M*L^2/T^3
    law power : P = diff(m*dot(v, v)/2, t)   [M*L^2/T^3]
    derive p : P = m*(diff(v.x, t)*v.x + diff(v.y, t)*v.y + diff(v.z, t)*v.z)   [M*L^2/T^3]
        from    Main.power
        assumes m > 0
        via     simplify

  $ landau -v cases/calculus/approximations.lan
  theory Relativity
    import SI
    var m : kg   [M], positive
    var v, c : m/s   [L/T], positive
    var E : J   [M*L^2/T^2]
    law energy : E = m*c^2/sqrt(1 - v^2/c^2)   [M*L^2/T^2]
    derive classical : E = m*c^2 + m*v^2/2   [M*L^2/T^2]
        from    Relativity.energy
        assumes v ≪ c (to order 2); left out: 3*m*v^4/(8*c^2)
        via     approximate (v ≪ c, order 2)
          E = m*c^2 + m*v^2/2
  
  theory Pendulum
    import SI
    var t : s   [T], positive
    var θ(t) : 1
    var g : m/s^2   [L/T^2], positive
    var L : m   [L], positive
    var θ0 : 1, positive
    law exact : diff(diff(θ, t), t) = -g/L*sin(θ)   [1/T^2]
    derive small : diff(diff(θ, t), t) = -g*θ/L   [1/T^2]
        from    Pendulum.exact
        assumes θ ≪ 1 (to order 1); left out: g*θ^3/(6*L)
        via     approximate (θ ≪ 1, order 1)
          diff(diff(θ, t), t) = -g*θ/L
    derive swing : θ = θ0*cos(t*sqrt(g)/sqrt(L))   [1]
        from    Pendulum.exact
        assumes θ ≪ 1 (to order 1); left out: g*θ^3/(6*L), t > 0, g > 0, L > 0
        via     approximate (θ ≪ 1, order 1), solve for θ with initial conditions
          s := diff(diff(θ, t), t) = -g*θ/L
          θ = θ0*cos(t*sqrt(g)/sqrt(L))
  
  theory Height
    import Constants
    var M : kg   [M], positive
    var R, z : m   [L], positive
    var gh : m/s^2   [L/T^2]
    law gravity : gh = G*M/(R + z)^2   [L/T^2]
    derive near_surface : gh = G*M/R^2 - 2*G*M*z/R^3   [L/T^2]
        from    Height.gravity
        assumes z ≪ R (to order 1); left out: 3*G*M*z^2/R^4
        via     approximate (z ≪ R, order 1)
          gh = G*M/R^2 - 2*G*M*z/R^3
  
  theory Terminal
    import SI
    var t : s   [T], positive
    var v(t) : m/s   [L/T]
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var b : kg/s   [M/T], positive
    law falling : m*diff(v, t) = m*g - b*v   [M*L/T^2]
    derive terminal : v(inf) = m*g/b   [L/T]
        from    Terminal.falling
        assumes m > 0, t > 0, g > 0, b > 0, t → inf
        via     solve for v with initial conditions, limit t → inf
          s := v = m*g/b - m*g*exp(-t*b/m)/b
          v(inf) = m*g/b
  
  theory Bad
    import SI
    var v, c : m/s   [L/T]
    var x : m   [L]
    var E : J   [M*L^2/T^2]
    var F : N   [M*L/T^2], vector
    law e1 : E = 1/(1 - v/c)*(1 [J])   [M*L^2/T^2]
  cases/calculus/approximations.lan:62: error: `v << 1` compares [L/T] with [1]: a small quantity is small compared with something of the same dimension, as in v << c
  cases/calculus/approximations.lan:65: error: in `v << 2*v`, the scale cannot depend on `v`
  cases/calculus/approximations.lan:68: error: `F` is a vector; say which component is small, or use its norm
  cases/calculus/approximations.lan:71: error: the two sides have different dimensions: `v` is [L/T] but `3 [m]` is [L]
  cases/calculus/approximations.lan:74: error: the order must be between 0 and 20
  
  [1]

  $ landau cases/calculus/maxwell_wave.lan
  theory M
    dim M, L, T, I
    var r : L, position
    var t : T
    var E(r, t) : M*L/(T^3*I), vector
    var B(r, t) : M/(T^2*I), vector
    var J(r, t) : I/L^2, vector
    var ρ(r, t) : T*I/L^3
    var ε0 : T^4*I^2/(M*L^3), positive
    var μ0 : M*L/(T^2*I^2), positive
    law gauss : div(E) = ρ/ε0   [M/(T^3*I)]
    law faraday : curl(E) = -diff(B, t)   [3-vector M/(T^3*I)]
    law ampere : curl(B) = μ0*J + μ0*ε0*diff(E, t)   [3-vector M/(L*T^2*I)]
    law curl_curl : curl(curl(E)) = grad(div(E)) - lap(E)   [3-vector M/(L*T^3*I)]
    derive check_identity : 0 = 0   [any]   (holds identically)
        from    M.curl_curl
        via     expand, simplify
    derive continuity : 0 = μ0*(diff(ρ, t) + div(J))   [M/(L^2*T^2*I)]
        from    M.gauss, M.ampere
        assumes μ0 > 0, ε0 > 0
        via     apply div, subst, simplify
    derive wave : lap(E) = μ0*ε0*diff(diff(E, t), t)   [3-vector M/(L*T^3*I)]
        from    M.gauss, M.curl_curl, M.ampere, M.faraday
        assumes μ0 > 0, ε0 > 0
        via     apply curl, subst, subst, subst, simplify
  

Sums and integers: closed forms, sums left as they are (a case split, or no
closed form), a counter that is the sum's own (the theory's k is a length),
and the integer attribute.

  $ landau -v cases/calculus/sums.lan
  theory Sums
    dim L
    var S, x : L
    var r, N, A, B, C, D : 1
    var k : L
    law gauss : A = sum(k, k, 1, N)   [1]
    law geometric : B = sum(r^k, k, 0, N)   [1]
    law zeta3 : C = sum(1/k^3, k, 1, inf)   [1]
    law lengths : S = sum(x/k^2, k, 1, inf)   [L]
    law half : D = sum(1/2^k, k, 1, inf)   [1]
    derive g : A = N*(1 + N)/2   [1]
        from    Sums.gauss
        via     simplify
          A = N*(1 + N)/2
    derive geo : B = sum(r^k, k, 0, N)   [1]
        from    Sums.geometric
        via     simplify
          B = sum(r^k, k, 0, N)
    derive z : C = sum(1/k^3, k, 1, inf)   [1]
        from    Sums.zeta3
        via     simplify
          C = sum(1/k^3, k, 1, inf)
    derive l : S = x*pi^2/6   [L]
        from    Sums.lengths
        via     simplify
          S = x*pi^2/6
    derive h : D = 1   [1]
        from    Sums.half
        via     simplify
          D = 1
    derive renamed : A = sum(k, k, 1, N)   [1]
        from    Sums.gauss
        via     instantiate
          s := A = sum(k, k, 1, N)
    compute sum(1/k^3, k, 1, inf) = 1.2020569   [1]
    compute sum(1/(k*(k + 1)), k, 1, 100) = 0.990099   [1]
  
  theory Errors
    dim L
    var S, x : L
  cases/calculus/sums.lan:38: error: the bound `x` of `sum` must be dimensionless, but it is [L]
  cases/calculus/sums.lan:39: error: `sum` counts with a name, as in sum(1/n^2, n, 1, inf), but got `2*k`
  cases/calculus/sums.lan:40: error: `sum` takes 4 arguments (f, n, a, b), but got 3
  cases/calculus/sums.lan:41: error: the two sides have different dimensions: `S` is [L] but `sum(1, k, 1, 3)` is [1]
  
  theory Integers
    var n : 1, integer, positive
    var m : 1, integer
    var A, B, C : 1
    law s : A = sin(n*pi)   [1]
    law c : B = cos(m*pi)   [1]
    law q : C = sin(m*pi)   [1]
    derive zero : A = 0   [1]
        from    Integers.s
        assumes n a positive integer
        via     simplify
          A = 0
    derive sign : B = (-1)^m   [1]
        from    Integers.c
        assumes m an integer
        via     simplify
          B = (-1)^m
    derive also_zero : C = 0   [1]
        from    Integers.q
        assumes m an integer
        via     simplify
          C = 0
  
  theory BadIntegers
    dim L
  cases/calculus/sums.lan:65: error: an integer counts, so it is dimensionless, but `q` is [L]
  cases/calculus/sums.lan:66: error: a vector cannot be `integer`
  cases/calculus/sums.lan:67: error: a variable cannot be both `integer` and `complex`
  
  [1]

Chained dependencies: y(x) with x(t), so derivatives by t follow the chain
rule; putting θ := ω*t into a law turns h(θ) into h(ω*t).

  $ landau -v cases/calculus/chain.lan
  theory Bead
    dim L, T
    var t : T
    var x(t) : L
    var y(x) : L
    var vy : L/T
    var ay : L/T^2
    law vertical : vy = diff(y, t)   [L/T]
    law accel : ay = diff(diff(y, t), t)   [L/T^2]
    derive chain : vy = diff(y, x)*diff(x, t)   [L/T]
        from    Bead.vertical
        via     simplify
          vy = diff(y, x)*diff(x, t)
    derive chain2 : ay = diff(x, t)^2*diff(diff(y, x), x) + diff(y, x)*diff(diff(x, t), t)   [L/T^2]
        from    Bead.accel
        via     simplify
          ay = diff(x, t)^2*diff(diff(y, x), x) + diff(y, x)*diff(diff(x, t), t)
  
  theory Pendulum
    dim L, T
    var t : T
    var θ(t) : 1
    var ω : 1/T, positive
    var ℓ : L, positive
    var h(θ) : L
    var vh : L/T
    law height : h = -ℓ*cos(θ)   [L]
    law rate : vh = diff(h, t)   [L/T]
    derive speed : vh = ℓ*diff(θ, t)*sin(θ)   [L/T]
        from    Pendulum.height, Pendulum.rate
        assumes ℓ > 0
        via     subst, simplify
          s := vh = diff(-ℓ*cos(θ), t)
          vh = ℓ*diff(θ, t)*sin(θ)
    derive steady : vh = ℓ*ω*sin(t*ω)   [L/T]
        from    Pendulum.height, Pendulum.rate
        assumes ℓ > 0, ω > 0
        via     instantiate, simplify
          s := vh = ℓ*diff(ω*t, t)*sin(ω*t)
          vh = ℓ*ω*sin(t*ω)
    derive general : vh = ω*at(diff(h, θ), θ, t*ω)   [L/T]
        from    Pendulum.rate
        assumes ω > 0
        via     instantiate, simplify
          s := vh = diff(h(ω*t), t)
          vh = ω*at(diff(h, θ), θ, t*ω)
  
  theory NoPath
    dim L, T
    var t : T
    var x : L
    var y(x) : L
    var v : L/T
  cases/calculus/chain.lan:51: error: `diff(y, t)` is always 0, because `y` does not depend on `t`; declare the dependence, e.g. `var y(t, x) : ...`
  
  [1]

Lagrangian mechanics: each misuse of euler_lagrange and conserved fails with
its reason; the last derivation holds.

  $ landau cases/calculus/lagrange_errors.lan
  theory Mistakes
    import SI
    var t, τ : s   [T]
    var x(t), z(t), y : m   [L]
    var u(t, τ) : m   [L]
    var r(t) : m   [L], vector
    var m : kg   [M], positive
    var F0 : N   [M*L/T^2]
    var ω : 1/s   [1/T]
    var L : J   [M*L^2/T^2]
    law free : L = m*diff(x, t)^2/2   [M*L^2/T^2]
    law driven : L = m*diff(x, t)^2/2 + F0*x*cos(ω*t)   [M*L^2/T^2]
    law static : L = F0*y   [M*L^2/T^2]
    law swapped : m*diff(x, t)^2/2 = L   [M*L^2/T^2]
    law vectorial : L = m*dot(diff(r, t), diff(r, t))/2   [M*L^2/T^2]
  cases/calculus/lagrange_errors.lan:20: error: `euler_lagrange` needs the Lagrangian as `L = ...`, but this is `m*diff(x, t)^2/2 = L`
  cases/calculus/lagrange_errors.lan:21: error: `y` is not a function of time; declare a coordinate like `var q(t)`
  cases/calculus/lagrange_errors.lan:22: error: a coordinate depends on time alone, like `var q(t)`, but `u` depends on t, τ
  cases/calculus/lagrange_errors.lan:23: error: `euler_lagrange` works one coordinate at a time; `r` is a vector
  cases/calculus/lagrange_errors.lan:24: error: the Lagrangian `m*diff(x, t)^2/2` does not depend on `z`
  cases/calculus/lagrange_errors.lan:25: error: `x` appears in the Lagrangian, so its momentum is not conserved: ∂L/∂x = F0*cos(t*ω)
  cases/calculus/lagrange_errors.lan:26: error: the Lagrangian depends on `t` itself, so the energy is not conserved: ∂L/∂t = -F0*ω*x*sin(t*ω)
  cases/calculus/lagrange_errors.lan:27: error: nothing in the Lagrangian `F0*y` changes with `t`
    derive cyclic : p_x = m*diff(x, t)   [M*L/T]
        from    Mistakes.free
        assumes m > 0
        constants p_x [M*L/T]
        via     conserved for x
  
  [1]
