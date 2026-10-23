Units: SI, declared units, scale factors, and their errors.

  $ landau cases/units/si.lan
  theory Mechanics
    import SI
    var m : kg   [M], positive
    var v : m/s   [L/T]
    var a : m/s^2   [L/T^2]
    var F : N   [M*L/T^2]
    var r : m   [L], vector
    var Fv : N   [M*L/T^2], vector
    var τ : N*m   [M*L^2/T^2], vector
    var E : J   [M*L^2/T^2]
    var d : km   [L]
    var t : h   [T]
    law newton : F = m*a   [M*L/T^2]
    law kinetic : E = m*v^2/2   [M*L^2/T^2]
    law torque : τ = cross(r, Fv)   [3-vector M*L^2/T^2]
    law speed : v = d/t   [L/T]
    derive accel : a = F/m   [L/T^2]
        from    Mechanics.newton
        assumes m > 0
        via     solve for a
  
  theory Fields
    import SI
    var Q : C   [T*I]
    var ε0 : F/m   [T^4*I^2/(M*L^3)], positive
    var μ0 : H/m   [M*L/(T^2*I^2)], positive
    var R : m   [L], positive
    var E : V/m   [M*L/(T^3*I)]
    var B : T   [M/(T^2*I)]
    var c : m/s   [L/T], positive
    var ω : 1/s   [1/T]
    law coulomb : E = Q/(4*pi*ε0*R^2)   [M*L/(T^3*I)]
    law light : c = 1/sqrt(μ0*ε0)   [L/T]
    derive eps : ε0 = 1/(c^2*μ0)   [T^4*I^2/(M*L^3)]
        from    Fields.light
        assumes c > 0, μ0 > 0, ε0 > 0
        via     solve for ε0
    derive mu_c : μ0 = 1/(c^2*ε0)   [M*L/(T^2*I^2)]
        from    Fields.light
        assumes c > 0, μ0 > 0, ε0 > 0
        via     solve for μ0
  
  theory Auto
    import SI
    var x : L
    var q : T*I
    var p : M/(L*T^2)
    var eps : T^4*I^2/(M*L^3)
    var f : 1/T
    law two : x = x   [L]
  

  $ landau cases/units/errors.lan
  theory A
    dim L, T
    dim V = L/T
    unit m : L, s : T
    unit ft = 0.3048 [L]
  cases/units/errors.lan:6: error: a base unit needs a base dimension, but `V` is an alias
  cases/units/errors.lan:7: error: `L` already has the base unit `m`; define `yd` from it with its size, as in `unit yd = k*m`
  cases/units/errors.lan:8: error: `T` is already a dimension; a unit needs another name
  cases/units/errors.lan:9: error: a number like `1000` can only scale a unit, as in `unit km = 1000*m`; a dimension cannot contain one
    var y : ft^(1/2)   [L^(1/2)]
  cases/units/errors.lan:11: error: unknown dimension or unit `furlong`
    unit sqm = [L^(1/2)]
    var ok : ft/s   [L/T]
  
  theory B
    dim T
  cases/units/errors.lan:18: error: `T` is both a dimension and a unit of SI
  
  [1]

  $ landau cases/units/factors.lan
  theory A
    import SI
    unit ft = 0.3048 [L], mi = 1609.344 [L], ly = 9.4607e+15 [L]
  

  $ landau cases/units/negative_powers.lan
    dim L, T
    var a : T/L
    var b : T/L
    var c : T/L
    var d : T/L
    law same : a = b + c + d   [T/L]

  $ landau cases/units/annotated_def.lan
  theory K
    import SI
    def kinetic : (M, L/T) -> M*L^2/T^2
    compute kinetic(2 [kg], 3 [m/s]) = 9 [J]   [M*L^2/T^2]
  cases/units/annotated_def.lan:5: error: the argument `3 [s]` of `kinetic` is [T], but `kinetic` expects [L/T] there
  
  [1]

