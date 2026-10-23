(* Theories that come with Landau; `import SI` loads the one of that name.

   SI names its dimensions in words and shows them by their usual symbols,
   so that T, N and J are free for tesla, newton and joule. *)

let si =
  {|
theory SI
  dim Mass (M), Length (L), Time (T), Current (I), Temperature (Θ), Amount (N), Luminosity (J)

  unit kg : Mass, m : Length, s : Time, A : Current, K : Temperature, mol : Amount, cd : Luminosity

  -- derived units with their own names
  unit N = kg*m/s^2, J = N*m, W = J/s, Pa = N/m^2
  unit C = A*s, V = W/A, Ω = V/A, F = C/V, S = A/V, Wb = V*s, T = Wb/m^2, H = Wb/A
  unit Hz = 1/s, Bq = 1/s, Gy = J/kg, Sv = J/kg, rad = 1, sr = 1
  unit deg = pi/180*rad                -- a degree, exactly; sin(30 [deg]) is 1/2

  -- scaled units
  unit g = 0.001*kg, km = 1000*m, cm = 0.01*m, mm = 0.001*m, nm = 1e-9*m
  unit min = 60*s, h = 3600*s, ms = 0.001*s
  unit kJ = 1000*J, MJ = 1e6*J, eV = 1.602176634e-19*J, atm = 101325*Pa, bar = 100000*Pa
  unit kN = 1000*N, kPa = 1000*Pa, MPa = 1e6*Pa, kW = 1000*W, MW = 1e6*W
  unit mA = 0.001*A, kV = 1000*V, μC = 1e-6*C, nC = 1e-9*C, μF = 1e-6*F, pF = 1e-12*F, mH = 0.001*H, mT = 0.001*T
end
|}

(* Physical constants in SI: exact where the SI defines them (c, h, e, k_B,
   N_A), CODATA 2018 otherwise. Symbolically they stay names; `evaluate`
   uses their values. *)
let constants =
  {|
theory Constants
  import SI
  const c = 299792458 [m/s]                  -- speed of light
  const G = 6.67430e-11 [N*m^2/kg^2]         -- gravitational constant
  const h = 6.62607015e-34 [J*s]             -- Planck constant
  const ħ = 1.054571817e-34 [J*s]            -- reduced Planck constant
  const e = 1.602176634e-19 [C]              -- elementary charge
  const k_B = 1.380649e-23 [J/K]             -- Boltzmann constant
  const N_A = 6.02214076e23 [1/mol]          -- Avogadro constant
  const R_gas = 8.314462618 [J/(mol*K)]      -- gas constant
  const ε0 = 8.8541878128e-12 [F/m]          -- vacuum permittivity
  const μ0 = 1.25663706212e-6 [H/m]          -- vacuum permeability
  const k_e = 8.9875517923e9 [N*m^2/C^2]     -- Coulomb constant, 1/(4 pi ε0)
  const m_e = 9.1093837015e-31 [kg]          -- electron mass
  const m_p = 1.67262192369e-27 [kg]         -- proton mass
  const m_n = 1.67492749804e-27 [kg]         -- neutron mass
  const σ_SB = 5.670374419e-8 [W/(m^2*K^4)]  -- Stefan-Boltzmann constant
  const g = 9.80665 [m/s^2]                  -- standard gravity
end
|}

let theories = [ ("SI", si); ("Constants", constants) ]
