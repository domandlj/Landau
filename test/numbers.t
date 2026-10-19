Numbers with units: evaluate, compute, constants and numeric roots.
compute guards a fixed bug: to 3 digits, 6864.655 J must round to 6860, not
6870. no_closed_form records a current limitation: a nonlinear system with no
formula fails with SymPy's own message, until systems can be solved
numerically.

  $ landau cases/numbers/evaluate.lan
  theory Numbers
    import SI
    const g = 9.81 [m/s^2]   [L/T^2]
    var m : kg   [M], positive
    var W : N   [M*L/T^2]
    var v : km/h   [L/T]
    var d : km   [L], positive
    var t : min   [T], positive
    var x : m   [L]
    var v0 : m/s   [L/T]
    var T1 : s   [T], positive
    law weight : W = m*g   [M*L/T^2]
    law speed : v = d/t   [L/T]
    law fall : x = v0*T1 - g*T1^2/2   [L]
    derive w : W = 19.62 [N]   [M*L/T^2]
        from    Numbers.weight
        via     instantiate, evaluate
    derive w_kN : W = 0.0196 [kN]   [M*L/T^2]
        from    Numbers.weight
        via     instantiate, evaluate in kN
    derive trip : v = 48 [km/h]   [L/T]
        from    Numbers.speed
        via     instantiate, evaluate
    derive trip_ms : v = 13.3333 [m/s]   [L/T]
        from    Numbers.speed
        via     instantiate, evaluate in m/s
    derive drop : x = -(19.62 [m])   [L]
        from    Numbers.fall
        via     instantiate, evaluate
    derive check_ok : 19.62 [N] = 19.62 [N]   [M*L/T^2]   (holds identically)
        from    Numbers.weight
        via     evaluate
    derive check_rounded : 19.6 [N] = 19.6 [N]   [M*L/T^2]   (holds identically)
        from    Numbers.weight
        via     evaluate
    derive time_up : T1 = 4.08 [s]   [T]
        from    Numbers.fall
        assumes T1 > 0, g > 0
        via     solve for T1, instantiate, evaluate
  

  $ landau cases/numbers/errors.lan
  theory E
    import SI
    const g = 9.81 [m/s^2]   [L/T^2]
    var m, M : kg   [M]
    var W : N   [M*L/T^2]
    var v : m/s   [L/T]
    var F : N   [M*L/T^2], vector
    law weight : W = m*g   [M*L/T^2]
    law two : W = M*g + m*g   [M*L/T^2]
    law vec : F = m*vec(0, 0, -g)   [3-vector M*L/T^2]
  cases/numbers/errors.lan:12: error: give values for `m`: put them in with `law[x := 3 [m]]`, or declare them with `const`
  cases/numbers/errors.lan:15: error: the result is [M*L/T^2], but `m/s` is [L/T]
  cases/numbers/errors.lan:18: error: the equation does not hold: the left side is 20 [N] but the right side is 19.62 [N] (to 6 digits)
  cases/numbers/errors.lan:21: error: `evaluate` works on scalar equations; take a component first
  cases/numbers/errors.lan:24: error: give values for `M`, `m`: put them in with `law[x := 3 [m]]`, or declare them with `const`
  cases/numbers/errors.lan:27: error: cannot put `2 [m]` [L] in place of `m` [M]
  cases/numbers/errors.lan:30: error: digits must be between 1 and 30
  
  theory NoUnits
    dim L, T
    var x : L
    var t : T
    law p : x = t*0   [L]
  cases/numbers/errors.lan:40: error: unknown dimension or unit `s`
  
  [1]

  $ landau cases/numbers/constants.lan
  theory Atom
    import Constants
    var F : N   [M*L/T^2]
    var r : m   [L], positive
    var E : eV   [M*L^2/T^2]
    var λ : nm   [L], positive
    var f : Hz   [1/T]
    law coulomb : F = k_e*e^2/r^2   [M*L/T^2]
    law photon : E = h*c/λ   [M*L^2/T^2]
    derive bohr_force : F = 8.24e-8 [N]   [M*L/T^2]
        from    Atom.coulomb
        via     instantiate, evaluate
    derive green_photon : E = 2.33 [eV]   [M*L^2/T^2]
        from    Atom.photon
        via     instantiate, evaluate
    derive in_joules : E = 3.734e-19 [J]   [M*L^2/T^2]
        from    Atom.photon
        via     instantiate, evaluate in J
    derive symbolic : λ = h*c/E   [L]
        from    Atom.photon
        assumes h > 0, c > 0, λ > 0
        via     solve for λ
  

  $ landau cases/numbers/compute.lan
  theory Energy
    import Constants
    def kinetic : ('a, 'b) -> 'a*'b^2
    def potential : ('a, 'b) -> 'a*'b*L/T^2
    def period : ('a) -> 'a^(1/2)*T/L^(1/2)
    compute kinetic(2 [kg], 3 [m/s]) = 9 [J]   [M*L^2/T^2]
    compute kinetic(1500 [kg], 100 [km/h]) = 579 [kJ]   [M*L^2/T^2]
    compute E1 = kinetic(2 [kg], 3 [m/s]) = 9 [J]   [M*L^2/T^2]
    compute E1/(2 [s]) = 4.5 [W]   [M*L^2/T^3]
    compute potential(70 [kg], 10 [m]) = 6860 [J]   [M*L^2/T^2]
    compute period(1 [m]) = 2.006 [s]   [T]
    compute h_drop = E1/(2 [kg]*g) = 45.9 [cm]   [L]
    compute sin(pi/6) = 0.5   [1]
    compute c/(1 [km/s]) = 299800   [1]
    var x : m   [L]
    law fall : x = h_drop   [L]
    derive check : x = 459 [mm]   [L]
        from    Energy.fall
        via     evaluate in mm
  
  theory Bad
    import SI
    def kinetic : ('a, 'b) -> 'a*'b^2
    var y : m   [L]
    var F : N   [M*L/T^2], vector
    compute kinetic(2 [kg], 3 [s]) = 9 [kg*s^2]   [M*T^2]
  cases/numbers/compute.lan:30: error: give values for `y`: write quantities such as `2 [kg]`, or declare constants with `const`
  cases/numbers/compute.lan:31: error: `compute` gives one number; take a component, as in `compute F.x`
  cases/numbers/compute.lan:32: error: the result is [M*L^2/T^2], but `m/s` is [L/T]
  cases/numbers/compute.lan:33: error: digits must be between 1 and 30
  
  [1]

  $ landau cases/numbers/quantity_in_law.lan
  theory Q
    import SI
    var W : N   [M*L/T^2]
    var m : kg   [M], positive
    law w : W = m*(9.81 [m/s^2])   [M*L/T^2]
    derive mass : m = W/(9.81 [m/s^2])   [M]
        from    Q.w
        assumes m > 0
        via     solve for m
    derive mass_value : m = 5 [kg]   [M]
        from    Q.w
        assumes m > 0
        via     solve for m, evaluate
  

  $ landau cases/numbers/nsolve.lan
  theory Kepler
    import SI
    var E, M, e : 1
    law kepler : M = E - e*sin(E)   [1]
    derive anomaly : E = 1.4987   [1]
        from    Kepler.kepler
        assumes the root near 1
        via     instantiate, solve for E numerically near 1
  
  theory Fall
    import Constants
    var x : m   [L]
    var t : s   [T], positive
    var v0 : m/s   [L/T]
    law height : x = v0*t - g*t^2/2   [L]
    derive landing : t = 4.08 [s]   [T]
        from    Fall.height
        assumes the root near 3 [s]
        via     instantiate, solve for t numerically near 3 [s]
  cases/numbers/nsolve.lan:22: error: give values for `v0`, `x` first, so that only `t` is unknown
  cases/numbers/nsolve.lan:26: error: the two sides have different dimensions: `t` is [T] but `3 [m]` is [L]
  
  [1]

  $ landau cases/numbers/no_closed_form.lan
  theory Wien
    var x : 1
    law peak : x = 5*(1 - exp(-x))   [1]
    derive wien_x : x = 4.96511   [1]
        from    Wien.peak
        assumes the root near 5
        via     solve for x numerically near 5
  
  theory Integral
    import SI
    var u : 1
    compute integral(exp(-u^3), u, 0, 1) = 0.807511   [1]
  
  theory Systems
    var x, y : 1
    law circle : x^2 + y^2 = 4   [1]
    law curve : y = exp(x)   [1]
  cases/numbers/no_closed_form.lan:20: error: SymPy: NotImplementedError: could not solve s1 - exp(-sqrt(-(s1 - 2)*(s1 + 2)))
  
  [1]
