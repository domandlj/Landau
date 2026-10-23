(* Shapes: every expression is a scalar, an n-vector or an n×n matrix.

   This is checked separately from dimensions, because the two never
   interact: dot(a, b) and cross(a, b) have the dimension of a*b whatever
   their shapes. The literal 0 has every shape, as it has every dimension. *)

open Syntax
open Printf

type t = Scalar | Vector of int | Matrix of int

(* [Zero] is the shape of 0 and its multiples: it fits anywhere. *)
type s = S | V of int | M of int | Zero

let to_string = function Scalar -> "scalar" | Vector n -> sprintf "%d-vector" n | Matrix n -> sprintf "%d×%d-matrix" n n
let of_s = function V n -> Vector n | M n -> Matrix n | S | Zero -> Scalar
let to_s = function Vector n -> V n | Matrix n -> M n | Scalar -> S
let s_name = function V n -> sprintf "%d-vector" n | M n -> sprintf "%d×%d matrix" n n | S -> "scalar" | Zero -> "zero"

(* The shapes a definition was found to accept, for display. *)
type table = (t list * t) list

type env = {
  var_shape : string -> t option;
  def_body : string -> (string list * expr) option;
  position : (string * int) option; (* the position vector and its size *)
  var_deps : string -> string list;
  locals : (string * s) list;
}

let fail fmt = ksprintf (fun m -> raise (Infer.Error m)) fmt
let show = Pretty.expr

let position env f =
  match env.position with
  | Some p -> p
  | None -> fail "`%s` needs a position vector: declare one with `var r : L, position`" f

let rec infer env e =
  match e with
  | Num q -> if Q.equal q Q.zero then Zero else S
  | Const _ | Quantity _ -> S
  | Var x -> (
      match List.assoc_opt x env.locals with
      | Some s -> s
      | None -> Option.fold ~none:S ~some:to_s (env.var_shape x))
  | Neg a -> infer env a
  | Add (a, b) | Sub (a, b) -> (
      match (infer env a, infer env b) with
      | Zero, s | s, Zero -> s
      | sa, sb when sa = sb -> sa
      | sa, sb ->
          fail "cannot %s `%s` (a %s) and `%s` (a %s)"
            (match e with Add _ -> "add" | _ -> "subtract")
            (show a) (s_name sa) (show b) (s_name sb))
  | Mul (a, b) -> (
      match (infer env a, infer env b) with
      | V _, V _ -> fail "cannot multiply two vectors `%s` and `%s`: use dot(...) or cross(...)" (show a) (show b)
      | V _, M _ -> fail "a vector times a matrix, `%s*%s`, is not defined here: write the matrix first, `%s*%s`" (show a) (show b) (show b) (show a)
      | M n, V m when n <> m -> fail "cannot multiply the %d×%d matrix `%s` by the %d-vector `%s`" n n (show a) m (show b)
      | M n, M m when n <> m -> fail "cannot multiply the %d×%d matrix `%s` by the %d×%d matrix `%s`" n n (show a) m m (show b)
      | Zero, _ | _, Zero -> Zero
      | M _, (V _ as v) -> v
      | (M _ as m), _ | _, (M _ as m) -> m
      | (V _ as v), _ | _, (V _ as v) -> v
      | S, S -> S)
  | Div (a, b) ->
      (match infer env b with
      | V _ -> fail "cannot divide by the vector `%s`" (show b)
      | M _ -> fail "cannot divide by the matrix `%s`: multiply by inv(%s)" (show b) (show b)
      | _ -> ());
      infer env a
  | Pow (a, b) -> (
      (match infer env b with V _ | M _ -> fail "the exponent `%s` is not a number" (show b) | _ -> ());
      match infer env a with
      | V _ -> fail "the vector `%s` cannot be raised to a power: use dot(%s, %s) or norm(%s)^k" (show a) (show a) (show a) (show a)
      | M _ -> fail "write powers of the matrix `%s` as products, `%s*%s`" (show a) (show a) (show a)
      | s -> s)
  | Call ("sum", [ f; Var k; a; b ]) ->
      List.iter (fun x -> if infer env x <> S && infer env x <> Zero then fail "the bounds of `sum` are numbers, but `%s` is a vector" (show x)) [ a; b ];
      infer { env with locals = (k, S) :: env.locals } f
  | Call (f, args) -> infer_call env f args

