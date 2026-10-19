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
