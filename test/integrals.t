Integrals over lines, surfaces and volumes, and improper ones.
divergence_theorem guards a fixed bug: the volume side used to be 0 because
the point was put in before the derivatives were taken.

  $ landau cases/integrals/shapes.lan
  theory Geo
    dim M, L, T
    var r : L, position
    var s, u, w : 1
    var ρ : L
    var θ, φ : 1
    var a, R, h : L, positive
    var m, k : M, positive
    var g : L/T^2, positive
    var v0 : L/T, positive
    var ρ0 : M/L^3, positive
    var W : M*L^2/T^2
    var Len : L, positive
    var Ar : L^2
    var ϱ, z : L
    var Φ : L^3/T
    var V : L^3
    var Mass : M
    var F(r) : M*L/T^2, vector
    var Γ : L^2/T
    law work_ramp : W = line(vec(0, 0, -m*g), vec(h*s, 0, h*s), s, 0, 1)   [M*L^2/T^2]
    law circumf : Len = line(1, vec(a*cos(s), a*sin(s), 0), s, 0, 2*pi)   [L]
    law flux_disk : Φ = surface(vec(0, 0, v0), vec(ϱ*cos(w), ϱ*sin(w), 0), ϱ, 0, R, w, 0, 2*pi)   [L^3/T]
    law sphere_area : Ar = surface(1, vec(R*sin(u)*cos(w), R*sin(u)*sin(w), R*cos(u)), u, 0, pi, w, 0, 2*pi)   [L^2]
    law ball : V = volume(1, vec(ρ*sin(θ)*cos(φ), ρ*sin(θ)*sin(φ), ρ*cos(θ)), ρ, 0, R, θ, 0, pi, φ, 0, 2*pi)   [L^3]
    law cone_mass : Mass = volume(ρ0, vec(ϱ*cos(w), ϱ*sin(w), z), ϱ, 0, R*(1 - z/h), w, 0, 2*pi, z, 0, h)   [M]
    law circulation : Γ = loop(vec(-r.y, r.x, 0)*v0/a, vec(a*cos(s), a*sin(s), 0), s, 0, 2*pi)   [L^2/T]
    derive d1 : W = -m*g*h   [M*L^2/T^2]
        from    Geo.work_ramp
        assumes m > 0, g > 0, h > 0
        via     simplify
    derive d2 : Len = 2*pi*a   [L]
        from    Geo.circumf
        assumes Len > 0, a > 0
        via     simplify
    derive d3 : Φ = pi*v0*R^2   [L^3/T]
        from    Geo.flux_disk
        assumes v0 > 0, R > 0
        via     simplify
    derive d4 : Ar = 4*pi*R^2   [L^2]
        from    Geo.sphere_area
        assumes R > 0
        via     simplify
    derive d5 : V = 4*pi*R^3/3   [L^3]
        from    Geo.ball
        assumes R > 0
        via     simplify
    derive d6 : Mass = pi*ρ0*h*R^2/3   [M]
        from    Geo.cone_mass
        assumes ρ0 > 0, R > 0, h > 0
        via     simplify
    derive d7 : Γ = 2*pi*a*v0   [L^2/T]
        from    Geo.circulation
        assumes a > 0, v0 > 0
        via     simplify
  

  $ landau cases/integrals/divergence_theorem.lan
  theory DivTheorem
    dim L
    var r : L, position
    var R : L, positive
    var ρ : L
    var θ, φ : 1
    var F(r) : L, vector
    var Out, In : L^3
    law field : F = vec(r.x, r.y, r.z)   [3-vector L]
    law flux : Out = surface(F, vec(R*sin(θ)*cos(φ), R*sin(θ)*sin(φ), R*cos(θ)), θ, 0, pi, φ, 0, 2*pi)   [L^3]
    law source : In = volume(div(F), vec(ρ*sin(θ)*cos(φ), ρ*sin(θ)*sin(φ), ρ*cos(θ)), ρ, 0, R, θ, 0, pi, φ, 0, 2*pi)   [L^3]
    derive outward : Out = 4*pi*R^3   [L^3]
        from    DivTheorem.field, DivTheorem.flux
        assumes R > 0
        via     subst, simplify
    derive inside : In = 4*pi*R^3   [L^3]
        from    DivTheorem.field, DivTheorem.source
        assumes R > 0
        via     subst, simplify
  
  theory Bad
    dim L, T
    var r : L, position(2)
    var s : 1
    var t : T
    var a : L
    var A : L^2
  cases/integrals/divergence_theorem.lan:29: error: `surface` needs 3-dimensional space, but the position `r` is a 2-vector
  cases/integrals/divergence_theorem.lan:30: error: the bound `t` of `line` is [T], but the parameter `s` is [1]
  cases/integrals/divergence_theorem.lan:31: error: the parameters of `line` must be variables, but got `2*s`
  cases/integrals/divergence_theorem.lan:32: error: `line` needs a 2-vector, but `vec(a*s, 0, 0)` is a 3-vector
  
  [1]

  $ landau cases/integrals/improper.lan
    dim L, T
    var x : L
    var t : T
    var a : L, positive
    var τ : T, positive
    var A : L
    var B : 1
    var D : L
    law gauss : A = integral(exp(-x^2/a^2), x, -inf, inf)   [L]
    law decay : B = integral(exp(-t/τ), t, 0, inf)/τ   [1]
    law diverge : D = integral(1, x, 0, inf)   [L]
    law limitdim : x = inf   [L]
    derive g : A = a*sqrt(pi)   [L]
        from    Main.gauss
        assumes a > 0
        via     simplify
    derive d : B = 1   [1]
        from    Main.decay
        assumes τ > 0
        via     simplify
    derive v : D = inf   [L]
        from    Main.diverge
        via     simplify

  $ landau cases/integrals/line_gravity.lan
  theory Gravity
    dim M, L, T
    var r : L, position
    var s : 1
    var p(s) : L, vector
    var F(r) : M*L/T^2, vector
    var W : M*L^2/T^2
    var m : M, positive
    var g : L/T^2, positive
    var h : L, positive
    law work : W = integral(dot(F(p), diff(p, s)), s, 0, 1)   [M*L^2/T^2]
    law field : F = vec(0, 0, -m*g)   [3-vector M*L/T^2]
    law path : p = vec(h*s, 0, h*s)   [3-vector L]
    derive lifted : W = -m*g*h   [M*L^2/T^2]
        from    Gravity.path, Gravity.field, Gravity.work
        assumes m > 0, g > 0, h > 0
        via     subst, subst, simplify
  

  $ landau cases/integrals/line_spring.lan
  theory Spring3D
    dim M, L, T
    var r : L, position
    var s : 1
    var p(s) : L, vector
    var F(r) : M*L/T^2, vector
    var W : M*L^2/T^2
    var k : M/T^2, positive
    var a, b : L, positive
    law work : W = integral(dot(F(p), diff(p, s)), s, 0, 1)   [M*L^2/T^2]
    law field : F = -k*vec(r.x, r.y, r.z)   [3-vector M*L/T^2]
    law path : p = vec(a*cos(pi*s/2), b*sin(pi*s/2), 0)   [3-vector L]
    derive along_ellipse : W = k*(a^2 - b^2)/2   [M*L^2/T^2]
        from    Spring3D.path, Spring3D.field, Spring3D.work
        assumes k > 0, a > 0, b > 0
        via     subst, subst, simplify
  