and infer_call env f args =
  let shapes = List.map (infer env) args in
  let scalar a s =
    match s with
    | V _ ->
        fail "`%s` needs a scalar, but `%s` is a vector%s" f (show a)
          (if f = "abs" then sprintf " (use norm(%s))" (show a) else "")
    | M _ -> fail "`%s` needs a scalar, but `%s` is a matrix" f (show a)
    | _ -> ()
  in
  let square a s =
    match s with
    | M n -> n
    | _ -> fail "`%s` needs a square matrix, but `%s` is a %s" f (show a) (s_name s)
  in
  let vector ?size a s =
    match (s, size) with
    | S, _ -> fail "`%s` needs a vector, but `%s` is a scalar" f (show a)
    | M _, _ -> fail "`%s` needs a vector, but `%s` is a matrix" f (show a)
    | V n, Some m when n <> m -> fail "`%s` needs a %d-vector, but `%s` is a %d-vector" f m (show a) n
    | _ -> ()
  in
  let same_size a sa b sb =
    match (sa, sb) with
    | V n, V m when n <> m -> fail "`%s` needs vectors of the same size, but `%s` is a %d-vector and `%s` a %d-vector" f (show a) n (show b) m
    | _ -> ()
  in
  match (f, args, shapes) with
  | "dot", [ a; b ], [ sa; sb ] ->
      vector a sa; vector b sb; same_size a sa b sb; S
  | "cross", [ a; b ], [ sa; sb ] ->
      vector ~size:3 a sa; vector ~size:3 b sb; V 3
  | "norm", [ a ], [ s ] -> vector a s; S
  | "grad", [ a ], [ s ] ->
      let _, n = position env f in
      scalar a s; V n
  | "div", [ a ], [ s ] ->
      let _, n = position env f in
      vector ~size:n a s; S
  | "curl", [ a ], [ s ] ->
      let r, n = position env f in
      if n <> 3 then fail "`curl` exists only in 3 dimensions, but the position `%s` is a %d-vector" r n;
      vector ~size:3 a s; V 3
  | "lap", [ _ ], [ s ] -> ignore (position env f); s
  | "diff", [ _; x ], [ s; sx ] ->
      (match x with
      | Var _ | Call ("comp", [ Var _; _ ]) -> ()
      | _ -> fail "`diff` differentiates by a variable or one of its components, but got `%s`" (show x));
      (match sx with V _ -> fail "`diff` differentiates by a scalar, but `%s` is a vector" (show x) | _ -> ());
      s
  | "vec", _, _ ->
      if List.length args < 2 then fail "`vec` needs at least 2 components";
      List.iter2 scalar args shapes;
      V (List.length args)
  | "mat", _, _ ->
      (* mat(vec(a, b), vec(c, d)): its rows, as many as each has entries *)
      let n = List.length args in
      if n < 2 then fail "`mat` needs at least 2 rows, each a vec(...)";
      List.iter2
        (fun a s ->
          match (a, s) with
          | Call ("vec", _), V m when m = n -> ()
          | Call ("vec", _), V m -> fail "a %d×%d matrix needs rows of %d entries, but `%s` has %d" n n n (show a) m
          | _ -> fail "the rows of `mat` are written vec(...), but got `%s`" (show a))
        args shapes;
      M n
  | "identity", [ Num q ], _ when Q.to_int q >= 2 && Q.equal q (Q.of_int (Q.to_int q)) -> M (Q.to_int q)
  | "identity", _, _ -> fail "`identity(n)` takes the size n, a whole number of at least 2"
  | ("det" | "trace"), [ a ], [ s ] -> ignore (square a s); S
  | ("inv" | "transpose"), [ a ], [ s ] -> M (square a s)
  | "entry", [ a; Num i; Num j ], [ s; _; _ ] ->
      let n = square a s and i = Q.to_int i and j = Q.to_int j in
      if i < 1 || i > n || j < 1 || j > n then fail "`%s` is %d×%d, so it has no entry (%d, %d)" (show a) n n i j;
      S
  | "entry", _, _ -> fail "`entry(A, i, j)` takes a matrix and two whole numbers"
  | "comp", [ a; Num q ], [ s; _ ] -> (
      let k = Q.to_int q in
      match s with
      | V n when k > n -> fail "`%s` is a %d-vector and has no component %s" (show a) n (component_name k)
      | V _ | Zero -> S
      | S -> fail "`%s` is a scalar and has no components" (show a)
      | M _ -> fail "`%s` is a matrix: take an entry with entry(%s, i, j)" (show a) (show a))
  | "integral", f :: x :: bounds, sf :: sx :: sbounds ->
      (match x with
      | Var _ | Call ("comp", [ Var _; _ ]) -> ()
      | _ -> fail "`integral` integrates over a variable or one of its components, but got `%s`" (show x));
      (match sx with V _ -> fail "`integral` integrates over a scalar, but `%s` is a vector" (show x) | _ -> ());
      List.iter2 scalar bounds sbounds;
      ignore f;
      sf
  | ("line" | "loop" | "surface" | "volume"), f_ :: q :: rest, sf :: sq :: srest ->
      let r, n = position env f in
      let dims = match f with "line" | "loop" -> 1 | "surface" -> 2 | _ -> 3 in
      if List.length rest <> 3 * dims then S (* arity: reported by dimension inference *)
      else (
        if dims > 1 && n <> 3 then fail "`%s` needs 3-dimensional space, but the position `%s` is a %d-vector" f r n;
        vector ~size:n q sq;
        List.iteri
          (fun i (a, sa) ->
            if i mod 3 = 0 then (
              match a with
              | Var _ -> scalar a sa
              | _ -> fail "the parameters of `%s` must be variables, but got `%s`" f (show a))
            else scalar a sa)
          (List.combine rest srest);
        match (f, sf) with
        | ("line" | "loop" | "surface"), V m when m <> n -> fail "`%s` needs a %d-vector field, but `%s` is a %d-vector" f n (show f_) m
        | ("line" | "loop" | "surface"), _ -> S (* F·dr and F·dA, or f dl and f dA *)
        | _, s -> s (* a volume integral keeps the shape of its integrand *))
  | "at", [ _; x; a ], [ se; sx; sa ] ->
      (match x with
      | Var _ | Call ("comp", [ Var _; _ ]) -> ()
      | _ -> fail "`at` sets a variable or one of its components, but got `%s`" (show x));
      (match (sx, sa) with
      | _, Zero -> ()
      | sx, sa when sx <> sa -> fail "`at` puts `%s` (a %s) in place of `%s` (a %s)" (show a) (s_name sa) (show x) (s_name sx)
      | _ -> ());
      se
  | _ when env.var_shape f <> None && env.var_deps f <> [] ->
      let n = List.length (env.var_deps f) in
      if List.length args <> n then
        fail "`%s` depends on %d variable(s), so `%s` needs %d argument(s)" f n (show (Call (f, args))) n;
      List.iter2
        (fun (a, sa) d ->
          let sd = Option.fold ~none:S ~some:to_s (env.var_shape d) in
          if sa <> Zero && sa <> sd then fail "in `%s`, `%s` is a %s but stands for `%s`, a %s" (show (Call (f, args))) (show a) (s_name sa) d (s_name sd))
        (List.combine args shapes) (env.var_deps f);
      Option.fold ~none:S ~some:to_s (env.var_shape f)
  | ( "dot" | "cross" | "norm" | "grad" | "div" | "curl" | "lap" | "diff" | "comp" | "integral" | "at" | "line" | "loop"
    | "surface" | "volume" | "det" | "trace" | "inv" | "transpose" ), _, _ ->
      S (* wrong arity: reported by dimension inference *)
  | _ -> (
      match env.def_body f with
      | Some (params, body) when List.length params = List.length args -> (
          (* Definitions are checked at each use with the actual shapes, so
             they work for vectors of any size. *)
          try infer { env with locals = List.combine params shapes } body
          with Infer.Error m -> fail "in `%s`: %s" (show (Call (f, args))) m)
      | _ ->
          List.iter2 scalar args shapes;
          S)

