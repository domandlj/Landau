Systems of equations.

  $ landau cases/systems/systems.lan
  theory Collision
    dim M, L, T
    var m1, m2 : M, positive
    var v1, v2 : L/T
    var u1, u2 : L/T
    law momentum : m1*v1 + m2*v2 = m1*u1 + m2*u2   [M*L/T]
    law energy : m1*v1^2/2 + m2*v2^2/2 = m1*u1^2/2 + m2*u2^2/2   [M*L^2/T^2]
    derive try_it : u1 = (v1*m1 - v1*m2 + 2*v2*m2)/(m1 + m2)   [L/T]
        from    Collision.momentum, Collision.energy
        assumes m1 > 0, m2 > 0
        via     solve for u1, u2
  
  theory Circuit
    dim M, L, T, I
    dim Volt = M*L^2/(T^3*I)
    dim Ohm = M*L^2/(T^3*I^2)
    var ε1, ε2 : M*L^2/(T^3*I)
    var R1, R2, R3 : M*L^2/(T^3*I^2), positive
    var I1, I2, I3 : I
    law junction : I1 + I2 = I3   [I]
    law loop1 : ε1 = I1*R1 + I3*R3   [M*L^2/(T^3*I)]
    law loop2 : ε2 = I2*R2 + I3*R3   [M*L^2/(T^3*I)]
    derive current3 : I3 = (ε1*R2 + ε2*R1)/(R1*R3 + R1*R2 + R3*R2)   [I]
        from    Circuit.junction, Circuit.loop1, Circuit.loop2
        assumes R1 > 0, R3 > 0, R2 > 0
        via     solve for I3, I1, I2
  
  theory Collision2D
    dim M, L, T
    var m : M, positive
    var v : L/T, positive
    var u1, u2 : L/T, vector(2)
    var a, b : L/T
    law momentum : m*vec(v, 0) = m*u1 + m*u2   [2-vector M*L/T]
    derive split : b = v - a   [L/T]
        from    Collision2D.momentum
        assumes m > 0, v > 0
        via     instantiate, solve for b, a
  
  theory Bad
    dim L, T
    var x, y : L
    var t : T
    var p : L, vector
    var f(t) : L
    law a : x + y = 2*x   [L]
    law b : x - y = 0   [L]
    law c : diff(f, t) = x/t   [L/T]
  cases/systems/systems.lan:52: error: solve for the components of the vector `p`, such as p.x
  cases/systems/systems.lan:55: error: systems of differential equations are not supported yet
  cases/systems/systems.lan:58: error: initial conditions need a single differential equation
  cases/systems/systems.lan:61: error: there is no root 5; the system has 1 solution
  
  [1]

  $ landau cases/systems/free_unknown.lan
    dim L
    var x, y : L
    law a : x + y = 2*x   [L]
    derive e : x = y   [L]
        from    Main.a
        via     solve for x, y
