The modules that come with Landau, checked in full, with every derivation
step (-v). Their output is the expected behavior: a change to a derived law,
a dimension or a number shows up here. Each result was checked by hand or
against an independent calculation when the feature was added.

  $ landau -v ../modules/projectile.lan
  theory Kinematics
    dim L, T
    var r, r0 : L, vector(2)
    var v0 : L/T, vector(2)
    var a : L/T^2, vector(2)
    var t : T, positive
    law position : r = r0 + v0*t + a*t^2/2   [2-vector L]
  
  theory Projectile
    import Kinematics
    var v : L/T, positive
    var θ : 1
    var g : L/T^2, positive
    var R : L
    derive range : R = v^2*sin(2*θ)/g   [L]
        from    Kinematics.position
        assumes v > 0, t > 0, g > 0
        via     instantiate, component x, component y, solve for t, subst, simplify
          m := vec(R, 0) = vec(v*cos(θ)*t, v*sin(θ)*t - g*t^2/2)
          hx := R = v*cos(θ)*t
          hy := 0 = v*sin(θ)*t - g*t^2/2
          tf := t = 2*v*sin(θ)/g
          rr := R = v*cos(θ)*(2*v*sin(θ)/g)
          R = v^2*sin(2*θ)/g
  

  $ landau -v ../modules/energy.lan
  theory Mechanics
    dim M, L, T
    dim Energy = M*L^2/T^2
    var m : M, positive
    var v : L/T, positive
    var h : L, positive
    var g : L/T^2, positive
    var E : M*L^2/T^2
    def kinetic : ('a, 'b) -> 'a*'b^2
    def potential : ('a, 'b) -> 'a*'b*L/T^2
    law conservation : kinetic(m, v) = potential(m, h)   [M*L^2/T^2]
    derive fall_speed : v = sqrt(2)*sqrt(g)*sqrt(h)   [L/T]
        from    Mechanics.conservation
        assumes m > 0, v > 0, g > 0, h > 0
        via     solve for v
          v = sqrt(2)*sqrt(g)*sqrt(h)
    derive fall_height : h = v^2/(2*g)   [L]
        from    Mechanics.conservation
        assumes m > 0, v > 0, g > 0, h > 0
        via     solve for h
          h = v^2/(2*g)
  

  $ landau -v ../modules/motion.lan
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
    derive gravity : a = -g   [L/T^2]
        from    Motion.position, Motion.velocity, Motion.accel
        assumes g > 0
        via     subst, simplify
          s := a = diff(v0 - t*g, t)
          a = -g
    derive highest : t = v0/g   [T]
        from    Motion.position, Motion.velocity
        assumes g > 0
        via     instantiate, solve for t
          s := 0 = v0 - t*g
          t = v0/g
    derive twice : diff(diff(x, t), t) = -g   [L/T^2]
        from    Motion.position
        assumes g > 0
        via     differentiate by t, differentiate by t, simplify
          d1 := diff(x, t) = diff(x0 + v0*t - g*t^2/2, t)
          d2 := diff(diff(x, t), t) = diff(diff(x0 + v0*t - g*t^2/2, t), t)
          diff(diff(x, t), t) = -g
  
  theory Oscillations
    import Motion
    var ω : 1/T, positive
    var T1 : T, positive
    law falling : diff(diff(x, t), t) = -g   [L/T^2]
    law spring : diff(diff(x, t), t) = -ω^2*x   [L/T^2]
    derive general : x = C1 + C2*t - g*t^2/2   [L]
        from    Oscillations.falling
        assumes g > 0
        constants C1 [L], C2 [L/T]
        via     solve for x
          x = C1 + C2*t - g*t^2/2
    derive thrown : x = x0 + t*v0 - g*t^2/2   [L]
        from    Oscillations.falling
        assumes g > 0
        via     solve for x with initial conditions
          x = x0 + t*v0 - g*t^2/2
    derive oscillator : x = x0*cos(t*ω)   [L]
        from    Oscillations.spring
        assumes ω > 0
        via     solve for x with initial conditions
          x = x0*cos(t*ω)
    derive displacement : integral(v, t, 0, T1) = -x(0) + x(T1)   [L]
        from    Motion.velocity
        assumes T1 > 0
        via     integrate by t from 0 to T1, simplify
          i := integral(v, t, 0, T1) = integral(diff(x, t), t, 0, T1)
          integral(v, t, 0, T1) = -x(0) + x(T1)
  
  theory Identities
    dim L
    var r : L, position
    var f(r) : L
    var F(r) : L, vector
    law curl_grad : curl(grad(f)) = 0   [3-vector 1/L]
    law div_curl : div(curl(F)) = 0   [1/L]
    derive check_curl_grad : 0 = 0   [any]   (holds identically)
        from    Identities.curl_grad
        via     expand, simplify
          e := vec(diff(diff(f, r.z), r.y) - diff(diff(f, r.y), r.z), diff(diff(f, r.x), r.z) - diff(diff(f, r.z), r.x), diff(diff(f, r.y), r.x) - diff(diff(f, r.x), r.y)) = 0
          0 = 0
    derive check_div_curl : 0 = 0   [any]   (holds identically)
        from    Identities.div_curl
        via     expand, simplify
          e := diff(diff(F.z, r.y) - diff(F.y, r.z), r.x) + diff(diff(F.x, r.z) - diff(F.z, r.x), r.y) + diff(diff(F.y, r.x) - diff(F.x, r.y), r.z) = 0
          0 = 0
  

  $ landau -v ../modules/approximations.lan
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
    derive small_angles : diff(diff(θ, t), t) = -g*θ/L   [1/T^2]
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
  
  theory Altitude
    import Constants
    var M : kg   [M], positive
    var R, z : m   [L], positive
    var gz : m/s^2   [L/T^2]
    law gravity : gz = G*M/(R + z)^2   [L/T^2]
    derive near_surface : gz = G*M/R^2 - 2*G*M*z/R^3   [L/T^2]
        from    Altitude.gravity
        assumes z ≪ R (to order 1); left out: 3*G*M*z^2/R^4
        via     approximate (z ≪ R, order 1)
          gz = G*M/R^2 - 2*G*M*z/R^3
  
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
  

  $ landau -v ../modules/systems.lan
  theory ElasticCollision
    dim M, L, T
    var m1, m2 : M, positive
    var v1, v2 : L/T
    var u1, u2 : L/T
    law momentum : m1*v1 + m2*v2 = m1*u1 + m2*u2   [M*L/T]
    law energy : m1*v1^2/2 + m2*v2^2/2 = m1*u1^2/2 + m2*u2^2/2   [M*L^2/T^2]
    derive first_after : u1 = (v1*m1 - v1*m2 + 2*v2*m2)/(m1 + m2)   [L/T]
        from    ElasticCollision.momentum, ElasticCollision.energy
        assumes m1 > 0, m2 > 0
        via     solve for u1, u2
          u1 = (v1*m1 - v1*m2 + 2*v2*m2)/(m1 + m2)
    derive second_after : u2 = (v2*m2 - v2*m1 + 2*v1*m1)/(m1 + m2)   [L/T]
        from    ElasticCollision.momentum, ElasticCollision.energy
        assumes m1 > 0, m2 > 0
        via     solve for u2, u1
          u2 = (v2*m2 - v2*m1 + 2*v1*m1)/(m1 + m2)
  
  theory Atwood
    dim M, L, T
    dim Force = M*L/T^2
    var m1, m2 : M, positive
    var g : L/T^2, positive
    var a : L/T^2
    var Tn : M*L/T^2
    law heavy : m1*a = m1*g - Tn   [M*L/T^2]
    law light : m2*a = Tn - m2*g   [M*L/T^2]
    derive acceleration : a = g*(m1 - m2)/(m1 + m2)   [L/T^2]
        from    Atwood.heavy, Atwood.light
        assumes m1 > 0, g > 0, m2 > 0
        via     solve for a, Tn
          a = g*(m1 - m2)/(m1 + m2)
    derive tension : Tn = 2*m1*g*m2/(m1 + m2)   [M*L/T^2]
        from    Atwood.heavy, Atwood.light
        assumes m1 > 0, g > 0, m2 > 0
        via     solve for Tn, a
          Tn = 2*m1*g*m2/(m1 + m2)
  
  theory Kirchhoff
    dim M, L, T, I
    dim Volt = M*L^2/(T^3*I)
    dim Ohm = M*L^2/(T^3*I^2)
    var ε1, ε2 : M*L^2/(T^3*I)
    var R1, R2, R3 : M*L^2/(T^3*I^2), positive
    var I1, I2, I3 : I
    law junction : I1 + I2 = I3   [I]
    law left : ε1 = I1*R1 + I3*R3   [M*L^2/(T^3*I)]
    law right : ε2 = I2*R2 + I3*R3   [M*L^2/(T^3*I)]
    derive shared_current : I3 = (ε1*R2 + ε2*R1)/(R1*R3 + R1*R2 + R3*R2)   [I]
        from    Kirchhoff.junction, Kirchhoff.left, Kirchhoff.right
        assumes R1 > 0, R3 > 0, R2 > 0
        via     solve for I3, I1, I2
          I3 = (ε1*R2 + ε2*R1)/(R1*R3 + R1*R2 + R3*R2)
  

  $ landau -v ../modules/units.lan
  theory Mechanics
    import SI
    var m : kg   [M], positive
    var v : m/s   [L/T]
    var a : m/s^2   [L/T^2]
    var F : N   [M*L/T^2]
    var E : J   [M*L^2/T^2]
    var r : m   [L], vector
    var Fv : N   [M*L/T^2], vector
    var τ : N*m   [M*L^2/T^2], vector
    var d : km   [L]
    var t : h   [T], positive
    law newton : F = m*a   [M*L/T^2]
    law kinetic : E = m*v^2/2   [M*L^2/T^2]
    law torque : τ = cross(r, Fv)   [3-vector M*L^2/T^2]
    law average : v = d/t   [L/T]
    derive accel : a = F/m   [L/T^2]
        from    Mechanics.newton
        assumes m > 0
        via     solve for a
          a = F/m
  
  theory Electromagnetism
    import SI
    var q, Q : C   [T*I]
    var ε0 : F/m   [T^4*I^2/(M*L^3)], positive
    var μ0 : H/m   [M*L/(T^2*I^2)], positive
    var R : m   [L], positive
    var E : V/m   [M*L/(T^3*I)]
    var B : T   [M/(T^2*I)]
    var c : m/s   [L/T], positive
    var Fm : N   [M*L/T^2]
    var v : m/s   [L/T]
    law coulomb : E = Q/(4*pi*ε0*R^2)   [M*L/(T^3*I)]
    law light : c = 1/sqrt(μ0*ε0)   [L/T]
    law magnetic : Fm = q*v*B   [M*L/T^2]
    derive permittivity : ε0 = 1/(c^2*μ0)   [T^4*I^2/(M*L^3)]
        from    Electromagnetism.light
        assumes c > 0, μ0 > 0, ε0 > 0
        via     solve for ε0
          ε0 = 1/(c^2*μ0)
  
  theory Imperial
    import SI
    unit ft = 0.3048 [L], mi = 1609.344 [L], lbf = 4.448221615 [M*L/T^2]
    var height : ft   [L]
    var weight : lbf   [M*L/T^2]
    var work : J   [M*L^2/T^2]
    law lifting : work = weight*height   [M*L^2/T^2]
  

  $ landau -v ../modules/numbers.lan
  theory Kinematics
    import Constants
    var x, x0 : m   [L]
    var v, v0 : m/s   [L/T]
    var t : s   [T], positive
    var H : m   [L]
    law position : x = x0 + v0*t - g*t^2/2   [L]
    law speed : v = v0 - g*t   [L/T]
    derive top_time : t = 1.53 [s]   [T]
        from    Kinematics.speed
        assumes g > 0, t > 0
        via     instantiate, solve for t, evaluate
          s := 0 = 15 [m/s] - g*t
          t1 := t = 15 [m/s]/g
          t = 1.53 [s]
    derive top_height : x = 11.5 [m]   [L]
        from    Kinematics.speed, Kinematics.position
        assumes g > 0, t > 0
        via     solve for t, subst, instantiate, evaluate
          t1 := t = v0/g
          h := x = x0 + v0*(v0/g) - g*(v0/g)^2/2
          a := x = 15 [m/s]*(15 [m/s]/g) - g*(15 [m/s]/g)^2/2
          x = 11.5 [m]
  
  theory Driving
    import SI
    var d : km   [L], positive
    var T : min   [T], positive
    var v : km/h   [L/T]
    law average : v = d/T   [L/T]
    derive trip : v = 48 [km/h]   [L/T]
        from    Driving.average
        via     instantiate, evaluate
          a := v = 12 [km]/(15 [min])
          v = 48 [km/h]
    derive trip_si : v = 13.3 [m/s]   [L/T]
        from    Driving.average
        via     instantiate, evaluate in m/s
          a := v = 12 [km]/(15 [min])
          v = 13.3 [m/s]
  
  theory Orbit
    import Constants
    var M, m : kg   [M], positive
    var r : m   [L], positive
    var v : km/s   [L/T], positive
    law circular : G*M*m/r^2 = m*v^2/r   [M*L/T^2]
    derive leo : v = 7.67 [km/s]   [L/T]
        from    Orbit.circular
        assumes G > 0, M > 0, m > 0, r > 0, v > 0
        via     solve for v, instantiate, evaluate
          s := v = sqrt(G)*sqrt(M)/sqrt(r)
          a := v = sqrt(G)*sqrt(5.97e24 [kg])/sqrt(6780000 [m])
          v = 7.67 [km/s]
  
  theory Answers
    import SI
    var F : N   [M*L/T^2]
    var m : kg   [M], positive
    var a : m/s^2   [L/T^2]
    law newton : F = m*a   [M*L/T^2]
    derive check : 29.4 [N] = 29.4 [N]   [M*L/T^2]   (holds identically)
        from    Answers.newton
        via     evaluate
          29.4 [N] = 29.4 [N]
  
  theory Energies
    import Constants
    def kinetic : (M, L/T) -> M*L^2/T^2
    def potential : (M, L) -> M*L^2/T^2
    compute kinetic(1500 [kg], 100 [km/h]) = 579 [kJ]   [M*L^2/T^2]
    compute E_ball = kinetic(0.145 [kg], 40 [m/s]) = 116 [J]   [M*L^2/T^2]
    compute h_ball = E_ball/(0.145 [kg]*g) = 81.6 [m]   [L]
    compute potential(70 [kg], 8848 [m]) = 6.07 [MJ]   [M*L^2/T^2]
  

  $ landau -v ../modules/forces.lan
  theory Incline
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var α, μ : 1, positive
    var N, f : N   [M*L/T^2]
    var a : m/s^2   [L/T^2]
    diagram sliding : vec(-m*a*cos(α), -m*a*sin(α)) = vec(-N*sin(α) + μ*N*cos(α), -m*g + N*cos(α) + μ*N*sin(α))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force N = N toward (-0.479, 0.878)
        force f = μ*N toward (0.878, 0.479)
    derive acceleration : a = g*(-μ*cos(α) + sin(α))   [L/T^2]
        from    Incline.sliding
        assumes m > 0, α > 0, μ > 0, g > 0
        via     component x, component y, solve for a, N
          x := -m*a*cos(α) = -N*sin(α) + μ*N*cos(α)
          y := -m*a*sin(α) = -m*g + N*cos(α) + μ*N*sin(α)
          a = g*(-μ*cos(α) + sin(α))
    derive normal_force : N = m*g*cos(α)   [M*L/T^2]
        from    Incline.sliding
        assumes m > 0, α > 0, μ > 0, g > 0
        via     component x, component y, solve for N, a
          x := -m*a*cos(α) = -N*sin(α) + μ*N*cos(α)
          y := -m*a*sin(α) = -m*g + N*cos(α) + μ*N*sin(α)
          N = m*g*cos(α)
  
  theory Knot
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var T1, T2 : N   [M*L/T^2]
    var β : 1, positive
    diagram hanging : 0 = vec(-T1*cos(β) + T2*cos(β), -m*g + T1*sin(β) + T2*sin(β))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force T1 = T1 toward (-0.825, 0.565)
        force T2 = T2 toward (0.825, 0.565)
    derive tension : T1 = m*g/(2*sin(β))   [M*L/T^2]
        from    Knot.hanging
        assumes β > 0, m > 0, g > 0
        via     component x, component y, solve for T1, T2
          x := 0 = -T1*cos(β) + T2*cos(β)
          y := 0 = -m*g + T1*sin(β) + T2*sin(β)
          T1 = m*g/(2*sin(β))
  
  theory Atwood
    import SI
    var m1, m2 : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var T : N   [M*L/T^2]
    var a : m/s^2   [L/T^2]
    diagram heavy : vec(0, -m1*a) = vec(0, -m1*g + T)   [2-vector M*L/T^2]
        force W1 = m1*g toward (0, -1)
        force T = T toward (0, 1)
    diagram light : vec(0, m2*a) = vec(0, -m2*g + T)   [2-vector M*L/T^2]
        force W2 = m2*g toward (0, -1)
        force T = T toward (0, 1)
    derive acceleration : a = g*(m1 - m2)/(m1 + m2)   [L/T^2]
        from    Atwood.heavy, Atwood.light
        assumes m1 > 0, g > 0, m2 > 0
        via     component y, component y, solve for a, T
          h := -m1*a = -m1*g + T
          l := m2*a = -m2*g + T
          a = g*(m1 - m2)/(m1 + m2)
  

  $ landau -v ../modules/work.lan
  theory Work1D
    dim M, L, T
    dim Force = M*L/T^2
    var x, x1, x2 : L
    var F(x) : M*L/T^2
    var W : M*L^2/T^2
    var k : M/T^2, positive
    law work : W = integral(F, x, x1, x2)   [M*L^2/T^2]
    law hooke : F = -k*x   [M*L/T^2]
    derive spring_work : W = k*(x1^2 - x2^2)/2   [M*L^2/T^2]
        from    Work1D.hooke, Work1D.work
        assumes k > 0
        via     subst, simplify
          w := W = integral(-k*x, x, x1, x2)
          W = k*(x1^2 - x2^2)/2
  
  theory WorkAlongPath
    dim M, L, T
    dim Force = M*L/T^2
    var r : L, position
    var s : 1
    var p(s) : L, vector
    var F(r) : M*L/T^2, vector
    var W : M*L^2/T^2
    var m, k : M, positive
    var g : L/T^2, positive
    var h, a, b : L, positive
    law work : W = line(F, p, s, 0, 1)   [M*L^2/T^2]
    law gravity : F = vec(0, 0, -m*g)   [3-vector M*L/T^2]
    law ramp : p = vec(h*s, 0, h*s)   [3-vector L]
    derive lift : W = -m*g*h   [M*L^2/T^2]
        from    WorkAlongPath.ramp, WorkAlongPath.gravity, WorkAlongPath.work
        assumes m > 0, g > 0, h > 0
        via     subst, subst, simplify
          w1 := W = line(vec(0, 0, -m*g), p, s, 0, 1)
          w2 := W = line(vec(0, 0, -m*g), vec(h*s, 0, h*s), s, 0, 1)
          W = -m*g*h
  
  theory SpringField
    import WorkAlongPath
    var κ : M/T^2, positive
    law spring : F = -κ*vec(r.x, r.y, r.z)   [3-vector M*L/T^2]
    law ellipse : p = vec(a*cos(pi*s/2), b*sin(pi*s/2), 0)   [3-vector L]
    derive around : W = κ*(a^2 - b^2)/2   [M*L^2/T^2]
        from    SpringField.ellipse, SpringField.spring, WorkAlongPath.work
        assumes κ > 0, a > 0, b > 0
        via     subst, subst, simplify
          w1 := W = line(vec(-κ*r.x, -κ*r.y, -κ*r.z), p, s, 0, 1)
          w2 := W = line(vec(-κ*r.x, -κ*r.y, -κ*r.z), vec(a*cos(pi*s/2), b*sin(pi*s/2), 0), s, 0, 1)
          W = κ*(a^2 - b^2)/2
  

  $ landau -v ../modules/integrals.lan
  theory Shapes
    dim M, L
    var r : L, position
    var R, h : L, positive
    var ρ, ϱ, z : L
    var θ, φ : 1
    var ρ0 : M/L^3, positive
    var Area : L^2
    var Vol : L^3
    var Mass : M
    law sphere : Area = surface(1, vec(R*sin(θ)*cos(φ), R*sin(θ)*sin(φ), R*cos(θ)), θ, 0, pi, φ, 0, 2*pi)   [L^2]
    law ball : Vol = volume(1, vec(ρ*sin(θ)*cos(φ), ρ*sin(θ)*sin(φ), ρ*cos(θ)), ρ, 0, R, θ, 0, pi, φ, 0, 2*pi)   [L^3]
    law cone : Mass = volume(ρ0, vec(ϱ*cos(φ), ϱ*sin(φ), z), ϱ, 0, R*(1 - z/h), φ, 0, 2*pi, z, 0, h)   [M]
    derive sphere_area : Area = 4*pi*R^2   [L^2]
        from    Shapes.sphere
        assumes R > 0
        via     simplify
          Area = 4*pi*R^2
    derive ball_volume : Vol = 4*pi*R^3/3   [L^3]
        from    Shapes.ball
        assumes R > 0
        via     simplify
          Vol = 4*pi*R^3/3
    derive cone_mass : Mass = pi*ρ0*h*R^2/3   [M]
        from    Shapes.cone
        assumes ρ0 > 0, R > 0, h > 0
        via     simplify
          Mass = pi*ρ0*h*R^2/3
  
  theory Improper
    dim L, T
    var x : L
    var t : T
    var a : L, positive
    var τ : T, positive
    var G : L
    var P : 1
    law gaussian : G = integral(exp(-x^2/a^2), x, -inf, inf)   [L]
    law decay : P = integral(exp(-t/τ), t, 0, inf)/τ   [1]
    derive gaussian_value : G = a*sqrt(pi)   [L]
        from    Improper.gaussian
        assumes a > 0
        via     simplify
          G = a*sqrt(pi)
    derive normalized : P = 1   [1]
        from    Improper.decay
        assumes τ > 0
        via     simplify
          P = 1
  
  theory Theorems
    dim L
    var r : L, position
    var R : L, positive
    var ρ, ϱ : L
    var θ, φ, s : 1
    var F(r) : L, vector
    var Out, Inside : L^3
    var Around, Through : L^2
    law radial : F = vec(r.x, r.y, r.z)   [3-vector L]
    law flux : Out = surface(F, vec(R*sin(θ)*cos(φ), R*sin(θ)*sin(φ), R*cos(θ)), θ, 0, pi, φ, 0, 2*pi)   [L^3]
    law source : Inside = volume(div(F), vec(ρ*sin(θ)*cos(φ), ρ*sin(θ)*sin(φ), ρ*cos(θ)), ρ, 0, R, θ, 0, pi, φ, 0, 2*pi)   [L^3]
    derive gauss_outside : Out = 4*pi*R^3   [L^3]
        from    Theorems.radial, Theorems.flux
        assumes R > 0
        via     subst, simplify
          f := Out = surface(vec(r.x, r.y, r.z), vec(R*sin(θ)*cos(φ), R*sin(θ)*sin(φ), R*cos(θ)), θ, 0, pi, φ, 0, 2*pi)
          Out = 4*pi*R^3
    derive gauss_inside : Inside = 4*pi*R^3   [L^3]
        from    Theorems.radial, Theorems.source
        assumes R > 0
        via     subst, simplify
          f := Inside = volume(div(vec(r.x, r.y, r.z)), vec(ρ*sin(θ)*cos(φ), ρ*sin(θ)*sin(φ), ρ*cos(θ)), ρ, 0, R, θ, 0, pi, φ, 0, 2*pi)
          Inside = 4*pi*R^3
    law swirl : F = vec(-r.y, r.x, 0)   [3-vector L]
    law circulation : Around = loop(F, vec(R*cos(s), R*sin(s), 0), s, 0, 2*pi)   [L^2]
    law curl_flux : Through = surface(curl(F), vec(ϱ*cos(φ), ϱ*sin(φ), 0), ϱ, 0, R, φ, 0, 2*pi)   [L^2]
    derive stokes_around : Around = 2*pi*R^2   [L^2]
        from    Theorems.swirl, Theorems.circulation
        assumes R > 0
        via     subst, simplify
          c := Around = loop(vec(-r.y, r.x, 0), vec(R*cos(s), R*sin(s), 0), s, 0, 2*pi)
          Around = 2*pi*R^2
    derive stokes_through : Through = 2*pi*R^2   [L^2]
        from    Theorems.swirl, Theorems.curl_flux
        assumes R > 0
        via     subst, simplify
          c := Through = surface(curl(vec(-r.y, r.x, 0)), vec(ϱ*cos(φ), ϱ*sin(φ), 0), ϱ, 0, R, φ, 0, 2*pi)
          Through = 2*pi*R^2
  

  $ landau -v ../modules/maxwell.lan
  theory Maxwell
    dim M, L, T, I
    dim Charge = T*I
    dim Force = M*L/T^2
    var r : L, position
    var t : T
    var E(r, t) : M*L/(T^3*I), vector
    var B(r, t) : M/(T^2*I), vector
    var J(r, t) : I/L^2, vector
    var ρ(r, t) : T*I/L^3
    var ε0 : T^4*I^2/(M*L^3), positive
    var μ0 : M*L/(T^2*I^2), positive
    law gauss : div(E) = ρ/ε0   [M/(T^3*I)]
    law gauss_b : div(B) = 0   [M/(L*T^2*I)]
    law faraday : curl(E) = -diff(B, t)   [3-vector M/(T^3*I)]
    law ampere : curl(B) = μ0*J + μ0*ε0*diff(E, t)   [3-vector M/(L*T^2*I)]
    derive current : J = curl(B)/μ0 - ε0*diff(E, t)   [3-vector I/L^2]
        from    Maxwell.ampere
        assumes μ0 > 0, ε0 > 0
        via     solve for J
          J = curl(B)/μ0 - ε0*diff(E, t)
    derive continuity : 0 = μ0*(diff(ρ, t) + div(J))   [M/(L^2*T^2*I)]
        from    Maxwell.gauss, Maxwell.ampere
        assumes μ0 > 0, ε0 > 0
        via     apply div, subst, simplify
          d := 0 = μ0*div(J) + μ0*ε0*diff(div(E), t)
          g := 0 = μ0*div(J) + μ0*ε0*diff(ρ/ε0, t)
          0 = μ0*(diff(ρ, t) + div(J))
    law curl_curl : curl(curl(E)) = grad(div(E)) - lap(E)   [3-vector M/(L*T^3*I)]
    derive curl_curl_holds : 0 = 0   [any]   (holds identically)
        from    Maxwell.curl_curl
        via     expand, simplify
          e := vec(diff(diff(E.y, r.x) - diff(E.x, r.y), r.y) - diff(diff(E.x, r.z) - diff(E.z, r.x), r.z), diff(diff(E.z, r.y) - diff(E.y, r.z), r.z) - diff(diff(E.y, r.x) - diff(E.x, r.y), r.x), diff(diff(E.x, r.z) - diff(E.z, r.x), r.x) - diff(diff(E.z, r.y) - diff(E.y, r.z), r.y)) = vec(diff(diff(E.x, r.x) + diff(E.y, r.y) + diff(E.z, r.z), r.x) - (diff(diff(E.x, r.x), r.x) + diff(diff(E.x, r.y), r.y) + diff(diff(E.x, r.z), r.z)), diff(diff(E.x, r.x) + diff(E.y, r.y) + diff(E.z, r.z), r.y) - (diff(diff(E.y, r.x), r.x) + diff(diff(E.y, r.y), r.y) + diff(diff(E.y, r.z), r.z)), diff(diff(E.x, r.x) + diff(E.y, r.y) + diff(E.z, r.z), r.z) - (diff(diff(E.z, r.x), r.x) + diff(diff(E.z, r.y), r.y) + diff(diff(E.z, r.z), r.z)))
          0 = 0
    derive wave : lap(E) = μ0*ε0*diff(diff(E, t), t)   [3-vector M/(L*T^3*I)]
        from    Maxwell.gauss, Maxwell.curl_curl, Maxwell.ampere, Maxwell.faraday
        assumes μ0 > 0, ε0 > 0
        via     apply curl, subst, subst, subst, simplify
          c := curl(curl(E)) = -diff(curl(B), t)
          a := curl(curl(E)) = -diff(μ0*ε0*diff(E, t), t)
          i := grad(div(E)) - lap(E) = -diff(μ0*ε0*diff(E, t), t)
          g := -lap(E) = -diff(μ0*ε0*diff(E, t), t)
          lap(E) = μ0*ε0*diff(diff(E, t), t)
  
  theory Lorentz
    import Maxwell
    var q : T*I
    var v : L/T, vector
    var F : M*L/T^2, vector
    law lorentz : F = q*(E + cross(v, B))   [3-vector M*L/T^2]
    derive at_rest : F = q*E   [3-vector M*L/T^2]
        from    Lorentz.lorentz
        via     instantiate, simplify
          f := F = q*E
          F = q*E
  
  theory Light
    import Maxwell
    var E0 : M*L/(T^3*I), positive
    var B0 : M/(T^2*I), positive
    var k : 1/L, positive
    var ω : 1/T, positive
    var c : L/T, positive
    def Ew : () -> M*L/(T^3*I)
        shapes  () -> 3-vector
    def Bw : () -> M/(T^2*I)
        shapes  () -> 3-vector
    law faraday_wave : curl(Ew()) = -diff(Bw(), t)   [3-vector M/(T^3*I)]
    law ampere_wave : curl(Bw()) = μ0*ε0*diff(Ew(), t)   [3-vector M/(L*T^2*I)]
    law wave_speed : c = ω/k   [L/T]
    derive speed_of_light : c = 1/(sqrt(μ0)*sqrt(ε0))   [L/T]
        from    Light.faraday_wave, Light.ampere_wave, Light.wave_speed
        assumes E0 > 0, k > 0, ω > 0, B0 > 0, μ0 > 0, ε0 > 0, c > 0
        via     component z, solve for B0, component y, subst, solve for ω, subst, simplify
          f := diff(E0*cos(k*r.x - ω*t), r.x) = -diff(B0*cos(k*r.x - ω*t), t)
          b := B0 = E0*k/ω
          a := -diff(B0*cos(k*r.x - ω*t), r.x) = μ0*ε0*diff(E0*cos(k*r.x - ω*t), t)
          a2 := -diff(E0*k/ω*cos(k*r.x - ω*t), r.x) = μ0*ε0*diff(E0*cos(k*r.x - ω*t), t)
          w := ω = k/(sqrt(μ0)*sqrt(ε0))
          s := c = k/(sqrt(μ0)*sqrt(ε0))/k
          c = 1/(sqrt(μ0)*sqrt(ε0))
  

  $ landau -v ../modules/quantum.lan
  theory Schrodinger
    dim M, L, T
    var ħ : M*L^2/T
    var m : M, positive
    var V : M*L^2/T^2
    var t : T
    var x : L
    var r : L, position
    var ψ(r, t) : 1/L^(3/2), complex
    var k : 1/L, vector
    var ω : 1/T
    law schrodinger : im*ħ*diff(ψ, t) = -ħ^2/(2*m)*lap(ψ) + V*ψ   [M*L^(1/2)/T^2]
    law density : abs(ψ)^2 = 1/x^3   [1/L^3]
    def plane_wave : ('a) -> 'a
        shapes  (scalar) -> scalar | (3-vector) -> 3-vector
  
  theory Dispersion
    import Schrodinger
    var A : 1/L^(3/2), complex
    law wave : im*ħ*diff(plane_wave(A), t) = -ħ^2/(2*m)*lap(plane_wave(A)) + V*plane_wave(A)   [M*L^(1/2)/T^2]
    derive dispersion : ω = (V*m + ħ^2*(k.x^2 + k.y^2 + k.z^2)/2)/(ħ*m)   [1/T]
        from    Dispersion.wave
        assumes m > 0
        via     expand, solve for ω
          e := im*ħ*diff(A*exp(im*(k.x*r.x + k.y*r.y + k.z*r.z - ω*t)), t) = -ħ^2/(2*m)*(diff(diff(A*exp(im*(k.x*r.x + k.y*r.y + k.z*r.z - ω*t)), r.x), r.x) + diff(diff(A*exp(im*(k.x*r.x + k.y*r.y + k.z*r.z - ω*t)), r.y), r.y) + diff(diff(A*exp(im*(k.x*r.x + k.y*r.y + k.z*r.z - ω*t)), r.z), r.z)) + V*A*exp(im*(k.x*r.x + k.y*r.y + k.z*r.z - ω*t))
          ω = (V*m + ħ^2*(k.x^2 + k.y^2 + k.z^2)/2)/(ħ*m)
  

  $ landau -v ../modules/numerical.lan
  theory Kepler
    var E, M, e : 1
    law kepler : M = E - e*sin(E)   [1]
    derive anomaly : E = 1.4987   [1]
        from    Kepler.kepler
        assumes the root near 1
        via     instantiate, solve for E numerically near 1
          k := 1 = E - 1/2*sin(E)
          E = 1.4987
  
  theory Pendulums
    import SI
    const g = 9.81 [m/s^2]   [L/T^2]
    const L = 1 [m]   [L]
    var t : s   [T]
    var θ(t) : 1
    var φ(t) : 1
    law exact : diff(diff(θ, t), t) = -g/L*sin(θ)   [1/T^2]
    law small : diff(diff(φ, t), t) = -g/L*φ   [1/T^2]
    simulate swing: t from 0 to 10 [s], 400 points (DOP853)
        θ: starts at 1.2, ends at -1.16616, between -1.19999 and 1.2
        φ: starts at 1.2, ends at 1.19459, between -1.2 and 1.2
  
  theory Orbit
    import SI
    const GM = 1.32712e20 [m^3/s^2]   [L^3/T^2]
    var t : s   [T]
    var x(t), y(t) : m   [L]
    law ax : diff(diff(x, t), t) = -GM*x/(x^2 + y^2)^(3/2)   [L/T^2]
    law ay : diff(diff(y, t), t) = -GM*y/(x^2 + y^2)^(3/2)   [L/T^2]
    simulate year: t from 0 to 3.156e+07 [s], 400 points (DOP853)
        x: starts at 1.496e+11, ends at 1.49599e+11, between -1.49508e+11 and 1.496e+11 [m]
        y: starts at 0, ends at 4.51313e+08, between -1.49555e+11 and 1.49554e+11 [m]
  

  $ landau -v ../modules/derivatives.lan
  theory Oscillator
    dim M, L, T
    var t : T
    var x(t) : L
    var x0 : L
    var m : M, positive
    var k : M/T^2, positive
    var b : M/T, positive
    var ω : 1/T, positive
    var F : M*L/T^2
    var j : L/T^3
    law damped : m*diff(diff(x, t), t) + b*diff(x, t) + k*x = F   [M*L/T^2]
    law jerk : j = diff(diff(diff(x, t), t), t)   [L/T^3]
    law free : diff(diff(x, t), t) = -ω^2*x   [L/T^2]
    derive motion : x = x0*cos(t*ω)   [L]
        from    Oscillator.free
        assumes ω > 0
        via     solve for x with initial conditions
          x = x0*cos(t*ω)
    derive jolt : j = x0*ω^3*sin(t*ω)   [L/T^3]
        from    Oscillator.free, Oscillator.jerk
        assumes ω > 0
        via     subst, simplify
          s := j = diff(diff(diff(x0*cos(t*ω), t), t), t)
          j = x0*ω^3*sin(t*ω)
  
  theory Orbit
    dim L, T
    var t : T
    var r(t) : L, vector(3)
    var v(t) : L/T, vector(3)
    var R : L, positive
    var ω : 1/T, positive
    law velocity : v = diff(r, t)   [3-vector L/T]
    law circle : r = vec(R*cos(ω*t), R*sin(ω*t), 0)   [3-vector L]
    derive vx : v.x = -R*ω*sin(t*ω)   [L/T]
        from    Orbit.circle, Orbit.velocity
        assumes R > 0, ω > 0
        via     component x, subst, simplify
          c := v.x = diff(r.x, t)
          s := v.x = diff(R*cos(ω*t), t)
          v.x = -R*ω*sin(t*ω)
  
  theory Curve
    dim L
    var x : L
    var y(x) : L
    var a : 1/L
    var s : 1
    law parabola : y = a*x^2   [L]
    law slope : s = diff(y, x)   [1]
    derive steep : s = 2*a*x   [1]
        from    Curve.parabola, Curve.slope
        via     subst, simplify
          q := s = diff(a*x^2, x)
          s = 2*a*x
  
  theory Bead
    dim L, T
    var t : T
    var x(t) : L
    var y(x) : L
    var vy : L/T
    var ay : L/T^2
    law climb : vy = diff(y, t)   [L/T]
    law rise : ay = diff(diff(y, t), t)   [L/T^2]
    derive chain : vy = diff(y, x)*diff(x, t)   [L/T]
        from    Bead.climb
        via     simplify
          vy = diff(y, x)*diff(x, t)
    derive chain2 : ay = diff(x, t)^2*diff(diff(y, x), x) + diff(y, x)*diff(diff(x, t), t)   [L/T^2]
        from    Bead.rise
        via     simplify
          ay = diff(x, t)^2*diff(diff(y, x), x) + diff(y, x)*diff(diff(x, t), t)
  
  theory Wave
    dim L, T
    var x : L
    var t : T
    var c : L/T, positive
    var A : L
    var κ : 1/L
    var u(x, t) : L
    law wave : diff(diff(u, t), t) = c^2*diff(diff(u, x), x)   [L/T^2]
    derive travelling : 0 = 0   [any]   (holds identically)
        from    Wave.wave
        assumes c > 0
        via     instantiate, simplify
          w := diff(diff(A*sin(κ*(x - c*t)), t), t) = c^2*diff(diff(A*sin(κ*(x - c*t)), x), x)
          0 = 0
  

  $ landau -v ../modules/dimensional.lan
  theory Pendulum
    dim M, L, T
    var P : T
    var ℓ : L
    var g : L/T^2
    var m : M
    var θ0 : 1
    groups period : P from ℓ, g, m, θ0
        Π1 = θ0
        Π2 = g*P^2/ℓ
        P = sqrt(ℓ/g)*Φ(θ0)
        m cannot appear: no product of the others has its dimension [M]
  
  theory Drag
    dim M, L, T
    var F : M*L/T^2
    var ρ : M/L^3
    var v : L/T
    var D : L
    var μ : M/(L*T)
    groups drag : F from ρ, v, D, μ
        Π1 = ρ*v*D/μ
        Π2 = F/(ρ*v^2*D^2)
        F = ρ*v^2*D^2*Φ(ρ*v*D/μ)
  
  theory Blast
    dim M, L, T
    var R : L
    var E : M*L^2/T^2
    var ρ : M/L^3
    var t : T
    groups radius : R from E, ρ, t
        Π1 = ρ*R^5/(E*t^2)
        R = C*(E*t^2/ρ)^(1/5)   (C: a dimensionless constant)
  
  theory Orbit
    import Constants
    var P : s   [T]
    var r : m   [L]
    var M : kg   [M]
    groups kepler : P from r, G, M
        Π1 = G*M*P^2/r^3
        P = C*sqrt(r^3/(G*M))   (C: a dimensionless constant)
  
  theory Waves
    import Constants
    var c_w : m/s   [L/T]
    var λ : m   [L]
    var ρ : kg/m^3   [M/L^3]
    groups deep : c_w from g, λ, ρ
        Π1 = c_w^2/(g*λ)
        c_w = C*sqrt(g*λ)   (C: a dimensionless constant)
        ρ cannot appear: no product of the others has its dimension [M/L^3]
  
  theory Planck
    import Constants
    var ℓ_P : m   [L]
    groups length : ℓ_P from ħ, G, c
        Π1 = c^3*ℓ_P^2/(ħ*G)
        ℓ_P = C*sqrt(ħ*G/c^3)   (C: a dimensionless constant)
    compute sqrt(ħ*G/c^3) = 1.616e-35 [m]   [L]
  

  $ landau -v ../modules/series.lan
  theory Zeta
    var Z2, Z4 : 1
    law basel : Z2 = sum(1/k^2, k, 1, inf)   [1]
    law fourth : Z4 = sum(1/k^4, k, 1, inf)   [1]
    derive two : Z2 = pi^2/6   [1]
        from    Zeta.basel
        via     simplify
          Z2 = pi^2/6
    derive four : Z4 = pi^4/90   [1]
        from    Zeta.fourth
        via     simplify
          Z4 = pi^4/90
  
  theory Oscillator
    dim M, L, T
    var ħ : M*L^2/T, positive
    var ω : 1/T, positive
    var β : T^2/(M*L^2), positive
    var Z(β) : 1
    var U : M*L^2/T^2
    law partition : Z = sum(exp(-β*ħ*ω*(k + 1/2)), k, 0, inf)   [1]
    law mean : U = -diff(log(Z), β)   [M*L^2/T^2]
    derive closed : Z = 1/(2*sinh(β*ħ*ω/2))   [1]
        from    Oscillator.partition
        assumes β > 0, ħ > 0, ω > 0
        via     simplify
          Z = 1/(2*sinh(β*ħ*ω/2))
    derive energy : U = ħ*ω/(2*tanh(β*ħ*ω/2))   [M*L^2/T^2]
        from    Oscillator.partition, Oscillator.mean
        assumes β > 0, ħ > 0, ω > 0
        via     subst, simplify
          s := U = -diff(log(1/(2*sinh(β*ħ*ω/2))), β)
          U = ħ*ω/(2*tanh(β*ħ*ω/2))
  
  theory Box
    dim M, L, T
    var n : 1, integer, positive
    var m : M, positive
    var a : L, positive
    var x : L
    var ħ : M*L^2/T
    var k : 1/L
    var E : M*L^2/T^2
    var ψa, N : 1
    law wall : ψa = sin(n*pi)   [1]
    law norm : N = integral(sin(n*pi*x/a)^2, x, 0, a)/a   [1]
    law wave : k = n*pi/a   [1/L]
    law energy : E = ħ^2*k^2/(2*m)   [M*L^2/T^2]
    derive vanishes : ψa = 0   [1]
        from    Box.wall
        assumes n a positive integer
        via     simplify
          ψa = 0
    derive half : N = 1/2   [1]
        from    Box.norm
        assumes n a positive integer, a > 0
        via     simplify
          N = 1/2
    derive levels : E = pi^2*ħ^2*n^2/(2*a^2*m)   [M*L^2/T^2]
        from    Box.wave, Box.energy
        assumes n a positive integer, a > 0, m > 0
        via     subst, simplify
          s := E = ħ^2*(n*pi/a)^2/(2*m)
          E = pi^2*ħ^2*n^2/(2*a^2*m)
  
  theory Square
    var n : 1, integer, positive
    var x, b : 1
    law coefficient : b = 2/pi*integral(sin(n*x), x, 0, pi)   [1]
    derive bn : b = 2*(1 - (-1)^n)/(pi*n)   [1]
        from    Square.coefficient
        assumes n a positive integer
        via     simplify
          b = 2*(1 - (-1)^n)/(pi*n)
    compute sum(4/pi*sin((2*k - 1)*pi/2)/(2*k - 1), k, 1, 200) = 0.9984   [1]
  

  $ landau -v ../modules/matrices.lan
  theory Coupled
    dim M, L, T
    var m : M, positive
    var k, κ : M/T^2, positive
    var ω : 1/T, positive
    var K : M/T^2, matrix(2)
    var Mm : M, matrix(2)
    var x : L, vector(2)
    var F : M*L/T^2, vector(2)
    law stiffness : K = mat(vec(k + κ, -κ), vec(-κ, k + κ))   [2×2-matrix M/T^2]
    law mass : Mm = mat(vec(m, 0), vec(0, m))   [2×2-matrix M]
    law springs : F = -K*x   [2-vector M*L/T^2]
    law modes : det(K - ω^2*Mm) = 0   [M^2/T^4]
    derive forces : F = vec(x.y*κ - x.x*(k + κ), x.x*κ - x.y*(k + κ))   [2-vector M*L/T^2]
        from    Coupled.stiffness, Coupled.springs
        assumes k > 0, κ > 0
        via     subst, simplify
          s := F = mat(vec(-(k + κ), κ), vec(κ, -(k + κ)))*x
          F = vec(x.y*κ - x.x*(k + κ), x.x*κ - x.y*(k + κ))
    derive characteristic : (k - m*ω^2)*(k + 2*κ - m*ω^2) = 0   [M^2/T^4]
        from    Coupled.mass, Coupled.stiffness, Coupled.modes
        assumes k > 0, m > 0, ω > 0, κ > 0
        via     subst, subst, simplify
          a := det(mat(vec(k + κ, -κ), vec(-κ, k + κ)) - ω^2*Mm) = 0
          b := det(mat(vec(k + κ - ω^2*m, -κ), vec(-κ, k + κ - ω^2*m))) = 0
          (k - m*ω^2)*(k + 2*κ - m*ω^2) = 0
    eigen normal : K, Mm
        λ1 = k/m   [1/T^2]
            v = vec(1, 1)
        λ2 = (k + 2*κ)/m   [1/T^2]
            v = vec(1, -1)
  
  theory Inertia
    dim M, L, T
    var A, B, C : M*L^2, positive
    var I : M*L^2, matrix(3)
    var w : 1/T, vector(3)
    var Lw : M*L^2/T, vector(3)
    law tensor : I = mat(vec(A, -B, 0), vec(-B, A, 0), vec(0, 0, C))   [3×3-matrix M*L^2]
    law momentum : Lw = I*w   [3-vector M*L^2/T]
    derive spin : Lw = vec(w.x*A - w.y*B, w.y*A - w.x*B, w.z*C)   [3-vector M*L^2/T]
        from    Inertia.tensor, Inertia.momentum
        assumes A > 0, B > 0, C > 0
        via     subst, simplify
          s := Lw = mat(vec(A, -B, 0), vec(-B, A, 0), vec(0, 0, C))*w
          Lw = vec(w.x*A - w.y*B, w.y*A - w.x*B, w.z*C)
    eigen principal : I
        λ1 = C   [M*L^2]
            v = vec(0, 0, 1)
        λ2 = A - B   [M*L^2]
            v = vec(1, 1, 0)
        λ3 = A + B   [M*L^2]
            v = vec(1, -1, 0)
  
  theory Spin
    dim M, L, T
    var ħ : M*L^2/T, positive
    var ω, Ω : 1/T, positive
    var σx, σz : 1, matrix(2)
    var H : M*L^2/T^2, matrix(2)
    law pauli_x : σx = mat(vec(0, 1), vec(1, 0))   [2×2-matrix 1]
    law pauli_z : σz = mat(vec(1, 0), vec(0, -1))   [2×2-matrix 1]
    law hamiltonian : H = ħ/2*(ω*σz + Ω*σx)   [2×2-matrix M*L^2/T^2]
    derive written : H = mat(vec(ħ*ω/2, ħ*Ω/2), vec(ħ*Ω/2, -ħ*ω/2))   [2×2-matrix M*L^2/T^2]
        from    Spin.pauli_z, Spin.pauli_x, Spin.hamiltonian
        assumes ħ > 0, ω > 0, Ω > 0
        via     subst, subst, simplify
          a := H = ħ/2*(ω*σz + mat(vec(0, Ω), vec(Ω, 0)))
          b := H = mat(vec(ħ/2*ω, ħ/2*Ω), vec(ħ/2*Ω, -ħ/2*ω))
          H = mat(vec(ħ*ω/2, ħ*Ω/2), vec(ħ*Ω/2, -ħ*ω/2))
    eigen levels : H
        λ1 = -ħ*sqrt(ω^2 + Ω^2)/2   [M*L^2/T^2]
            v = vec(1, Ω/(ω - sqrt(ω^2 + Ω^2)))
        λ2 = ħ*sqrt(ω^2 + Ω^2)/2   [M*L^2/T^2]
            v = vec(1, Ω/(ω + sqrt(ω^2 + Ω^2)))
  

  $ landau -v ../modules/errors.lan
  theory Broken
    dim L, T
    var x : L
    var v : L/T
    var t : T
  ../modules/errors.lan:9: error: cannot add `v*t` [L] and `v` [L/T]
  ../modules/errors.lan:10: error: the argument of `exp` must be dimensionless, but `t` is [T]
  ../modules/errors.lan:11: error: the two sides have different dimensions: `x` is [L] but `v` is [L/T]
  ../modules/errors.lan:12: error: the exponent `x` must be dimensionless, but it is [L]
    def speed : ('a, 'b) -> 'a/'b
  ../modules/errors.lan:15: error: cannot add `speed(t, x)` [T/L] and `x` [L]
  
  theory BrokenVectors
    dim M, L, T
    var m : M
    var s : L/T
    var v, u : L/T, vector
    var p : L*M/T, vector
  ../modules/errors.lan:27: error: the two sides have different shapes: `p` is a 3-vector but `m*s` is a scalar
  ../modules/errors.lan:28: error: cannot multiply two vectors `m*v` and `u`: use dot(...) or cross(...)
  ../modules/errors.lan:29: error: `abs` needs a scalar, but `v` is a vector (use norm(v))
  
  [1]
