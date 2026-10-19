Vectors: components, sizes, 4-vectors, and the errors for misusing them.
diff_through_dot guards a fixed bug: a derivative through dot(k, r) used to be
0 because SymPy saw r as one opaque symbol.

  $ landau -v cases/vectors/components.lan
  theory Ok
    dim M, L, T
    var r : L, position
    var a, b : L, vector
    var s, d : L
    var F : M*L/T^2, vector
    var τ : M*L^2/T^2, vector
    var E : M*L^2/T^2
    law len : s = norm(vec(3, 4)*d)   [L]
    law torque : τ = cross(r, F)   [3-vector M*L^2/T^2]
    law work : E = dot(F, a)   [M*L^2/T^2]
    law ax : s = a.x + b.y   [L]
  cases/vectors/components.lan:14: error: `grad(E)` is always 0, because `E` does not depend on `r`; declare the dependence, e.g. `var E(r) : ...`
    derive len5 : s = 5*abs(d)   [L]
        from    Ok.len
        via     simplify
          s = 5*abs(d)
    derive tz : τ.z = r.x*F.y - r.y*F.x   [M*L^2/T^2]
        from    Ok.torque
        via     component z
          τ.z = r.x*F.y - r.y*F.x
    derive work_xyz : E = F.x*a.x + F.y*a.y + F.z*a.z   [M*L^2/T^2]
        from    Ok.work
        via     expand
          E = F.x*a.x + F.y*a.y + F.z*a.z
  cases/vectors/components.lan:26: error: unknown law `curlfree`
  
  theory FourVectors
    dim L, T
    var c : L/T, positive
    var t : T
    var x : L, vector(4)
    var X : L, vector(4)
    law event : X = vec(c*t, x.2, x.3, x.4)   [4-vector L]
    derive time : t = X.1/c   [T]
        from    FourVectors.event
        assumes c > 0
        via     component 1, solve for t
          e := X.1 = c*t
          t = X.1/c
  
  theory Bad
    dim L, T
    var r2 : L, position(2)
    var p, q : L, vector(2)
    var w : L, vector
    var s : L
    var t : T
  cases/vectors/components.lan:51: error: the two sides have different shapes: `p` is a 2-vector but `w` is a 3-vector
  cases/vectors/components.lan:52: error: `dot` needs vectors of the same size, but `p` is a 2-vector and `w` a 3-vector
  cases/vectors/components.lan:53: error: `cross` needs a 3-vector, but `p` is a 2-vector
  cases/vectors/components.lan:54: error: `curl` exists only in 3 dimensions, but the position `r2` is a 2-vector
  cases/vectors/components.lan:55: error: `p` is a 2-vector and has no component z
  cases/vectors/components.lan:56: error: the components of a vector must have the same dimension, but `s` is [L] and `t` is [T]
  cases/vectors/components.lan:57: error: `s` is a scalar and has no components
  
  [1]

  $ landau cases/vectors/errors.lan
    dim M, L, T
    var r : L, position
    var m : M, positive
    var t : T
    var v, u : L/T, vector
    var p : M*L/T, vector
    var s : L/T
    var φ : M*L^2/T^2
    law ok1 : p = m*v   [3-vector M*L/T]
  cases/vectors/errors.lan:11: error: `curl(v)` is always 0, because `v` does not depend on `r`; declare the dependence, e.g. `var v(r) : ...`
    law ok3 : s = norm(v)   [L/T]
  cases/vectors/errors.lan:13: error: the two sides have different shapes: `p` is a 3-vector but `m*s` is a scalar
  cases/vectors/errors.lan:14: error: cannot multiply two vectors `m*v` and `u`: use dot(...) or cross(...)
  cases/vectors/errors.lan:15: error: cannot divide by the vector `v`
  cases/vectors/errors.lan:16: error: the vector `v` cannot be raised to a power: use dot(v, v) or norm(v)^k
  cases/vectors/errors.lan:17: error: `sin` needs a scalar, but `v/s` is a vector
  cases/vectors/errors.lan:18: error: `abs` needs a scalar, but `v` is a vector (use norm(v))
  cases/vectors/errors.lan:19: error: `grad` needs a scalar, but `v` is a vector
  cases/vectors/errors.lan:20: error: `div` needs a vector, but `s` is a scalar
  cases/vectors/errors.lan:21: error: `diff` differentiates by a variable or one of its components, but got `2*t`
  cases/vectors/errors.lan:22: error: `diff` differentiates by a scalar, but `r` is a vector
    def f : ('a, 'b) -> 'a*'b
        shapes  (3-vector, 3-vector) -> scalar
  cases/vectors/errors.lan:24: error: in `f(s, s)`: `dot` needs a vector, but `a` is a scalar
  cases/vectors/errors.lan:25: error: `curl` is a built-in function; choose another name
  cases/vectors/errors.lan:26: error: a vector cannot be `positive` (only scalars are ordered)
  cases/vectors/errors.lan:27: error: a theory can have only one position vector, but `r` and `r2` both are
  cases/vectors/errors.lan:29: error: cannot solve a vector equation for the scalar `m`: take dot(...) or norm(...) of both sides first
  cases/vectors/errors.lan:32: error: cannot solve a scalar equation for the vector `v`
  cases/vectors/errors.lan:35: error: cannot put `s` (a scalar) in place of `v` (a 3-vector)
  [1]

  $ landau cases/vectors/sizes.lan
    dim L
  cases/vectors/sizes.lan:2: error: the size in `vector(0)` must be a whole number, at least 1
  cases/vectors/sizes.lan:3: error: `positive` takes no size
  cases/vectors/sizes.lan:4: error: the size in `vector(5/2)` must be a whole number, at least 1
  [1]

  $ landau cases/vectors/diff_through_dot.lan
    dim L
    var r : L, position
    var k : 1/L, vector
    var s : 1
    law p : s = diff(dot(k, r), r.x)*r.x   [1]
    derive bug : s = k.x*r.x   [1]
        from    Main.p
        via     simplify

  $ landau cases/vectors/diff_of_position.lan
    dim L
    var r : L, position
    var s : 1
    var t : L
    law p : vec(s, s, s) = diff(r, r.y)*t/t   [3-vector 1]
    law q : s = diff(norm(r), r.x)*norm(r)/r.x   [1]
    derive a : vec(s, s, s) = vec(0, 1, 0)   [3-vector 1]
        from    Main.p
        via     simplify
    derive b : s = norm(r)/sqrt(r.x^2 + r.y^2 + r.z^2)   [1]
        from    Main.q
        via     simplify
