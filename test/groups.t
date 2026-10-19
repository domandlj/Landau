Dimensionless groups (Buckingham π): `groups name: vars` and
`groups name: target from vars`. The modules file has the textbook cases
(pendulum, drag, blast wave, Kepler, deep water waves, Planck length).

  $ landau cases/groups/groups.lan
  theory Many
    dim M, L, T
    var ρ : M/L^3
    var v : L/T
    var D, h : L
    var μ : M/(L*T)
    var u : L/T, vector(3)
    var α : 1
    groups flow : ρ, v, D, μ, h, u, α
        Π1 = ρ*v*D/μ
        Π2 = h/D
        Π3 = u/v
        Π4 = α
  
  theory Independent
    dim M, L, T
    var m : M
    var x : L
    var t : T
    groups none : m, x, t
        no dimensionless groups
        m cannot appear: no product of the others has its dimension [M]
        x cannot appear: no product of the others has its dimension [L]
        t cannot appear: no product of the others has its dimension [T]
  
  theory Fractional
    dim M, L, T
    var f : 1/T
    var F : M*L/T^2
    var λ : M/L
    var ℓ : L
    groups string : f from F, λ, ℓ
        Π1 = λ*ℓ^2*f^2/F
        f = C*sqrt(F/(λ*ℓ^2))   (C: a dimensionless constant)
  

Errors: a target no product of the others can match, a variable listed
twice, an unknown name.

  $ landau cases/groups/errors.lan
  theory E
    dim M, L, T
    var x : L
    var m : M
    var t : T
  cases/groups/errors.lan:6: error: no product of `x`, `m` has the dimension of `t` [T], so it cannot be found from them
  cases/groups/errors.lan:7: error: `x` is listed twice
  cases/groups/errors.lan:8: error: `x` is listed twice
  cases/groups/errors.lan:9: error: unknown variable `y`
    def d : ('a) -> 'a
  cases/groups/errors.lan:11: error: unknown variable `d`
  
  [1]