(* Every combination of scalar and the given vector sizes, fewest vectors first. *)
let combos sizes n =
  let opts = Scalar :: List.map (fun k -> Vector k) sizes in
  let rec go n = if n = 0 then [ [] ] else List.concat_map (fun c -> List.map (fun o -> o :: c) opts) (go (n - 1)) in
  let vectors c = List.length (List.filter (( <> ) Scalar) c) in
  List.stable_sort (fun a b -> compare (vectors a) (vectors b)) (go n)

(* The argument shapes a definition accepts, among scalars and the vector
   sizes in scope. If none work, the error is the one from all scalars. *)
let infer_def env sizes params body : table =
  let try_ ps = of_s (infer { env with locals = List.combine params (List.map to_s ps) } body) in
  let table =
    List.filter_map (fun ps -> try Some (ps, try_ ps) with Infer.Error _ -> None) (combos sizes (List.length params))
  in
  if table = [] then ignore (try_ (List.map (fun _ -> Scalar) params));
  table

let table_to_string (t : table) =
  String.concat " | "
    (List.map (fun (ps, r) -> "(" ^ String.concat ", " (List.map to_string ps) ^ ") -> " ^ to_string r) t)

(* Both sides of an equation must have the same shape. *)
let check_eq env q =
  match (infer env q.lhs, infer env q.rhs) with
  | Zero, s | s, Zero -> of_s s
  | sl, sr when sl = sr -> of_s sl
  | sl, sr ->
      fail "the two sides have different shapes: `%s` is a %s but `%s` is a %s" (show q.lhs) (s_name sl)
        (show q.rhs) (s_name sr)