Angles: degrees are exactly pi/180 rad, a unit may be scaled by pi, and a lone
angle keeps its unit. Radians and cycles are both dimensionless, so a value in
rad/s cannot be shown in Hz, or back, without the 2π; that is an error rather
than a number off by 2π.

  $ landau cases/units/angles.lan
  theory Angles
    import SI
    unit rev = 2*pi [1], arcmin = pi/10800 [1]
    var ω : rad/s   [1/T]
    var f : Hz   [1/T]
    law spin : ω = 2*pi*f   [1/T]
    compute sin(30 [deg]) = 0.5   [1]
    compute 90 [deg] = 1.5708 [rad]   [1]
    compute pi/4 = 45 [deg]   [1]
    compute 1 [rad] = 57.29578 [deg]   [1]
    compute 1 [arcmin] = 0.01667 [deg]   [1]
    compute 33 [rev/min] = 3.45575 [rad/s]   [1/T]
    compute 360 [deg/s] = 6.28319 [rad/s]   [1/T]
    compute 3 [rad/s] = 3 [1/s]   [1/T]
    compute 3 [rad/s]/(2*pi) = 0.477465 [Hz]   [1/T]
    compute th = 45 [deg] = 45 [deg]   [1]
    compute cos(th)^2 = 0.5   [1]
    derive w : ω = 314.159 [rad/s]   [1/T]
        from    Angles.spin
        via     instantiate, evaluate in rad/s
  
  theory ToHz
    import SI
  cases/units/angles.lan:28: error: `3 [rad/s]` cannot be given in Hz without a factor 2π: Hz counts cycles, and a cycle is 2π rad. Write `3 [rad/s]/(2*pi)` in Hz
  
  theory FromHz
    import SI
  cases/units/angles.lan:33: error: `50 [Hz]` cannot be given in rad/s without a factor 2π: Hz counts cycles, and a cycle is 2π rad. Write `2*pi*50 [Hz]` in rad/s
  
  theory Degrees
    import SI
    var ω : deg/s   [1/T]
    const ω0 = 10 [deg/s]   [1/T]
  cases/units/angles.lan:40: error: `ω0` cannot be given in Hz without a factor 2π: Hz counts cycles, and a cycle is 2π rad. Write `ω0/(2*pi)` in Hz
  
  [1]

A bare number for a variable declared in degrees would be read as radians, so
it is an error, in a substitution and as an initial value. With its unit, as 0,
or for a variable declared in rad, it is accepted.

  $ landau cases/units/bare_angles.lan
  theory Fine
    import SI
    var θ : deg   [1]
    var φ : rad   [1]
    var y, r : m   [L]
    law height : y = r*sin(θ)   [L]
    law height2 : y = r*sin(φ)   [L]
    derive with_unit : y = 1 [m]   [L]
        from    Fine.height
        via     instantiate, evaluate in m
    derive zero : y = 0 [m]   [L]
        from    Fine.height
        via     instantiate, evaluate in m
    derive radians : y = 0.958851 [m]   [L]
        from    Fine.height2
        via     instantiate, evaluate in m
  
  theory Bare
    import SI
    var θ : deg   [1]
    var y, r : m   [L]
    law height : y = r*sin(θ)   [L]
  cases/units/bare_angles.lan:30: error: `θ` is declared in deg: write `θ := 30 [deg]` (a bare 30 would be 30 rad)
  cases/units/bare_angles.lan:33: error: `θ` is declared in deg: write `θ := -(30 [deg])` (a bare -30 would be -30 rad)
  
  theory Swing
    import SI
    var t : s   [T]
    var θ(t) : deg   [1]
    law swing : diff(diff(θ, t), t) = -(9.8 [m/s^2])/(1 [m])*sin(θ)   [1/T^2]
    simulate fine: t from 0 to 2 [s], 5 points (DOP853)
        θ: starts at 30, ends at 29.7523, between -29.938 and 30 [deg]
  cases/units/bare_angles.lan:43: error: `θ` is declared in deg: write `θ(0 [s]) = 30 [deg]` (a bare 30 would be 30 rad)
  
  [1]
