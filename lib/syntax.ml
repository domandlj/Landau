(* Abstract syntax of Landau files. *)

exception Syntax_error of string

(* Dimension expressions as written: L/T^2, M*L^2/T^2, 1, L^(-3/2) *)
type dexpr =
  | DOne
  | DNum of Q.t (* a scale factor, as in unit km = 1000*m; not allowed in a dimension *)
  | DName of string
  | DMul of dexpr * dexpr
  | DDiv of dexpr * dexpr
  | DPow of dexpr * Q.t

type expr =
  | Num of Q.t
  | Var of string
  | Const of string (* pi, im, inf *)
  | Neg of expr
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr
  | Pow of expr * expr
  | Call of string * expr list
  | Quantity of Q.t * dexpr (* 9.81 [m/s^2]: a number with a unit *)

type eq = { lhs : expr; rhs : expr }

(* Components are written v.x, v.y, v.z or v.1, v.2, ...; inside they are
   comp(v, k) with k counted from 1. *)
let component_index = function
  | "x" -> Some 1
  | "y" -> Some 2
  | "z" -> Some 3
  | s -> ( match int_of_string_opt s with Some k when k >= 1 -> Some k | _ -> None)

let component_name k = match k with 1 -> "x" | 2 -> "y" | 3 -> "z" | _ -> string_of_int k

(* Derivation steps: each one denotes an equation. *)
type step_expr =
  | Ref of string option * string (* law, or Theory.law *)
  | Inst of step_expr * (string * expr) list (* law[x := e, ...] *)
  | Solve of step_expr list * string list * int option * eq list
      (* solve e1, e2 for x, y, root k, with x(0) = x0 *)
  | Subst of step_expr * step_expr (* subst (x = e) into eq *)
  | Simplify of step_expr
  | Unfold of step_expr
  | Component of step_expr * int * string (* component x of eq: index from 1, and the name as written *)
  | Expand of step_expr (* write dot, cross, norm, grad, div, curl and lap in components *)
  | Differentiate of step_expr * string (* differentiate eq by t *)
  | Evaluate of step_expr * dexpr option * int option (* evaluate eq in km/h digits 3 *)
  | Approximate of step_expr * (string * expr) list * int option (* approximate eq where v << c order 2 *)
  | Limit of step_expr * string * expr (* limit eq as t -> inf *)
  | NSolve of step_expr * string * expr * int option (* solve eq for x numerically near 2 [s] digits 4 *)
  | Apply of string * step_expr (* apply curl to eq *)
  | Integrate of step_expr * string * expr * expr (* integrate eq by t from a to b *)
  | EulerLagrange of step_expr * string (* euler_lagrange L for x: d/dt ∂L/∂ẋ - ∂L/∂x = 0 *)
  | Conserved of step_expr * string (* conserved L for t (the energy) or for x (its momentum) *)

type step = { name : string option; body : step_expr; sline : int }

(* unit kg : Mass declares the base unit of a dimension; unit N = kg*m/s^2 a
   named combination, possibly scaled: unit km = 1000*m *)
and unit_def = UBase of dexpr | UDerived of dexpr

(* A free-body diagram: the forces on a body, from which Newton's second law
   is written, and a picture is drawn. *)
type diagram_item =
  | Body of expr (* body m: its mass *)
  | Force of string * expr option * expr (* force W = m*g toward down; no magnitude: the variable W *)
  | Accelerates of expr * expr option (* accelerates a toward d; or a vector *)
  | Plane of expr (* plane angle(α): the surface, for the picture *)
  | Draw of (string * expr) list (* draw α = 0.5: values for the picture only *)
  | Mark of expr * expr * expr (* mark α between plane and right: an angle to show, and check *)

(* simulate name: laws for x, y from t = 0 [s] to 10 [s] with x(0) = ..., ... points 400 *)
type simulation = {
  sname : string;
  laws : step_expr list;
  unknowns : string list;
  over : string; (* the independent variable, t *)
  t0 : expr;
  t1 : expr;
  initial : eq list;
  points : int option;
}

type decl_desc =
  | Import of string * string option (* import Theory, or import Theory from module *)
  | DimBase of (string * string option) list (* dim Time (T): the name, and how it is shown *)
  | Units of (string * unit_def) list
  | ConstDecl of (string * Q.t * dexpr) list (* const g = 9.81 [m/s^2] *)
  | Compute of string option * expr * dexpr option * int option (* compute E1 = f(2 [kg]) in J digits 3 *)
  | Simulate of simulation
  | Groups of string * string option * string list (* groups period: T from L, g, m *)
  | Eigen of string * expr * expr option (* eigen modes: K, M -- K v = λ M v *)
  | Diagram of string * diagram_item list
  | DimAlias of string * dexpr
  | VarDecl of (string * string list) list * dexpr * string list (* x(t), x0 : L, positive *)
  | Def of string * (string * dexpr option) list * expr
  | Law of string * eq
  | Derive of string * step list
  | Text of string (* text ... end: prose with $math$, shown as written *)

type decl = { desc : decl_desc; line : int }
type item = Theory of string * decl list | Top of decl

let children = function
  | Num _ | Var _ | Const _ | Quantity _ -> []
  | Neg a -> [ a ]
  | Add (a, b) | Sub (a, b) | Mul (a, b) | Div (a, b) | Pow (a, b) -> [ a; b ]
  | Call (_, args) -> args

let map_children f = function
  | (Num _ | Var _ | Const _ | Quantity _) as e -> e
  | Neg a -> Neg (f a)
  | Add (a, b) -> Add (f a, f b)
  | Sub (a, b) -> Sub (f a, f b)
  | Mul (a, b) -> Mul (f a, f b)
  | Div (a, b) -> Div (f a, f b)
  | Pow (a, b) -> Pow (f a, f b)
  | Call (g, args) -> Call (g, List.map f args)

(* Variables of an expression, in order of first appearance. *)
let rec vars acc = function
  | Var x -> if List.mem x acc then acc else acc @ [ x ]
  | e -> List.fold_left vars acc (children e)

let map_eq f q = { lhs = f q.lhs; rhs = f q.rhs }
