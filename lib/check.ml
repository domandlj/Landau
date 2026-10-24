(* Checking a Landau file: theories, declarations and derivations. *)

open Syntax
open Printf

exception Located of int * string

let fail fmt = ksprintf (fun s -> raise (Infer.Error s)) fmt

type var_info = {
  vdim : Dim.t;
  attrs : string list;
  deps : string list; (* x(t) depends on t *)
  vunit : dexpr option; (* the unit it was declared with, var F : N, for display *)
  value : (Q.t * dexpr) option; (* const g = 9.81 [m/s^2] *)
}

(* A unit stands for a dimension, possibly scaled: km is L with factor 1000.
   Base units (unit kg : Mass) are what other dimensions are shown in. *)
(* A unit's size in base units, q*pi^k: a degree is pi/180 (of a radian). *)
type scale = { q : Q.t; pi : int }

(* [angle] is the power of the radian a unit carries (rad/s: 1) and [hz] that
   of the hertz, so that a conversion from rad/s to Hz, which needs a 2π that
   dimensions cannot see, is caught. *)
type unit_info = { udim : Dim.t; factor : scale; base : bool; angle : Q.t; hz : Q.t }
type def_info = { params : string list; body : expr; scheme : Infer.scheme; shapes : Shape.table }

type law_info = {
  eq : eq;
  uses : string list; (* the axioms (non-derived laws) it rests on *)
  assumes : string list; (* assumptions the CAS was allowed to use *)
}

type 'a entry = { origin : string; v : 'a }

type theory = {
  tname : string;
  mutable dims : (string * Dim.t entry) list;
  mutable vars : (string * var_info entry) list;
  mutable defs : (string * def_info entry) list;
  mutable laws : (string * law_info entry) list;
  mutable units : (string * unit_info entry) list;
}

let new_theory n = { tname = n; dims = []; vars = []; defs = []; laws = []; units = [] }
let union a b = a @ List.filter (fun x -> not (List.mem x a)) b

(* ---- scopes ---- *)

let add_entry kind same tbl name e =
  match List.assoc_opt name tbl with
  | None -> tbl @ [ (name, e) ]
  | Some e' when same e' e -> tbl
  | Some e' -> fail "%s `%s` is already defined in %s" kind name e'.origin

let same_origin a b = a.origin = b.origin
let same_dim a b = Dim.equal a.v b.v
let never _ _ = false

let import th from =
  let merge kind same mine theirs =
    List.fold_left (fun acc (n, e) -> add_entry kind same acc n e) mine theirs
  in
  th.dims <- merge "dimension" same_dim th.dims from.dims;
  th.vars <- merge "variable" same_origin th.vars from.vars;
  th.defs <- merge "definition" same_origin th.defs from.defs;
  th.laws <- merge "law" same_origin th.laws from.laws;
  th.units <- merge "unit" same_origin th.units from.units

let find_var th x = Option.map (fun e -> e.v) (List.assoc_opt x th.vars)
let find_def th f = Option.map (fun e -> e.v) (List.assoc_opt f th.defs)

let check_var th x =
  match find_var th x with Some v -> v | None -> fail "`%s` is not a declared variable" x

let attrs_of th x = match find_var th x with Some v -> v.attrs | None -> []

(* Attributes may carry a size: "vector(2)". *)
let attr_name a = match String.index_opt a '(' with Some i -> String.sub a 0 i | None -> a

let attr_size a =
  match String.index_opt a '(' with
  | None -> None
  | Some i -> int_of_string_opt (String.sub a (i + 1) (String.length a - i - 2))

(* `vector` and `position` mean 3-vectors unless a size is given. *)
let vector_size attrs =
  List.find_map
    (fun a -> if List.mem (attr_name a) [ "vector"; "position" ] then Some (Option.value (attr_size a) ~default:3) else None)
    attrs

let is_vector_attrs a = vector_size a <> None
let is_vector th x = is_vector_attrs (attrs_of th x)
let has_vectors th = List.exists (fun (_, e) -> is_vector_attrs e.v.attrs) th.vars

(* `matrix(n)`: an n×n matrix *)
let matrix_size attrs = List.find_map (fun a -> if attr_name a = "matrix" then attr_size a else None) attrs
let is_matrix_attrs a = matrix_size a <> None

(* a vector or a matrix: not something to differentiate by, order, or count *)
let not_scalar a = is_vector_attrs a || is_matrix_attrs a
let kind_name a = if is_matrix_attrs a then "matrix" else "vector"

let shape_of_attrs a =
  match (vector_size a, matrix_size a) with
  | Some n, _ -> Shape.Vector n
  | None, Some n -> Shape.Matrix n
  | None, None -> Shape.Scalar

let vector_sizes th =
  List.sort_uniq compare (List.filter_map (fun (_, e) -> vector_size e.v.attrs) th.vars)

let is_position a = List.exists (fun a -> attr_name a = "position") a

let position th =
  List.find_map (fun (x, e) -> if is_position e.v.attrs then Some (x, e.v) else None) th.vars

let find_unit th n = Option.map (fun e -> e.v) (List.assoc_opt n th.units)

(* A dimension, written with dimensions or units: L/T, m/s and km/h are all
   L/T. A scale factor is only allowed in a unit definition. *)
let rec eval_dim th = function
  | DOne -> Dim.one
  | DNum q ->
      fail "a number like `%s` can only scale a unit, as in `unit km = 1000*m`; a dimension cannot contain one"
        (Q.to_string q)
  | DName n -> (
      match (List.assoc_opt n th.dims, find_unit th n) with
      | Some e, _ -> e.v
      | None, Some u -> u.udim
      | None, None -> fail "unknown dimension or unit `%s`" n)
  | DMul (a, b) -> Dim.add (eval_dim th a) (eval_dim th b)
  | DDiv (a, b) -> Dim.sub (eval_dim th a) (eval_dim th b)
  | DPow (a, q) -> Dim.scale q (eval_dim th a)

let shape_env th =
  {
    Shape.var_shape = (fun x -> Option.map (fun v -> shape_of_attrs v.attrs) (find_var th x));
    def_body = (fun f -> Option.map (fun d -> (d.params, d.body)) (find_def th f));
    position = Option.map (fun (x, v) -> (x, Option.value (vector_size v.attrs) ~default:3)) (position th);
    var_deps = (fun x -> match find_var th x with Some v -> v.deps | None -> []);
    locals = [];
  }

let shape th e = try Shape.infer (shape_env th) e with Infer.Error _ -> Shape.S

let env th =
  {
    Infer.global = (fun x -> Option.map (fun v -> v.vdim) (find_var th x));
    scheme_of = (fun f -> Option.map (fun d -> d.scheme) (find_def th f));
    locals = [];
    position = Option.map (fun (_, v) -> v.vdim) (position th);
    deps = (fun x -> match find_var th x with Some v -> v.deps | None -> []);
    unit_dim = (fun u -> eval_dim th u);
    matrix_size = (fun e -> match shape th e with Shape.M n -> Some n | _ -> None);
  }

(* ---- dependencies ---- *)

let deps_of th x = match find_var th x with Some v -> v.deps | None -> []

(* The names SymPy sees for what x depends on: a vector dependency r stands
   for its components r.1, r.2, r.3, as atomized in Cas. *)
let cas_deps th x =
  let base = match String.index_opt x '.' with Some i -> String.sub x 0 i | None -> x in
  List.concat_map
    (fun d ->
      match vector_size (attrs_of th d) with
      | Some n -> List.init n (fun i -> d ^ "." ^ string_of_int (i + 1))
      | None -> [ d ])
    (deps_of th base)

(* Does v depend on x, directly or through what it depends on: x(θ) with θ(t)
   depends on t? *)
let rec reaches th v x = List.exists (fun d -> d = x || reaches th d x) (deps_of th v)

(* Does [e] depend on the variable [x]? *)
let rec depends th x e =
  match e with
  | Var v -> v = x || reaches th v x
  | _ -> List.exists (depends th x) (children e)

(* An equation must agree in shape and in dimension. Shapes go first: adding
   a vector to a scalar is a more basic mistake than a wrong dimension. *)
let check_eq th q =
  let s = Shape.check_eq (shape_env th) q in
  (Infer.check_eq (env th) q, s)

(* q^k for a whole number k *)
let rec qpow q k = if k = 0 then Q.one else if k < 0 then Q.inv (qpow q (-k)) else Q.mul q (qpow q (k - 1))

let unscaled = { q = Q.one; pi = 0 }
let is_unscaled f = Q.equal f.q Q.one && f.pi = 0

(* The scale as a number: pi stays exact for SymPy. *)
let scale_expr f = if f.pi = 0 then Num f.q else Mul (Num f.q, Pow (Const "pi", Num (Q.of_int f.pi)))

(* A unit definition: its dimension and its size in base units. `pi` may
   scale a unit, as in `unit deg = pi/180*rad`. *)
let rec eval_unit th = function
  | DOne -> (Dim.one, unscaled)
  | DNum q -> (Dim.one, { q; pi = 0 })
  | DName "pi" when find_unit th "pi" = None -> (Dim.one, { q = Q.one; pi = 1 })
  | DName n -> (
      match (find_unit th n, List.assoc_opt n th.dims) with
      | Some u, _ -> (u.udim, u.factor)
      | None, Some e -> (e.v, unscaled)
      | None, None -> fail "unknown unit `%s`" n)
  | DMul (a, b) ->
      let da, fa = eval_unit th a and db, fb = eval_unit th b in
      (Dim.add da db, { q = Q.mul fa.q fb.q; pi = fa.pi + fb.pi })
  | DDiv (a, b) ->
      let da, fa = eval_unit th a and db, fb = eval_unit th b in
      (Dim.sub da db, { q = Q.div fa.q fb.q; pi = fa.pi - fb.pi })
  | DPow (a, q) ->
      let d, f = eval_unit th a in
      if is_unscaled f then (Dim.scale q d, f)
      else if Z.equal (Q.den q) Z.one then (Dim.scale q d, { q = qpow f.q (Q.to_int q); pi = f.pi * Q.to_int q })
      else fail "a scaled unit cannot be raised to the fractional power %s" (Q.to_string q)

(* The powers of the radian and of the hertz in a unit expression. *)
let rec angle_hz th = function
  | DOne | DNum _ -> (Q.zero, Q.zero)
  | DName n -> ( match find_unit th n with Some u -> (u.angle, u.hz) | None -> (Q.zero, Q.zero))
  | DMul (a, b) ->
      let (a1, h1), (a2, h2) = (angle_hz th a, angle_hz th b) in
      (Q.add a1 a2, Q.add h1 h2)
  | DDiv (a, b) ->
      let (a1, h1), (a2, h2) = (angle_hz th a, angle_hz th b) in
      (Q.sub a1 a2, Q.sub h1 h2)
  | DPow (a, q) ->
      let a1, h1 = angle_hz th a in
      (Q.mul q a1, Q.mul q h1)

let rec mentions_unit th = function
  | DName n -> find_unit th n <> None
  | DMul (a, b) | DDiv (a, b) -> mentions_unit th a || mentions_unit th b
  | DPow (a, _) -> mentions_unit th a
  | DOne | DNum _ -> false

(* The units to show a dimension in: the base units, or one named unit times
   base units when that is shorter, as F/m for ε0 or V/m for an electric
   field. On a tie the base units win, so 1/s stays 1/s rather than Hz. None
   when a base dimension has no base unit, or the dimension has variables. *)
let auto_units th (d : Dim.t) =
  let base_unit b =
    List.find_map (fun (n, e) -> if e.v.base && Dim.equal e.v.udim (Dim.base b) then Some n else None) th.units
  in
  let in_base (d : Dim.t) =
    Dim.K.fold
      (fun k q acc ->
        match (acc, k) with
        | None, _ | _, Dim.Var _ -> None
        | Some u, Dim.Base b -> Option.map (fun n -> Dim.add u (Dim.scale q (Dim.base n))) (base_unit b))
      d (Some Dim.one)
  in
  let size (u : Dim.t) = (Dim.K.cardinal u, Dim.K.fold (fun _ q acc -> Q.add acc (Q.abs q)) u Q.zero) in
  match in_base d with
  | None -> None
  | Some plain ->
      let named =
        List.filter_map
          (fun (n, e) ->
            if e.v.base || not (is_unscaled e.v.factor) then None
            else Option.map (fun rest -> Dim.add (Dim.base n) rest) (in_base (Dim.sub d e.v.udim)))
          th.units
      in
      let better a b = compare (size a) (size b) < 0 in
      Some (List.fold_left (fun best u -> if better u best then u else best) plain named)

(* ---- rewriting ---- *)

(* Replace variables. [deps] says what a variable depends on, so that when x
   is replaced, x(0) becomes at(replacement, t, 0). *)
let rec subst_expr ?(deps = fun _ -> []) m e =
  let go = subst_expr ~deps m in
  (* renaming a bound variable is fine; replacing it by an expression is not *)
  let bound x what =
    match List.assoc_opt x m with
    | Some (Var _) | None -> ()
    | Some _ -> fail "cannot replace `%s` in `%s`: it is the variable %s" x (Pretty.expr e) what
  in
  match e with
  | Var x when List.mem_assoc x m -> List.assoc x m
  | Var x when List.exists (fun d -> List.mem_assoc d m) (deps x) ->
      (* x(θ) with θ replaced by ω*t is x(ω*t) *)
      Call (x, List.map (fun d -> go (Var d)) (deps x))
  | Var _ -> e
  | Call ("diff", [ _; (Var x | Call ("comp", [ Var x; _ ])) ]) ->
      bound x "being differentiated";
      map_children go e
  | Call ("integral", _ :: (Var x | Call ("comp", [ Var x; _ ])) :: _) ->
      bound x "of integration";
      map_children go e
  | Call ("sum", [ f; (Var k as i); a; b ]) ->
      (* the index is the sum's own: a variable of the same name outside is another *)
      Call ("sum", [ subst_expr ~deps (List.remove_assoc k m) f; i; go a; go b ])
  | Call ("at", [ _; (Var x | Call ("comp", [ Var x; _ ])); _ ]) ->
      bound x "being set";
      map_children go e
  | Call (("line" | "loop" | "surface" | "volume"), _ :: _ :: rest) ->
      List.iteri (fun i a -> match a with Var x when i mod 3 = 0 -> bound x "of integration" | _ -> ()) rest;
      map_children go e
  | Call (f, args) when List.mem_assoc f m && deps f <> [] ->
      List.fold_left2 (fun acc d a -> Call ("at", [ acc; Var d; go a ])) (List.assoc f m) (deps f) args
  | _ -> map_children go e

(* Expand calls to the definitions selected by [only]. *)
let rec unfold th only e =
  match map_children (unfold th only) e with
  | Call (f, args) as e' -> (
      match find_def th f with
      | Some d when only f -> unfold th only (subst_expr (List.combine d.params args) d.body)
      | _ -> e')
  | e' -> e'

(* Does [e] mention any of [names], also through the bodies of definitions? *)
let rec mentions th names e =
  match e with
  | Var x -> List.mem x names
  | Call (f, args) -> List.mem f names || List.exists (mentions th names) args || def_mentions th names f
  | _ -> List.exists (mentions th names) (children e)

and def_mentions th names f =
  match find_def th f with
  | None -> false
  | Some d -> mentions th (List.filter (fun n -> not (List.mem n d.params)) names) d.body

(* Trivial clean-ups after substitution; no CAS involved. *)
(* Is s a plain number-valued factor, safe to move into a vec or mat? Not if
   it involves a vector or a matrix: A*vec(1, 2) is not vec(A*1, A*2). Uses
   the printer's hooks, which the checker sets for the current theory. *)
let rec plain s =
  match s with
  | Var v -> !Pretty.vector_size v = None && not (!Pretty.is_matrix v)
  | Call (("vec" | "mat" | "identity" | "inv" | "transpose" | "cross" | "grad" | "curl"), _) -> false
  | _ -> List.for_all plain (children s)

let rec tidy e =
  let zero q = Q.equal q Q.zero and one q = Q.equal q Q.one in
  match map_children tidy e with
  | Add (Num z, a) when zero z -> a
  | Add (a, Num z) when zero z -> a
  | Sub (a, Num z) when zero z -> a
  | Sub (Num z, a) when zero z -> Neg a
  | Mul (Num z, _) when zero z -> Num Q.zero
  | Mul (_, Num z) when zero z -> Num Q.zero
  | Div (Num z, _) when zero z -> Num Q.zero
  | Mul (Num o, a) when one o -> a
  | Mul (Num m, a) when Q.equal m Q.minus_one -> Neg a
  | Mul (a, Num m) when Q.equal m Q.minus_one -> Neg a
  (* a sign comes out of a product, and products group left to right *)
  | Mul (a, Neg b) | Mul (Neg a, b) -> tidy (Neg (Mul (a, b)))
  | Mul (a, Mul (b, c)) -> tidy (Mul (Mul (a, b), c))
  | Mul (a, Num o) when one o -> a
  | Div (a, Num o) when one o -> a
  | Pow (a, Num o) when one o -> a
  | Neg (Num q) -> Num (Q.neg q)
  | Neg (Neg a) -> a
  | Quantity (z, _) when zero z -> Num Q.zero (* 0 [m/s] is 0, which has every dimension *)
  (* every vector operator maps 0 to 0 *)
  | Call (("dot" | "cross"), [ Num z; _ ]) when zero z -> Num Q.zero
  | Call (("dot" | "cross"), [ _; Num z ]) when zero z -> Num Q.zero
  | Call (("grad" | "div" | "curl" | "lap" | "norm" | "diff" | "comp"), Num z :: _) when zero z -> Num Q.zero
  | Call ("comp", [ Call ("vec", xs); Num k ]) when Q.to_int k <= List.length xs -> List.nth xs (Q.to_int k - 1)
  | Call ("vec", xs) when List.for_all (function Num z -> zero z | _ -> false) xs -> Num Q.zero
  | Call ("diff", [ Call ("vec", xs); x ]) -> tidy (Call ("vec", List.map (fun c -> Call ("diff", [ c; x ])) xs))
  (* arithmetic on explicit vectors happens component by component *)
  | Add (Call ("vec", xs), Call ("vec", ys)) when List.length xs = List.length ys -> tidy (Call ("vec", List.map2 (fun x y -> Add (x, y)) xs ys))
  | Sub (Call ("vec", xs), Call ("vec", ys)) when List.length xs = List.length ys -> tidy (Call ("vec", List.map2 (fun x y -> Sub (x, y)) xs ys))
  | Neg (Call ("vec", xs)) -> tidy (Call ("vec", List.map (fun x -> Neg x) xs))
  | Mul (Call ("vec", xs), s) when plain s -> tidy (Call ("vec", List.map (fun x -> Mul (x, s)) xs))
  | Mul (s, Call ("vec", xs)) when plain s -> tidy (Call ("vec", List.map (fun x -> Mul (s, x)) xs))
  | Div (Call ("vec", xs), s) -> tidy (Call ("vec", List.map (fun x -> Div (x, s)) xs))
  (* and on explicit matrices row by row, which the vector rules then finish *)
  | Add (Call ("mat", xs), Call ("mat", ys)) when List.length xs = List.length ys -> tidy (Call ("mat", List.map2 (fun x y -> Add (x, y)) xs ys))
  | Sub (Call ("mat", xs), Call ("mat", ys)) when List.length xs = List.length ys -> tidy (Call ("mat", List.map2 (fun x y -> Sub (x, y)) xs ys))
  | Neg (Call ("mat", xs)) -> tidy (Call ("mat", List.map (fun x -> Neg x) xs))
  | Mul (Call ("mat", xs), s) when plain s -> tidy (Call ("mat", List.map (fun x -> Mul (x, s)) xs))
  | Mul (s, Call ("mat", xs)) when plain s -> tidy (Call ("mat", List.map (fun x -> Mul (s, x)) xs))
  | Div (Call ("mat", xs), s) -> tidy (Call ("mat", List.map (fun x -> Div (x, s)) xs))
  | Call ("entry", [ Call ("mat", rows); Num i; Num j ]) -> (
      match List.nth_opt rows (Q.to_int i - 1) with
      | Some (Call ("vec", xs)) -> List.nth xs (Q.to_int j - 1)
      | _ -> Call ("entry", [ Call ("mat", rows); Num i; Num j ]))
  | Call ("mat", rows) when List.for_all (function Num z -> zero z | _ -> false) rows -> Num Q.zero
  | e' -> e'

(* Write products the physicist's way, scalars first: q*E rather than E*q. *)
let vectors_last th e =
  let isv f = match shape th f with Shape.V _ -> true | _ -> false in
  let rec flat = function Mul (a, b) -> flat a @ flat b | f -> [ f ] in
  let rec go e =
    match map_children go e with
    | Mul _ as m -> (
        let scalars, vectors = List.partition (fun f -> not (isv f)) (flat m) in
        match scalars @ vectors with x :: xs -> List.fold_left (fun a b -> Mul (a, b)) x xs | [] -> m)
    | e' -> e'
  in
  go e

(* ---- components ---- *)

let num k = Num (Q.of_int k)
let comp e k = Call ("comp", [ e; num k ])
let sum = function [] -> Num Q.zero | x :: xs -> List.fold_left (fun a b -> Add (a, b)) x xs

(* For cross and curl: component k is built from the other two, cyclically. *)
let cyclic k = match k with 1 -> (2, 3) | 2 -> (3, 1) | _ -> (1, 2)

let position_var th = match position th with Some (x, _) -> Var x | None -> fail "no position vector is declared"

let msize th e = match shape th e with Shape.M n -> n | _ -> 0
let is_matrix th e = msize th e > 0

(* Entry (i, j) of a matrix expression, pushed inside as far as it goes:
   (A*B)_ij = Σ_k A_ik B_kj, transpose(A)_ij = A_ji, identity(n)_ij = δ_ij.
   An inverse is worked out by SymPy from the entries. *)
let rec entry th i j e =
  let en = entry th in
  match e with
  | Num _ -> e
  | Var _ -> Call ("entry", [ e; num i; num j ])
  | Neg a -> Neg (en i j a)
  | Add (a, b) -> Add (en i j a, en i j b)
  | Sub (a, b) -> Sub (en i j a, en i j b)
  | Mul (a, b) when is_matrix th a && is_matrix th b ->
      sum (List.init (msize th a) (fun k -> Mul (en i (k + 1) a, en (k + 1) j b)))
  | Mul (a, b) when is_matrix th a -> Mul (en i j a, b)
  | Mul (a, b) -> Mul (a, en i j b)
  | Div (a, b) -> Div (en i j a, b)
  | Call ("mat", rows) -> ( match List.nth rows (i - 1) with Call ("vec", xs) -> List.nth xs (j - 1) | r -> comp r j)
  | Call ("identity", _) -> num (if i = j then 1 else 0)
  | Call ("transpose", [ a ]) -> en j i a
  | Call ("inv", [ a ]) -> List.nth (List.nth (Cas.inv ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) (entries th a)) (i - 1)) (j - 1)
  | Call ("diff", [ f; x ]) -> Call ("diff", [ en i j f; x ])
  | _ -> Call ("entry", [ e; num i; num j ])

and entries th a =
  let n = msize th a in
  List.init n (fun i -> List.init n (fun j -> entry th (i + 1) (j + 1) a))

(* The matrix with these entries, written out: mat(vec(..), vec(..)) *)
let mat_of rows = Call ("mat", List.map (fun r -> Call ("vec", r)) rows)

(* Component k of a vector expression, pushed inside as far as it goes:
   (a + b).x = a.x + b.x, (s*v).x = s*v.x, vec(a, b, c).y = b, ... *)
let rec component th k e =
  let c = component th in
  match e with
  | Num _ -> e
  | Var _ -> comp e k
  | Neg a -> Neg (c k a)
  | Add (a, b) -> Add (c k a, c k b)
  | Sub (a, b) -> Sub (c k a, c k b)
  | Mul (a, b) when is_matrix th a ->
      (* (A v)_k = Σ_j A_kj v_j *)
      sum (List.init (msize th a) (fun j -> Mul (entry th k (j + 1) a, c (j + 1) b)))
  | Mul (a, b) -> ( match shape th a with Shape.V _ -> Mul (c k a, b) | _ -> Mul (a, c k b))
  | Div (a, b) -> Div (c k a, b)
  | Call ("vec", xs) -> List.nth xs (k - 1)
  | Call ("cross", [ a; b ]) ->
      let i, j = cyclic k in
      Sub (Mul (c i a, c j b), Mul (c j a, c i b))
  | Call ("grad", [ f ]) -> Call ("diff", [ f; comp (position_var th) k ])
  | Call ("curl", [ f ]) ->
      let i, j = cyclic k and r = position_var th in
      Sub (Call ("diff", [ c j f; comp r i ]), Call ("diff", [ c i f; comp r j ]))
  | Call ("lap", [ f ]) -> Call ("lap", [ c k f ])
  | Call ("diff", [ f; x ]) -> Call ("diff", [ c k f; x ])
  | _ -> comp e k

let size th e = match shape th e with Shape.V n -> n | _ -> 0

(* Write dot, norm, cross, div and curl in components. With [only_concrete],
   only where no vector variable is involved, as in norm(vec(3, 4)). *)
let rec expand ?(only_concrete = false) th e =
  (* a vector variable used whole is opaque; its components r.x are not *)
  let rec whole e =
    match e with
    | Call ("comp", [ Var _; _ ]) -> false
    | Var v -> is_vector th v
    | _ -> List.exists whole (children e)
  in
  let ok args = (not only_concrete) || not (List.exists whole args) in
  let comps n f = List.init n (fun i -> f (i + 1)) in
  match map_children (expand ~only_concrete th) e with
  (* Matrices are always written out: SymPy's symbols commute, so it would
     take A*B for B*A. *)
  | Call ("det", [ a ]) when is_matrix th a -> Cas.det ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) (entries th a)
  | Call ("trace", [ a ]) when is_matrix th a -> sum (List.init (msize th a) (fun i -> entry th (i + 1) (i + 1) a))
  | Call ("entry", [ a; Num i; Num j ]) when (match a with Var _ -> false | _ -> true) -> entry th (Q.to_int i) (Q.to_int j) a
  | Mul (a, b) when is_matrix th a && size th b > 0 -> Call ("vec", comps (size th b) (fun k -> component th k e))
  | (Mul (a, b)) when is_matrix th a && is_matrix th b -> mat_of (entries th e)
  | Call (("inv" | "transpose" | "identity"), _) when is_matrix th e -> mat_of (entries th e)
  | Call ("dot", [ a; b ]) when ok [ a; b ] && size th a > 0 ->
      sum (comps (size th a) (fun k -> Mul (component th k a, component th k b)))
  | Call ("norm", [ a ]) when ok [ a ] && size th a > 0 ->
      Call ("sqrt", [ sum (comps (size th a) (fun k -> Pow (component th k a, num 2))) ])
  | Call ("cross", [ a; b ]) as x when ok [ a; b ] -> Call ("vec", comps 3 (fun k -> component th k x))
  | Call ("div", [ f ]) when ok [ f ] && size th f > 0 ->
      let r = position_var th in
      sum (comps (size th f) (fun k -> Call ("diff", [ component th k f; comp r k ])))
  | Call ("curl", [ _ ]) as x when ok [ x ] -> Call ("vec", comps 3 (fun k -> component th k x))
  | Call ("grad", [ f ]) when ok [ f ] ->
      let r = position_var th in
      Call ("vec", comps (size th r) (fun k -> Call ("diff", [ f; comp r k ])))
  | Call ("lap", [ f ]) when ok [ f ] ->
      let r = position_var th in
      let lap_of g = sum (comps (size th r) (fun k -> Call ("diff", [ Call ("diff", [ g; comp r k ]); comp r k ]))) in
      if size th f > 0 then Call ("vec", comps (size th f) (fun k -> lap_of (component th k f))) else lap_of f
  | e' -> e'

(* SymPy sees a vector as one opaque symbol, so it cannot differentiate
   through one: for SymPy, diff(dot(k, r), r.x) would be 0 because the r
   inside dot is not the symbol r.x. So whenever a derivative's argument
   mentions the position or a vector operation that depends on the variable,
   write it in components first; diff(E, t) on its own stays as it is. *)
let vector_ops = [ "dot"; "cross"; "norm"; "grad"; "div"; "curl"; "lap" ]

let rec in_components th e =
  match map_children (in_components th) e with
  | Call ("diff", [ f; x ]) as d ->
      let xv = match x with Var v | Call ("comp", [ Var v; _ ]) -> v | _ -> "" in
      let rec needs e =
        match e with
        | Var v -> Option.fold ~none:false ~some:(fun (p, _) -> p = v) (position th)
        | Call (op, args) when List.mem op vector_ops && List.exists (depends th xv) args -> true
        | _ -> List.exists needs (children e)
      in
      if not (needs f) then d
      else (
        match shape th f with
        | Shape.V n -> Call ("vec", List.init n (fun i -> Call ("diff", [ expand th (component th (i + 1) f); x ])))
        | _ -> Call ("diff", [ expand th f; x ]))
  | e' -> e'

(* e with the position r set to the point q: r -> q, r.x -> q.x, and a field
   F(r) -> F(q). *)
let at_point th q e =
  let r = match position th with Some (r, _) -> r | None -> fail "no position vector is declared" in
  let rec go e =
    match e with
    | Var v when v = r -> q
    | Var v when List.mem r (deps_of th v) -> Call (v, List.map (fun d -> if d = r then q else Var d) (deps_of th v))
    | _ -> map_children go e
  in
  go e

(* The integrand f evaluated on the region q. Derivatives by position must
   be taken before the point is put in, or they would all be 0: then f is
   written in components and evaluated with at(..., r.x, q.x) for each
   component, which SymPy does after differentiating. *)
let on_region th q f =
  let r = match position th with Some (r, _) -> r | None -> fail "no position vector is declared" in
  let rec has_derivative e =
    match e with
    | Call (("grad" | "div" | "curl" | "lap"), _) | Call ("diff", [ _; Call ("comp", [ Var _; _ ]) ]) -> true
    | _ -> List.exists has_derivative (children e)
  in
  if not (has_derivative f) then at_point th q f
  else
    let n = size th (Var r) in
    let chain e = List.fold_left (fun acc k -> Call ("at", [ acc; comp (Var r) k; comp q k ])) e (List.init n (fun i -> i + 1)) in
    let f' = expand th f in
    match shape th f with
    | Shape.V m -> Call ("vec", List.init m (fun i -> chain (component th (i + 1) f')))
    | _ -> chain f'

(* line, loop, surface and volume as plain nested integrals over their
   parameters, with the tangent, normal or Jacobian written out:
     line(F, p, s, a, b)   = ∫ F(p)·dp/ds ds,   or ∫ f(p) |dp/ds| ds
     surface(F, q, u, .., w, ..) = ∫∫ F(q)·(dq/du × dq/dw) du dw, or with |...|
     volume(f, q, u, .., v, .., w, ..) = ∫∫∫ f(q) dq/du·(dq/dv × dq/dw) du dv dw
   The volume uses the signed Jacobian, so order the parameters to keep it
   positive (r, θ, φ in spherical coordinates). *)
let rec integrals th e =
  let e = map_children (integrals th) e in
  let is_vector f = match shape th f with Shape.V _ -> true | _ -> false in
  let d q u = Call ("diff", [ q; u ]) in
  let nest body params =
    List.fold_left (fun acc (u, a, b) -> Call ("integral", [ acc; u; a; b ])) body params
  in
  let rec triples = function a :: b :: c :: rest -> (a, b, c) :: triples rest | _ -> [] in
  match e with
  | Call (("line" | "loop"), [ f; p; s; a; b ]) ->
      let fp = on_region th p f and dp = d p s in
      nest (if is_vector f then Call ("dot", [ fp; dp ]) else Mul (fp, Call ("norm", [ dp ]))) [ (s, a, b) ]
  | Call ("surface", f :: q :: rest) when List.length rest = 6 ->
      let ps = triples rest in
      let (u, _, _), (w, _, _) = (List.nth ps 0, List.nth ps 1) in
      let fq = on_region th q f and n = Call ("cross", [ d q u; d q w ]) in
      nest (if is_vector f then Call ("dot", [ fq; n ]) else Mul (fq, Call ("norm", [ n ]))) ps
  | Call ("volume", f :: q :: rest) when List.length rest = 9 ->
      let ps = triples rest in
      let (u, _, _), (v, _, _), (w, _, _) = (List.nth ps 0, List.nth ps 1, List.nth ps 2) in
      let jacobian = Call ("dot", [ d q u; Call ("cross", [ d q v; d q w ]) ]) in
      nest (Mul (on_region th q f, jacobian)) ps
  | e' -> e'

(* Everything a CAS step does to an expression before SymPy sees it. *)
let prepare th e =
  tidy (in_components th (expand ~only_concrete:true th (tidy (integrals th (unfold th (fun _ -> true) e)))))

let assumptions th q =
  List.concat_map
    (fun x ->
      let a = attrs_of th x in
      match (List.mem "integer" a, List.mem "positive" a, List.mem "nonzero" a) with
      | true, true, _ -> [ x ^ " a positive integer" ]
      | true, false, true -> [ x ^ " an integer ≠ 0" ]
      | true, false, false -> [ x ^ " an integer" ]
      | false, true, _ -> [ x ^ " > 0" ]
      | false, false, true -> [ x ^ " ≠ 0" ]
      | false, false, false -> [])
    (vars (vars [] q.lhs) q.rhs)

(* Rules for curl, div, grad and lap, so that their results line up with laws
   to substitute: they are linear, pass through constants, commute with
   derivatives by anything but position, and div(curl F) = curl(grad f) = 0. *)
let spatial = [ "grad"; "div"; "curl"; "lap" ]

let rec normalize th e =
  let constant s = match position th with Some (p, _) -> not (depends th p s) | None -> true in
  let scalar s = match shape th s with Shape.V _ -> false | _ -> true in
  let n = normalize th in
  match map_children n e with
  | Call (op, [ Add (a, b) ]) when List.mem op spatial -> Add (n (Call (op, [ a ])), n (Call (op, [ b ])))
  | Call (op, [ Sub (a, b) ]) when List.mem op spatial -> Sub (n (Call (op, [ a ])), n (Call (op, [ b ])))
  | Call (op, [ Neg a ]) when List.mem op spatial -> Neg (n (Call (op, [ a ])))
  | Call (op, [ Mul (s, a) ]) when List.mem op spatial && constant s && scalar s -> Mul (s, n (Call (op, [ a ])))
  | Call (op, [ Mul (a, s) ]) when List.mem op spatial && constant s && scalar s -> Mul (n (Call (op, [ a ])), s)
  | Call (op, [ Div (a, s) ]) when List.mem op spatial && constant s -> Div (n (Call (op, [ a ])), s)
  | Call (op, [ Call ("diff", [ f; (Var t as x) ]) ])
    when List.mem op spatial && (match position th with Some (p, _) -> p <> t | None -> true) ->
      Call ("diff", [ n (Call (op, [ f ])); x ])
  | Call ("div", [ Call ("curl", _) ]) | Call ("curl", [ Call ("grad", _) ]) -> Num Q.zero
  (* at(e, r, p) is plain substitution when nothing in e depends on r through
     a declaration (as E(r) would); it also turns r.x into p.x *)
  | Call ("at", [ e; Var x; a ]) when not (List.exists (fun v -> v <> x && List.mem x (deps_of th v)) (vars [] e)) ->
      n (subst_expr [ (x, a) ] e)
  | e' -> tidy e'

(* ---- numbers ---- *)

(* The variables an expression still needs values for. The variable of an
   integral, of at(...) and the parameters of line, surface and volume are
   bound, so they do not count; x(0) needs a value of x. *)
let free_vars th e =
  let name = function Var x | Call ("comp", [ Var x; _ ]) -> [ x ] | _ -> [] in
  let rec go bound e =
    match e with
    | Var x -> if List.mem x bound then [] else [ x ]
    | Call ("integral", f :: x :: rest) -> go (name x @ bound) f @ List.concat_map (go bound) rest
    | Call ("sum", [ f; Var k; a; b ]) -> go (k :: bound) f @ go bound a @ go bound b
    | Call ("at", [ e; x; a ]) -> go (name x @ bound) e @ go bound a
    | Call (("line" | "loop" | "surface" | "volume"), f :: q :: rest) ->
        let params = List.concat (List.filteri (fun i _ -> i mod 3 = 0) (List.map name rest)) in
        go (params @ bound) f @ go (params @ bound) q @ List.concat_map (go (params @ bound)) rest
    | Call (f, args) when deps_of th f <> [] -> [ f ] @ List.concat_map (go bound) args
    | _ -> List.concat_map (go bound) (children e)
  in
  List.sort_uniq compare (go [] e)

(* Quantities and constants as plain numbers in base units: 3 [km] is 3000. *)
let rec in_base_units th e =
  match e with
  | Quantity (q, u) ->
      let f = snd (eval_unit th u) in
      scale_expr { f with q = Q.mul q f.q }
  | Var x -> (
      match find_var th x with Some { value = Some (q, u); _ } -> in_base_units th (Quantity (q, u)) | _ -> e)
  | _ -> map_children (in_base_units th) e

(* Units, as a unit expression, from a vector of unit names: {N: 1, m: 1} is N*m. *)
let dexpr_of_units (u : Dim.t) =
  match Dim.sorted u with
  | [] -> DOne
  | items ->
      let term (k, q) =
        let n = match k with Dim.Base b -> DName b | Dim.Var _ -> DOne in
        if Q.equal q Q.one then n else DPow (n, q)
      in
      let pos = List.filter (fun (_, q) -> Q.sign q > 0) items
      and neg = List.filter_map (fun (k, q) -> if Q.sign q < 0 then Some (k, Q.neg q) else None) items in
      let prod = function [] -> DOne | x :: xs -> List.fold_left (fun a b -> DMul (a, term b)) (term x) xs in
      if neg = [] then prod pos else DDiv (prod pos, prod neg)

(* ---- derivations ---- *)

(* dsolve leaves constants C1, C2, ... Their dimensions follow from the
   solution, x = C1 + C2*t: each constant gets a fresh dimension variable and
   inference solves for them. They become variables of the theory, renamed
   if the name is taken. *)
let integration_constants th x sol =
  let unknown = List.filter (fun v -> find_var th v = None) (vars [] sol) in
  if unknown = [] then (sol, [])
  else
    let st = Infer.create () in
    let locals = List.map (fun c -> (c, Infer.fresh st)) unknown in
    let env' = { (env th) with Infer.locals } in
    Infer.unify st (Infer.infer st env' (Var x)) (Infer.infer st env' sol) (fun a b ->
        sprintf "the solution has dimension [%s], not [%s]" (Dim.to_string b) (Dim.to_string a));
    let taken = ref (List.map fst th.vars) in
    let fresh c =
      let rec go k = let n = "C" ^ string_of_int k in if List.mem n !taken then go (k + 1) else n in
      let n = if List.mem c !taken then go 1 else c in
      taken := n :: !taken;
      n
    in
    let consts =
      List.map
        (fun (c, d) ->
          let d = Infer.apply st d in
          if Dim.vars d <> [] then fail "cannot work out the dimension of the integration constant `%s`" c;
          (c, fresh c, d))
        locals
    in
    List.iter
      (fun (_, n, d) ->
        th.vars <- th.vars @ [ (n, { origin = th.tname; v = { vdim = d; attrs = [ "real" ]; deps = []; vunit = None; value = None } }) ])
      consts;
    (subst_expr (List.map (fun (c, n, _) -> (c, Var n)) consts) sol, List.map (fun (_, n, d) -> (n, d)) consts)

type value = {
  veq : eq;
  vuses : string list;
  vassumes : string list;
  vconsts : (string * Dim.t) list; (* integration constants introduced by solving an ODE *)
}

let find_law th locals (q, n) =
  let of_entry e = { veq = e.v.eq; vuses = e.v.uses; vassumes = e.v.assumes; vconsts = [] } in
  match q with
  | None -> (
      match List.assoc_opt n locals with
      | Some v -> v
      | None -> (
          match List.assoc_opt n th.laws with Some e -> of_entry e | None -> fail "unknown law `%s`" n))
  | Some t -> (
      match List.assoc_opt n th.laws with
      | Some e when e.origin = t -> of_entry e
      | _ -> fail "unknown law `%s.%s`" t n)

(* A derivative of something that does not depend on the variable is always
   0, which is almost certainly a missing declaration rather than intended. *)
let rec check_derivatives th e =
  List.iter (check_derivatives th) (children e);
  let undeclared what f x =
    fail "`%s` is always 0, because `%s` does not depend on `%s`; declare the dependence, e.g. `var %s(%s) : ...`"
      (Pretty.expr what) (Pretty.expr f) x
      (match vars [] f with v :: _ -> v | [] -> "f")
      (String.concat ", " (x :: List.filter (( <> ) x) (match vars [] f with v :: _ -> deps_of th v | [] -> [])))
  in
  match e with
  | Call ("diff", [ f; (Var x | Call ("comp", [ Var x; _ ])) ]) when not (depends th x f) -> undeclared e f x
  | Call (("grad" | "div" | "curl" | "lap"), [ f ]) -> (
      match position th with Some (r, _) when not (depends th r f) -> undeclared e f r | _ -> ())
  | _ -> ()

let plural n word = sprintf "%d %s%s" n word (if n = 1 then "" else "s")

(* ---- numeric results, for `evaluate` and `compute` ---- *)

(* ---- eigenvalues ---- *)

(* eigen name: A, or eigen name: K, M for K v = λ M v *)
type eigened = {
  eigname : string;
  ea : expr;
  eb : expr option;
  ldim : Dim.t; (* the eigenvalues': [A], or [K]/[M] *)
  pairs : (expr * int * expr list list) list; (* λ, its multiplicity, its eigenvectors *)
}

(* ---- dimensionless groups ---- *)

(* groups name: T from L, g, m -- the dimensionless groups (Buckingham π)
   of the variables, and the target solved in terms of them. *)
type grouped = {
  gname : string;
  target : string option;
  gvars : string list;
  groups : expr list; (* each a product of powers, dimensionless *)
  solved : eq option; (* T = sqrt(L/g)*Φ(θ0), or C*sqrt(L/g) when nothing is left *)
  absent : (string * Dim.t) list; (* variables no group can contain *)
}

(* x^2*y/z for [(x, 2); (y, 1); (z, -1)] *)
let monomial pairs =
  let pow (x, q) = if Q.equal q Q.one then Var x else Pow (Var x, Num q) in
  let product = function [] -> Num Q.one | f :: fs -> List.fold_left (fun a b -> Mul (a, b)) (pow f) (List.map pow fs) in
  let up = List.filter (fun (_, q) -> Q.sign q > 0) pairs in
  let down = List.filter_map (fun (x, q) -> if Q.sign q < 0 then Some (x, Q.neg q) else None) pairs in
  if down = [] then product up else Div (product up, product down)

(* The smallest whole-number multiple: (1, -1/2, 1/2) -> (2, -1, 1) *)
let whole v =
  let l = List.fold_left (fun l q -> Z.lcm l (Q.den q)) Z.one v in
  let v = List.map (fun q -> Q.mul q (Q.of_bigint l)) v in
  let g = List.fold_left (fun g q -> Z.gcd g (Q.num q)) Z.zero v in
  if Z.equal g Z.zero then v else List.map (fun q -> Q.div q (Q.of_bigint g)) v

let groups th name target xs =
  let all = xs @ Option.to_list target in
  List.iter
    (fun x -> if List.length (List.filter (( = ) x) all) > 1 then fail "`%s` is listed twice" x)
    all;
  let dims =
    List.map
      (fun x ->
        match find_var th x with
        | Some v when Dim.vars v.vdim = [] -> (x, v.vdim)
        | Some _ -> fail "the dimension of `%s` is not known" x
        | None -> fail "unknown variable `%s`" x)
      all
  in
  (* rows: base dimensions; columns: the variables, the target last, so that
     the earlier variables are the ones used to cancel the others' dimensions *)
  let bases =
    List.sort_uniq compare (List.concat_map (fun (_, d) -> List.map fst (Dim.K.bindings d)) dims)
  in
  let matrix = List.map (fun b -> List.map (fun (_, d) -> Dim.coeff b d) dims) bases in
  (* Written with more factors up than down (Re = ρvD/μ, not its inverse);
     the target's group keeps the target up. *)
  let tidy v =
    let count p = List.length (List.filter p v) in
    let has_target = target <> None && not (Q.equal (List.nth v (List.length all - 1)) Q.zero) in
    if (not has_target) && count (fun q -> Q.sign q < 0) > count (fun q -> Q.sign q > 0) then List.map Q.neg v else v
  in
  let basis = List.map (fun v -> tidy (whole v)) (Cas.nullspace matrix (List.length all)) in
  let pairs v = List.filter (fun (_, q) -> not (Q.equal q Q.zero)) (List.combine all v) in
  (* check what SymPy gave: every group is dimensionless *)
  List.iter
    (fun v ->
      let d = List.fold_left (fun acc ((_, d), q) -> Dim.add acc (Dim.scale q d)) Dim.one (List.combine dims v) in
      if not (Dim.is_one d) then fail "internal error: a group is not dimensionless")
    basis;
  let absent = List.filteri (fun i _ -> List.for_all (fun v -> Q.equal (List.nth v i) Q.zero) basis) dims in
  let solved =
    match target with
    | None -> None
    | Some t ->
        let i = List.length all - 1 in
        if List.mem_assoc t absent then
          fail "no product of %s has the dimension of `%s` [%s], so it cannot be found from them"
            (String.concat ", " (List.map (fun x -> "`" ^ x ^ "`") xs))
            t (Dim.to_string (List.assoc t dims));
        let own, others = List.partition (fun v -> not (Q.equal (List.nth v i) Q.zero)) basis in
        let v = List.hd own in
        (* t^a * prod x^b = 1, so t = prod x^(-b/a) *)
        let a = List.nth v i in
        let es = List.filter (fun (x, _) -> x <> t) (pairs (List.map (fun q -> Q.neg (Q.div q a)) v)) in
        let k = List.fold_left (fun l (_, q) -> Z.lcm l (Q.den q)) Z.one es in
        let scaled = monomial (List.map (fun (x, q) -> (x, Q.mul q (Q.of_bigint k))) es) in
        let prefactor =
          if Z.equal k Z.one then scaled
          else if Z.equal k (Z.of_int 2) then Call ("sqrt", [ scaled ])
          else Pow (scaled, Num (Q.inv (Q.of_bigint k)))
        in
        let rhs =
          match others with
          | [] -> Mul (Var "C", prefactor)
          | _ -> Mul (prefactor, Call ("Φ", List.map (fun v -> monomial (pairs v)) others))
        in
        Some { lhs = Var t; rhs }
  in
  { gname = name; target; gvars = xs; groups = List.map (fun v -> monomial (pairs v)) basis; solved; absent }

(* A matrix variable stands for the law that defines it, K = mat(...), so
   that `eigen modes: K, M` needs no copy of the matrices. *)
let defined_matrices th e =
  let rec go e =
    match e with
    | Var x when is_matrix_attrs (attrs_of th x) -> (
        match List.find_opt (fun (_, l) -> l.v.eq.lhs = Var x) th.laws with
        | Some (_, l) -> go l.v.eq.rhs
        | None -> e)
    | _ -> map_children go e
  in
  go e

let eigen th name a b =
  let size e =
    match Shape.infer (shape_env th) e with
    | Shape.M n -> n
    | s -> fail "`eigen` needs a square matrix, but `%s` is a %s" (Pretty.expr e) (Shape.s_name s)
  in
  let n = size a in
  Option.iter (fun b -> if size b <> n then fail "`%s` and `%s` must be the same size" (Pretty.expr a) (Pretty.expr b)) b;
  let dim e = Infer.check_eq (env th) { lhs = e; rhs = e } in
  let ldim = match b with Some b -> Dim.sub (dim a) (dim b) | None -> dim a in
  let rows e = entries th (tidy (prepare th (defined_matrices th e))) in
  let pairs = Cas.eigen ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) (rows a) (Option.map rows b) in
  { eigname = name; ea = a; eb = b; ldim; pairs = List.map (fun (l, m, vs) -> (tidy l, m, List.map (List.map tidy) vs)) pairs }

let check_digits digits =
  let d = Option.value digits ~default:6 in
  if d < 1 || d > 30 then fail "digits must be between 1 and 30";
  d

let has_value th x = match find_var th x with Some { value = Some _; _ } -> true | _ -> false
let missing_values th e = List.filter (fun x -> not (has_value th x)) (free_vars th e)

(* The unit to give a result of dimension [d] in, and its size in base units:
   the one asked for, else the declared one, else units picked for d. *)
let result_unit th d ~asked ~declared ~statement =
  let u =
    match (asked, declared) with
    | Some u, _ | None, Some u -> Some u
    | None, None -> if Dim.is_one d then Some DOne else Option.map dexpr_of_units (auto_units th d)
  in
  match u with
  | None -> fail "there are no units to give the result in: `import SI`, or name one with `%s ... in ...`" statement
  | Some u ->
      let ud, f = eval_unit th u in
      if not (Dim.equal ud d) then
        fail "the result is [%s], but `%s` is [%s]" (Dim.to_string d) (Pretty.dexpr_to_string u) (Dim.to_string ud);
      (u, f)

(* A decimal string from SymPy, possibly negative or with an exponent. *)
let parse_number s =
  let s, neg = if s <> "" && s.[0] = '-' then (String.sub s 1 (String.length s - 1), true) else (s, false) in
  let q = try Lexer.decimal s with _ -> fail "SymPy gave the value `%s`, which is not a number" s in
  if neg then Q.neg q else q

(* The number [e] is in base units, which must need no unknowns. *)
let base_number th e = Q.to_string (parse_number (Cas.evaluate ~digits:20 (in_base_units th e)))

(* A bare number for a variable declared in a scaled dimensionless unit, as
   30 for an angle in degrees, is read in base units (30 rad), which is not
   what anyone means: ask for the unit. [write] shows the fix for a value. *)
let check_bare th x e write =
  let rec bare = function Num q -> Some q | Neg a -> Option.map Q.neg (bare a) | _ -> None in
  match (bare e, Option.bind (find_var th x) (fun v -> v.vunit)) with
  | Some q, Some u when not (Q.equal q Q.zero) ->
      let _, f = eval_unit th u and angle, _ = angle_hz th u in
      if not (is_unscaled f) then
        fail "`%s` is declared in %s: write `%s`%s" x (Pretty.dexpr_to_string u)
          (write (Pretty.expr (Quantity (q, u))))
          (if Q.equal angle Q.zero then "" else sprintf " (a bare %s would be %s rad)" (Pretty.expr e) (Pretty.expr e))
  | _ -> ()

(* Radians and cycles are both dimensionless, so 3 rad/s and 3 Hz look alike
   to the dimensions, but 1 Hz is 2π rad/s. A value given in one cannot be
   shown in the other without that 2π, so say so rather than give a number. *)
let check_cycles th e u =
  let source =
    match e with
    | Quantity (_, su) -> Some su
    | Var x -> Option.bind (find_var th x) (fun v -> Option.map snd v.value)
    | _ -> None
  in
  match source with
  | Some su ->
      let (a1, h1), (a2, h2) = (angle_hz th su, angle_hz th u) in
      if (not (Q.equal a1 a2)) && not (Q.equal h1 h2) then
        let fix = if Q.gt h2 h1 then sprintf "%s/(2*pi)" else sprintf "2*pi*%s" in
        fail "`%s` cannot be given in %s without a factor 2π: Hz counts cycles, and a cycle is 2π rad. Write `%s` in %s"
          (Pretty.expr e) (Pretty.dexpr_to_string u) (fix (Pretty.expr e)) (Pretty.dexpr_to_string u)
  | None -> ()

(* The value of [e], which has no unknowns left, as a quantity in unit u. *)
let numeric th ~digits e (u, f) =
  check_cycles th e u;
  Quantity (parse_number (Cas.evaluate ~digits (Div (in_base_units th e, scale_expr f))), u)

let describe = function
  | Ref (None, n) -> n
  | Ref (Some t, n) -> t ^ "." ^ n
  | Inst _ -> "instantiate"
  | Solve (_, xs, _, []) -> "solve for " ^ String.concat ", " xs
  | Solve (_, xs, _, _) -> "solve for " ^ String.concat ", " xs ^ " with initial conditions"
  | Apply (f, _) -> "apply " ^ f
  | Integrate (_, x, a, b) -> sprintf "integrate by %s from %s to %s" x (Pretty.expr a) (Pretty.expr b)
  | Subst _ -> "subst"
  | Simplify _ -> "simplify"
  | Unfold _ -> "unfold"
  | Component (_, _, c) -> "component " ^ c
  | Expand _ -> "expand"
  | Differentiate (_, x) -> "differentiate by " ^ x
  | NSolve (_, x, g, _) -> sprintf "solve for %s numerically near %s" x (Pretty.expr g)
  | Approximate (_, smalls, order) ->
      sprintf "approximate (%s, order %d)"
        (String.concat ", " (List.map (fun (x, b) -> x ^ " ≪ " ^ Pretty.expr b) smalls))
        (Option.value order ~default:1)
  | Limit (_, x, p) -> sprintf "limit %s → %s" x (Pretty.expr p)
  | Evaluate (_, Some u, _) -> "evaluate in " ^ Pretty.dexpr_to_string u
  | Evaluate (_, None, _) -> "evaluate"

let rec eval th locals s =
  match s with
  | Ref (q, n) -> find_law th locals (q, n)
  | Inst (s, subs) ->
      let v = eval th locals s in
      List.iter
        (fun (x, e) ->
          let vi = check_var th x in
          let se = Shape.infer (shape_env th) e and sx = Shape.to_s (shape_of_attrs vi.attrs) in
          if se <> Shape.Zero && se <> sx then
            fail "cannot put `%s` (a %s) in place of `%s` (a %s)" (Pretty.expr e) (Shape.s_name se) x
              (Shape.s_name sx);
          let st = Infer.create () in
          let de = Infer.infer st (env th) e in
          Infer.unify st de vi.vdim (fun de dx ->
              sprintf "cannot put `%s` [%s] in place of `%s` [%s]" (Pretty.expr e) (Dim.to_string de) x
                (Dim.to_string dx));
          check_bare th x e (fun v -> x ^ " := " ^ v))
        subs;
      let names = List.map fst subs in
      let f e = tidy (subst_expr ~deps:(deps_of th) subs (unfold th (def_mentions th names) e)) in
      { v with veq = map_eq f v.veq }
  | Subst (a, b) ->
      let va = eval th locals a in
      let vb = eval th locals b in
      let combine veq =
        {
          veq;
          vuses = union va.vuses vb.vuses;
          vassumes = union va.vassumes vb.vassumes;
          vconsts = union va.vconsts vb.vconsts;
        }
      in
      let by_var x r =
        let target = map_eq (unfold th (def_mentions th [ x ])) vb.veq in
        if not (mentions th [ x ] target.lhs || mentions th [ x ] target.rhs) then
          fail "`%s` does not appear in `%s`" x (Pretty.eq vb.veq);
        combine (map_eq (fun e -> normalize th (subst_expr ~deps:(deps_of th) [ (x, r) ] e)) target)
      in
      (* With `curl(B) = ...`, replace that whole expression wherever it appears. *)
      let by_pattern () =
        let all e = normalize th (unfold th (fun _ -> true) e) in
        let target = map_eq all vb.veq in
        let rec occurs p e = e = p || List.exists (occurs p) (children e) in
        let rec replace p r e = if e = p then r else map_children (replace p r) e in
        let try_side p r =
          if occurs p target.lhs || occurs p target.rhs then Some (map_eq (fun e -> normalize th (replace p r e)) target)
          else None
        in
        let q = map_eq all va.veq in
        match try_side q.lhs q.rhs with
        | Some t -> combine t
        | None -> (
            match try_side q.rhs q.lhs with
            | Some t -> combine t
            | None ->
                fail "neither `%s` nor `%s` appears in `%s`" (Pretty.expr q.lhs) (Pretty.expr q.rhs)
                  (Pretty.eq target))
      in
      (match va.veq with
      | { lhs = Var x; rhs } -> by_var x rhs
      | { lhs; rhs = Var x } -> by_var x lhs
      | _ -> by_pattern ())
  | Solve ([ s ], [ x ], root, ics) ->
      let v = eval th locals s in
      ignore (check_var th x);
      let q = map_eq (prepare th) v.veq in
      (match (snd (check_eq th q), is_vector th x) with
      | Shape.Vector _, false ->
          fail "cannot solve a vector equation for the scalar `%s`: take dot(...) or norm(...) of both sides first" x
      | Shape.Scalar, true -> fail "cannot solve a scalar equation for the vector `%s`" x
      | _ -> ());
      (* a differential equation when x(t) appears inside a derivative *)
      let rec has_diff_of e =
        match e with
        | Call ("diff", [ f; _ ]) when List.mem x (vars [] f) -> true
        | _ -> List.exists has_diff_of (children e)
      in
      let ode = deps_of th x <> [] && (has_diff_of q.lhs || has_diff_of q.rhs) in
      if ics <> [] && not ode then fail "initial conditions apply only to a differential equation in `%s`" x;
      if ode && is_vector th x then fail "solve a vector differential equation one component at a time";
      List.iter (fun ic -> ignore (check_eq th ic)) ics;
      let sols =
        if ode then Cas.dsolve ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) q x (List.map (map_eq (prepare th)) ics)
        else Cas.solve ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) q x
      in
      let sols = List.map (vectors_last th) sols in
      let n = List.length sols in
      let pick =
        match (sols, root) with
        | [], _ -> fail "SymPy found no solution of `%s` for `%s`" (Pretty.eq q) x
        | [ s ], None -> s
        | _, None ->
            fail "`%s` has %d solutions; pick one with `, root k`:\n%s" x n
              (String.concat "\n"
                 (List.mapi (fun i s -> sprintf "    %d: %s = %s" (i + 1) x (Pretty.expr s)) sols))
        | _, Some k when k >= 1 && k <= n -> List.nth sols (k - 1)
        | _, Some k -> fail "there is no root %d; `%s` has %s" k x (plural n "solution")
      in
      let pick, consts = if ode then integration_constants th x pick else (pick, []) in
      {
        v with
        veq = { lhs = Var x; rhs = pick };
        vassumes = union v.vassumes (assumptions th q);
        vconsts = v.vconsts @ consts;
      }
  | Solve (ss, xs, root, ics) ->
      (* A system: the result is the equation for the first unknown, with the
         others eliminated. A vector equation counts as its components. *)
      let vs = List.map (eval th locals) ss in
      if ics <> [] then fail "initial conditions need a single differential equation";
      List.iter
        (fun x ->
          ignore (check_var th x);
          if is_vector th x then fail "solve for the components of the vector `%s`, such as %s.x" x x)
        xs;
      let equations =
        List.concat_map
          (fun v ->
            let q = map_eq (prepare th) v.veq in
            match snd (check_eq th q) with
            | Shape.Scalar -> [ q ]
            | Shape.Vector n -> List.init n (fun i -> map_eq (fun e -> tidy (component th (i + 1) e)) q)
            | Shape.Matrix n ->
                List.concat (List.init n (fun i -> List.init n (fun j -> map_eq (fun e -> tidy (entry th (i + 1) (j + 1) e)) q))))
          vs
      in
      List.iter
        (fun q ->
          let rec has_diff e =
            match e with
            | Call ("diff", [ f; _ ]) when List.exists (fun x -> List.mem x (vars [] f)) xs -> true
            | _ -> List.exists has_diff (children e)
          in
          if has_diff q.lhs || has_diff q.rhs then fail "systems of differential equations are not supported yet")
        equations;
      let x = List.hd xs in
      let all = Cas.solve_system ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) equations xs in
      if all <> [] && List.for_all (function None :: _ -> true | _ -> false) all then
        fail "these equations do not determine `%s`: they leave it free" x;
      let sets =
        all
        (* keep the sets that determine the first unknown *)
        |> List.filter_map (fun vals ->
               match List.map (Option.map (vectors_last th)) vals with
               | Some first :: _ as vals -> Some (vals, first)
               | _ -> None)
      in
      let show (vals, _) =
        String.concat ", "
          (List.map2 (fun x v -> x ^ " = " ^ match v with Some e -> Pretty.expr e | None -> "(free)") xs vals)
      in
      let n = List.length sets in
      let pick =
        match (sets, root) with
        | [], _ -> fail "SymPy found no solution of these equations for %s" (String.concat ", " xs)
        | [ (_, first) ], None -> first
        | _, None ->
            fail "the system has %d solutions; pick one with `, root k`:\n%s" n
              (String.concat "\n" (List.mapi (fun i s -> sprintf "    %d: %s" (i + 1) (show s)) sets))
        | _, Some k when k >= 1 && k <= n -> snd (List.nth sets (k - 1))
        | _, Some k -> fail "there is no root %d; the system has %s" k (plural n "solution")
      in
      {
        veq = { lhs = Var x; rhs = pick };
        vuses = List.fold_left (fun acc v -> union acc v.vuses) [] vs;
        vassumes =
          List.fold_left (fun acc q -> union acc (assumptions th q)) (List.fold_left (fun acc v -> union acc v.vassumes) [] vs) equations;
        vconsts = List.concat_map (fun v -> v.vconsts) vs;
      }
  | Apply (f, s) ->
      let v = eval th locals s in
      let unary = [ "grad"; "div"; "curl"; "lap"; "norm"; "sqrt"; "abs"; "conj" ] @ Infer.dimensionless_fns in
      (match find_def th f with
      | Some d when List.length d.params = 1 -> ()
      | Some _ -> fail "`apply` needs a function of one argument, but `%s` takes several" f
      | None when List.mem f unary -> ()
      | None -> fail "`apply` needs a function of one argument such as curl, div, grad, lap or sqrt; `%s` is not one" f);
      (* f(a) = f(b) follows from a = b for any function f *)
      { v with veq = map_eq (fun e -> normalize th (Call (f, [ unfold th (fun _ -> true) e ]))) v.veq }
  | Integrate (s, x, a, b) ->
      let v = eval th locals s in
      (match find_var th x with
      | None -> fail "`%s` is not a declared variable" x
      | Some vi when not_scalar vi.attrs -> fail "cannot integrate over the vector `%s`" x
      | Some _ -> ());
      { v with veq = map_eq (fun e -> Call ("integral", [ unfold th (fun _ -> true) e; Var x; a; b ])) v.veq }
  | Simplify s ->
      let v = eval th locals s in
      let q = map_eq (prepare th) v.veq in
      let simp e = match e with Var _ | Num _ -> e | _ -> tidy @@ vectors_last th (Cas.simplify ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) e) in
      (* If lhs - rhs simplifies to 0, in every component, the law holds identically. *)
      let components = match tidy (Sub (q.lhs, q.rhs)) with Call ("vec", xs) -> xs | d -> [ d ] in
      let zero e = match e with Num z -> Q.equal z Q.zero | _ -> false in
      let veq =
        if List.for_all (fun c -> zero (simp c)) components then { lhs = Num Q.zero; rhs = Num Q.zero }
        else
          match map_eq simp q with
          | { lhs = Neg a; rhs = Neg b } -> { lhs = a; rhs = b } (* -a = -b reads better as a = b *)
          | q -> q
      in
      { v with veq; vassumes = union v.vassumes (assumptions th q) }
  | Unfold s ->
      let v = eval th locals s in
      { v with veq = map_eq (unfold th (fun _ -> true)) v.veq }
  | Component (s, k, _) -> (
      let v = eval th locals s in
      let q = map_eq (unfold th (fun _ -> true)) v.veq in
      match snd (check_eq th q) with
      | Shape.Scalar -> fail "`component` needs a vector equation, but `%s` is scalar" (Pretty.eq q)
      | Shape.Matrix _ -> fail "`%s` is a matrix equation: multiply it by a vector, or use entry(..., i, j)" (Pretty.eq q)
      | Shape.Vector n when k > n -> fail "a %d-vector has no component %s" n (component_name k)
      | Shape.Vector _ -> { v with veq = map_eq (fun e -> tidy (component th k e)) q })
  | Differentiate (s, x) ->
      let v = eval th locals s in
      (match find_var th x with
      | None -> fail "`%s` is not a declared variable" x
      | Some vi when not_scalar vi.attrs -> fail "cannot differentiate by the vector `%s`; use one of its components" x
      | Some _ -> ());
      let q = map_eq (unfold th (fun _ -> true)) v.veq in
      if not (depends th x q.lhs || depends th x q.rhs) then
        fail "nothing in `%s` depends on `%s`, so both sides would be 0" (Pretty.eq q) x;
      { v with veq = map_eq (fun e -> Call ("diff", [ e; Var x ])) q }
  | Evaluate (s, unit, digits) ->
      let v = eval th locals s in
      let digits = check_digits digits in
      let q = map_eq (prepare th) v.veq in
      let d, shape = check_eq th q in
      if shape <> Shape.Scalar then fail "`evaluate` works on scalar equations; take a component first";
      let known e = missing_values th e = [] in
      let missing = missing_values th in
      let target declared = result_unit th d ~asked:unit ~declared ~statement:"evaluate" in
      let value = numeric th ~digits in
      let declared x = Option.bind (find_var th x) (fun v -> v.vunit) in
      let veq =
        match q with
        | { lhs = Var x; rhs } when (not (known (Var x))) && known rhs -> { lhs = Var x; rhs = value rhs (target (declared x)) }
        | { lhs; rhs = Var x } when (not (known (Var x))) && known lhs -> { lhs = Var x; rhs = value lhs (target (declared x)) }
        | { lhs; rhs } when known lhs && known rhs ->
            (* everything is known: check the equation, to the digits asked for *)
            let u = target (match lhs with Var x -> declared x | _ -> None) in
            let a = value lhs u and b = value rhs u in
            if a <> b then
              fail "the equation does not hold: the left side is %s but the right side is %s (to %d digits)"
                (Pretty.expr a) (Pretty.expr b) digits;
            { lhs = a; rhs = b }
        | { lhs; rhs } ->
            (* something is still unknown besides a lone x on one side *)
            let quoted xs = String.concat ", " (List.map (fun x -> "`" ^ x ^ "`") xs) in
            let still = match (lhs, rhs) with Var _, e | e, Var _ -> missing e | _ -> [] in
            if still <> [] then
              fail "give values for %s: put them in with `law[x := 3 [m]]`, or declare them with `const`" (quoted still)
            else
              fail "`evaluate` needs `x = ...` with everything else known; solve for one unknown first (unknown: %s)"
                (quoted (List.sort_uniq compare (missing lhs @ missing rhs)))
      in
      { v with veq }
  | NSolve (s, x, guess, digits) ->
      let v = eval th locals s in
      let digits = check_digits digits in
      let vi = check_var th x in
      if not_scalar vi.attrs then fail "solve numerically for a component, not the vector `%s`" x;
      if vi.deps <> [] then fail "`%s` is a function of %s; use `simulate` for differential equations" x (String.concat ", " vi.deps);
      let q = map_eq (prepare th) v.veq in
      (match snd (check_eq th q) with
      | Shape.Vector _ -> fail "take a component first"
      | Shape.Matrix _ -> fail "solve a matrix equation one entry at a time"
      | Shape.Scalar -> ());
      ignore (check_eq th { lhs = Var x; rhs = guess });
      let e = tidy (Sub (in_base_units th q.lhs, in_base_units th q.rhs)) in
      (match List.filter (fun y -> y <> x) (free_vars th e) with
      | [] -> ()
      | ys ->
          fail "give values for %s first, so that only `%s` is unknown"
            (String.concat ", " (List.map (fun y -> "`" ^ y ^ "`") ys)) x);
      let root = Cas.nsolve ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) e x (in_base_units th guess) in
      let value =
        numeric th ~digits (Num (parse_number root))
          (result_unit th vi.vdim ~asked:None ~declared:vi.vunit ~statement:"solve")
      in
      {
        v with
        veq = { lhs = Var x; rhs = value };
        vassumes = union v.vassumes [ sprintf "the root near %s" (Pretty.expr guess) ];
      }
  | Approximate (s, smalls, order) ->
      let v = eval th locals s in
      let order = Option.value order ~default:1 in
      if order < 0 || order > 20 then fail "the order must be between 0 and 20";
      (* `v << c` only makes sense when v/c is dimensionless *)
      List.iter
        (fun (x, b) ->
          let vi = check_var th x in
          if not_scalar vi.attrs then fail "`%s` is a vector; say which component is small, or use its norm" x;
          if List.mem x (vars [] b) then fail "in `%s << %s`, the scale cannot depend on `%s`" x (Pretty.expr b) x;
          let r = Div (Var x, b) in
          let d = Infer.check_eq (env th) { lhs = r; rhs = r } in
          if not (Dim.is_one d) then
            fail "`%s << %s` compares [%s] with [%s]: a small quantity is small compared with something of the same dimension, as in v << c"
              x (Pretty.expr b) (Dim.to_string vi.vdim) (Dim.to_string (Dim.sub vi.vdim d)))
        smalls;
      (* every small variable times a bookkeeping ε; expand in ε; then ε = 1 *)
      let eps = "#eps" in
      let scaled = List.map (fun (x, _) -> (x, Mul (Var eps, Var x))) smalls in
      let attrs_of v = if v = eps then [ "positive" ] else attrs_of th v in
      let left_out = ref [] in
      let rec approx e =
        match e with
        | Call ("vec", xs) -> Call ("vec", List.map approx xs)
        | _ when not (List.mem eps (vars [] e)) -> e
        | _ ->
            (match shape th e with
            | Shape.V _ -> fail "`approximate` works on scalars and explicit vectors; take a component first"
            | _ -> ());
            let kept, next = Cas.series ~attrs_of ~deps_of:(cas_deps th) e eps order in
            Option.iter (fun n -> left_out := !left_out @ [ Pretty.expr n ]) next;
            tidy kept
      in
      let q = map_eq (fun e -> subst_expr ~deps:(deps_of th) scaled (prepare th e)) v.veq in
      let veq = map_eq approx q in
      let note =
        sprintf "%s (to order %d)%s"
          (String.concat ", " (List.map (fun (x, b) -> x ^ " ≪ " ^ Pretty.expr b) smalls))
          order
          (match !left_out with [] -> "" | ts -> "; left out: " ^ String.concat ", " ts)
      in
      { v with veq; vassumes = union v.vassumes [ note ] }
  | Limit (s, x, point) ->
      let v = eval th locals s in
      let vi = check_var th x in
      if not_scalar vi.attrs then fail "cannot take a limit in the vector `%s`" x;
      ignore (check_eq th { lhs = Var x; rhs = point });
      (* a lone x(t) goes to its value there, v(inf); anything else to SymPy *)
      let lim e =
        match e with
        | Var y when deps_of th y = [ x ] -> Call (y, [ point ])
        | Var y when List.mem x (deps_of th y) -> Call ("at", [ e; Var x; point ])
        | _ when not (depends th x e) -> e
        | _ ->
            (match shape th e with Shape.V _ -> fail "take a component before the limit" | _ -> ());
            tidy (Cas.limit ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) (prepare th e) x point)
      in
      { v with veq = map_eq lim v.veq; vassumes = union v.vassumes [ sprintf "%s → %s" x (Pretty.expr point) ] }
  | Expand s ->
      let v = eval th locals s in
      { v with veq = map_eq (fun e -> tidy (expand th (tidy (integrals th (unfold th (fun _ -> true) e))))) v.veq }

let run_derive th steps =
  let trace = ref [] in
  let _, last =
    List.fold_left
      (fun (locals, _) (st : step) ->
        let v = try eval th locals st.body with Infer.Error m -> raise (Located (st.sline, m)) in
        (* Re-check every result: a failure here means the CAS bridge broke something. *)
        (try ignore (check_eq th v.veq)
         with Infer.Error m ->
           raise
             (Located (st.sline, "this step produced a dimensionally inconsistent equation (CAS bridge bug?): " ^ m)));
        trace := (st, v) :: !trace;
        let locals = match st.name with Some n -> (n, v) :: locals | None -> locals in
        (locals, Some v))
      ([], None) steps
  in
  match last with
  | None -> fail "empty derivation"
  | Some v -> (v, check_eq th v.veq, List.rev !trace)

(* ---- declarations ---- *)

let attributes = [ "positive"; "nonzero"; "real"; "complex"; "integer"; "vector"; "position"; "matrix" ]

(* A theory has at most one position vector, also counting imported ones. *)
let check_position th =
  match List.filter (fun (_, e) -> is_position e.v.attrs) th.vars with
  | (a, _) :: (b, _) :: _ -> fail "a theory can have only one position vector, but `%s` and `%s` both are" a b
  | _ -> ()

(* What a simulation shows: the time axis and each unknown, in display units. *)
type simulated = {
  title : string;
  equations : eq list;
  axis : string * dexpr * float list;
  curves : (string * dexpr * Dim.t * float list) list;
  solver : string;
}

(* What checking a declaration produced, for the text and JSON reports. *)
(* What a free-body diagram shows: the law it wrote, and arrows to draw, with
   directions as numbers when the drawing values make them known. *)
type drawn = {
  dname : string;
  law : eq;
  law_dim : Dim.t * Shape.t;
  body : expr;
  arrows : (string * expr * (float * float) option) list; (* label, magnitude, direction *)
  accel : (expr * (float * float) option) option;
  plane : (float * float) option;
  missing : string list; (* what the picture needs values for *)
  marks : (expr * (float * float) option * (float * float) option * bool) list;
      (* label, the two directions, and whether it goes at the foot of the plane *)
}

type shown =
  | SImport of string
  | SDim of (string * string option) list
  | SUnits of (string * unit_info) list
  | SConst of (string * Q.t * dexpr * Dim.t) list
  | SCompute of string option * expr * expr * Dim.t (* the expression, its value as a quantity *)
  | SSimulate of simulated
  | SGroups of grouped
  | SEigen of eigened
  | SDiagram of drawn
  | SAlias of string * Dim.t
  | SVar of (string * string list) list * Dim.t * string list * dexpr option (* the unit, if declared in one *)
  | SDef of string * string list * expr * Infer.scheme * Shape.table option (* shapes, shown when vectors are in scope *)
  | SLaw of string * eq * (Dim.t * Shape.t)
  | SDerive of string * value * (Dim.t * Shape.t) * (step * value) list

(* ---- modules ---- *)

(* Directories searched for module files: the checked file's own, any given
   with --modules, then Landau's modules/. *)
let extra_module_dirs : string list ref = ref []
let stdin_as : string option ref = ref None (* --as FILE: the source on stdin is this file *)
let module_path : string list ref = ref []
let current_file : string option ref = ref None
let loaded_modules : (string, string list) Hashtbl.t = Hashtbl.create 4 (* file -> its theories *)
let module_of_theory : (string, string) Hashtbl.t = Hashtbl.create 8 (* theory -> file *)
let loading : string list ref = ref [] (* for import cycles *)

(* Where files can be compared and resolved: the native executable sets
   these with Unix; in the browser, module files have a single name each. *)
let same_file_hook : (string -> string -> bool) ref = ref String.equal
let realpath_hook : (string -> string) ref = ref Fun.id
let same_file a b = !same_file_hook a b

let is_current f = match !current_file with Some c -> same_file c f | None -> false
let module_name f = Filename.remove_extension (Filename.basename f)

let module_files () =
  List.concat_map
    (fun d ->
      match Sys.readdir d with
      | names ->
          Array.to_list names |> List.filter (fun n -> Filename.check_suffix n ".lan") |> List.sort compare
          |> List.map (Filename.concat d)
      | exception Sys_error _ -> [])
    !module_path

let parse_file file =
  let ic = open_in_bin file in
  Fun.protect ~finally:(fun () -> close_in ic) @@ fun () ->
  let lexbuf = Lexing.from_channel ic in
  Lexing.set_filename lexbuf file;
  try Parser.file Lexer.token lexbuf
  with Lexer.Error _ | Parser.Error | Syntax_error _ ->
    fail "the module %s has a syntax error on line %d" (Filename.basename file) lexbuf.lex_start_p.pos_lnum

let cycle_through files = String.concat " -> " (List.map module_name files)

(* A module file named n.lan. The file being checked can only be found by a
   module it imports, which is a cycle. *)
let module_file n =
  match List.find_opt (fun f -> module_name f = n) (module_files ()) with
  | Some f when is_current f ->
      if !loading = [] then fail "a module cannot import itself"
      else fail "modules import each other in a circle: %s" (cycle_through ((f :: List.rev !loading) @ [ f ]))
  | found -> found

(* The module file that defines a theory named n, if exactly one does. *)
let theory_in_modules n =
  let defines f =
    (not (is_current f))
    && (try List.exists (function Theory (t, _) -> t = n | Top _ -> false) (parse_file f) with Infer.Error _ -> false)
  in
  match List.filter defines (module_files ()) with
  | [] -> None
  | [ f ] -> Some f
  | fs ->
      fail "a theory `%s` is defined in %s; say which one, as in `import %s from %s`" n
        (String.concat " and " (List.map Filename.basename fs)) n (module_name (List.hd fs))

(* ---- simulations ---- *)

(* How many times x is differentiated by t, at most, in e (-1 if absent). *)
let rec order_of t x e =
  match e with
  | Var y -> if y = x then 0 else -1
  | Call ("diff", [ f; Var tt ]) when tt = t -> ( match order_of t x f with -1 -> -1 | k -> k + 1)
  | _ -> List.fold_left (fun acc c -> max acc (order_of t x c)) (-1) (children e)

let rec process theories th d =
  let origin = th.tname in
  match d.desc with
  | Import (n, m) ->
      let from_module =
        match m with
        | None -> resolve theories n
        | Some m -> (
            match module_file m with
            | None -> fail "there is no module file %s.lan in %s" m (String.concat ", " !module_path)
            | Some file ->
                if not (List.mem n (load_module theories file)) then
                  fail "the module %s has no theory `%s`; it has %s" m n (String.concat ", " (load_module theories file));
                [ Hashtbl.find theories n ])
      in
      (try
         List.iter
           (fun from ->
             import th from;
             check_position th;
             List.iter
               (fun (u, _) -> if List.mem_assoc u th.dims then fail "`%s` is both a dimension and a unit of %s" u n)
               from.units)
           from_module
       with Infer.Error msg when List.length from_module > 1 ->
         fail "the theories of module %s clash when imported together (%s); import one of them: %s" n msg
           (String.concat ", " (List.map (fun t -> sprintf "`import %s from %s`" t.tname n) from_module)));
      SImport (match m with Some m -> n ^ " from " ^ m | None -> n)
  | DimBase ns ->
      List.iter
        (fun (n, sym) ->
          if find_unit th n <> None then fail "`%s` is already a unit; a dimension needs another name" n;
          Dim.register n;
          Option.iter (Hashtbl.replace Dim.symbols n) sym;
          th.dims <- add_entry "dimension" same_dim th.dims n { origin; v = Dim.base n })
        ns;
      SDim ns
  | Simulate sim -> SSimulate (simulate theories th sim)
  | Groups (name, target, xs) -> SGroups (groups th name target xs)
  | Eigen (name, a, b) -> SEigen (eigen th name a b)
  | Diagram (name, items) ->
      let dg = diagram th name items in
      if List.mem_assoc name th.laws then fail "law `%s` is already defined" name;
      th.laws <- add_entry "law" never th.laws name { origin; v = { eq = dg.law; uses = [ origin ^ "." ^ name ]; assumes = [] } };
      SDiagram dg
  | Compute (name, e, unit, digits) ->
      let digits = check_digits digits in
      (match Shape.infer (shape_env th) e with
      | Shape.V _ -> fail "`compute` gives one number; take a component, as in `compute F.x`"
      | Shape.M _ -> fail "`compute` gives one number; take an entry, as in `compute entry(A, 1, 2)`, or det(A)"
      | _ -> ());
      let d = Infer.check_eq (env th) { lhs = e; rhs = e } in
      let d = if Dim.vars d <> [] then Dim.one else d in
      let p = prepare th e in
      (match missing_values th p with
      | [] -> ()
      | xs ->
          fail "give values for %s: write quantities such as `2 [kg]`, or declare constants with `const`"
            (String.concat ", " (List.map (fun x -> "`" ^ x ^ "`") xs)));
      (* a lone dimensionless quantity keeps its unit: 45 [deg] stays in degrees *)
      let unit = match (unit, e) with None, Quantity (_, u) when Dim.is_one d -> Some u | _ -> unit in
      let value = numeric th ~digits p (result_unit th d ~asked:unit ~declared:None ~statement:"compute") in
      Option.iter
        (fun n ->
          match value with
          | Quantity (q, u) ->
              let attrs = if Q.sign q > 0 then [ "positive" ] else if Q.sign q < 0 then [ "nonzero" ] else [] in
              let vunit = if u = DOne then None else Some u in
              th.vars <-
                add_entry "variable" never th.vars n
                  { origin; v = { vdim = d; attrs; deps = []; vunit; value = Some (q, u) } }
          | _ -> ())
        name;
      SCompute (name, e, value, d)
  | ConstDecl cs ->
      let declare (n, q, u) =
        let vdim = eval_dim th u in
        let attrs = if Q.sign q > 0 then [ "positive" ] else if Q.sign q < 0 then [ "nonzero" ] else [] in
        let vunit = if u = DOne then None else Some u in
        th.vars <- add_entry "variable" never th.vars n { origin; v = { vdim; attrs; deps = []; vunit; value = Some (q, u) } };
        (n, q, u, vdim)
      in
      SConst (List.map declare cs)
  | Units us ->
      let declare (n, def) =
        if List.mem_assoc n th.dims then fail "`%s` is already a dimension; a unit needs another name" n;
        let info =
          match def with
          | UBase (DName b as de) when List.mem_assoc b th.dims ->
              let d = eval_dim th de in
              if not (Dim.equal d (Dim.base b)) then fail "a base unit needs a base dimension, but `%s` is an alias" b;
              (match List.find_opt (fun (_, e) -> e.v.base && Dim.equal e.v.udim d) th.units with
              | Some (other, _) ->
                  fail "`%s` already has the base unit `%s`; define `%s` from it with its size, as in `unit %s = k*%s`" b
                    other n n other
              | None -> ());
              { udim = d; factor = unscaled; base = true; angle = Q.zero; hz = Q.zero }
          | UBase _ -> fail "a base unit is declared for a base dimension, as in `unit m : Length`"
          | UDerived de ->
              let udim, factor = eval_unit th de in
              (* the radian and the hertz are where angles and cycles start *)
              let angle, hz = angle_hz th de in
              let angle = if n = "rad" then Q.one else angle and hz = if n = "Hz" then Q.one else hz in
              { udim; factor; base = false; angle; hz }
        in
        Dim.register n;
        th.units <- add_entry "unit" never th.units n { origin; v = info };
        (n, info)
      in
      SUnits (List.map declare us)
  | DimAlias (n, de) ->
      let v = eval_dim th de in
      th.dims <- add_entry "dimension" never th.dims n { origin; v };
      SAlias (n, v)
  | VarDecl (ns, de, attrs) ->
      List.iter
        (fun a ->
          if not (List.mem (attr_name a) attributes) then
            fail "unknown attribute `%s` (expected one of: %s)" a (String.concat ", " attributes);
          match (attr_name a, attr_size a) with
          | ("vector" | "position"), Some n when n >= 1 -> ()
          | ("vector" | "position"), None when not (String.contains a '(') -> ()
          | ("vector" | "position"), _ -> fail "the size in `%s` must be a whole number, at least 1" a
          | "matrix", Some n when n >= 2 -> ()
          | "matrix", _ -> fail "a matrix needs its size, a whole number of at least 2: `matrix(2)` is 2×2"
          | n, _ when String.contains a '(' -> fail "`%s` takes no size" n
          | _ -> ())
        attrs;
      if not_scalar attrs then
        List.iter
          (fun a -> if List.mem a [ "positive"; "nonzero" ] then fail "a %s cannot be `%s` (only scalars are ordered)" (kind_name attrs) a)
          attrs;
      if is_vector_attrs attrs && is_matrix_attrs attrs then fail "a variable is a vector or a matrix, not both";
      if is_position attrs then (
        match Option.to_list (Option.map fst (position th)) @ List.map fst ns with
        | a :: b :: _ -> fail "a theory can have only one position vector, but `%s` and `%s` both are" a b
        | _ -> ());
      List.iter
        (fun (n, deps) ->
          List.iter
            (fun d ->
              if d = n then fail "`%s` cannot depend on itself" n;
              match find_var th d with
              | None -> fail "`%s` depends on `%s`, which is not declared yet" n d
              | Some _ -> ())
            deps)
        ns;
      let vdim = eval_dim th de in
      (* a count, like the n of a level E_n: SymPy then knows sin(n*pi) = 0 *)
      if List.mem "integer" attrs then (
        if not_scalar attrs then fail "a %s cannot be `integer`" (kind_name attrs);
        if List.mem "complex" attrs then fail "a variable cannot be both `integer` and `complex`";
        if not (Dim.is_one vdim) then
          fail "an integer counts, so it is dimensionless, but `%s` is [%s]" (String.concat ", " (List.map fst ns))
            (Dim.to_string vdim));
      let vunit = if mentions_unit th de then Some de else None in
      List.iter
        (fun (n, deps) -> th.vars <- add_entry "variable" never th.vars n { origin; v = { vdim; attrs; deps; vunit; value = None } })
        ns;
      SVar (ns, vdim, attrs, vunit)
  | Def (n, ps, body) ->
      if List.mem n Infer.builtins then fail "`%s` is a built-in function; choose another name" n;
      let params = List.map (fun (p, a) -> (p, Option.map (eval_dim th) a)) ps in
      let shapes = Shape.infer_def (shape_env th) (vector_sizes th) (List.map fst ps) body in
      let scheme = Infer.infer_def (env th) params body in
      th.defs <- add_entry "definition" never th.defs n { origin; v = { params = List.map fst ps; body; scheme; shapes } };
      SDef (n, List.map fst ps, body, scheme, if has_vectors th then Some shapes else None)
  | Law (n, q) ->
      let dq = check_eq th q in
      ignore (map_eq (fun e -> check_derivatives th (unfold th (fun _ -> true) e); e) q);
      th.laws <- add_entry "law" never th.laws n { origin; v = { eq = q; uses = [ origin ^ "." ^ n ]; assumes = [] } };
      SLaw (n, q, dq)
  | Derive (n, steps) ->
      if List.mem_assoc n th.laws then fail "law `%s` is already defined" n;
      let v, dq, trace = run_derive th steps in
      th.laws <- add_entry "law" never th.laws n { origin; v = { eq = v.veq; uses = v.vuses; assumes = v.vassumes } };
      SDerive (n, v, dq, trace)

(* What `import n` brings in: a theory of this file, a built-in one, every
   theory of the module file n.lan, or the theory n from a module file. *)
and resolve theories n =
  match Hashtbl.find_opt theories n with
  | Some t -> [ t ]
  | None -> (
      match builtin theories n with
      | Some t -> [ t ]
      | None -> (
          match module_file n with
          | Some file -> List.map (Hashtbl.find theories) (load_module theories file)
          | None -> (
              match theory_in_modules n with
              | Some file ->
                  ignore (load_module theories file);
                  [ Hashtbl.find theories n ]
              | None ->
                  fail "unknown theory or module `%s`: a theory must be defined before it is imported, and module files are looked for in %s"
                    n
                    (match !module_path with [] -> "no directory" | ds -> String.concat ", " ds))))

(* Check a module file and add its theories; declarations outside a theory
   go to a theory named after the file. Returns the names of its theories. *)
and load_module theories file =
  match Hashtbl.find_opt loaded_modules file with
  | Some names -> names
  | None ->
      if List.mem file !loading then
        fail "modules import each other in a circle: %s"
          (String.concat " -> " (List.rev_map module_name (file :: !loading)));
      loading := file :: !loading;
      Fun.protect ~finally:(fun () -> loading := List.tl !loading) @@ fun () ->
      let base = module_name file in
      let add name ds =
        (match Hashtbl.find_opt module_of_theory name with
        | Some other when not (same_file other file) ->
            fail "the theory `%s` of module %s has the same name as one in %s" name base (module_name other)
        | _ -> ());
        if Hashtbl.mem theories name && not (Hashtbl.mem module_of_theory name) then
          fail "the module %s has a theory `%s`, and so does this file" base name;
        let t = match Hashtbl.find_opt theories name with Some t -> t | None -> new_theory name in
        List.iter
          (fun d ->
            try ignore (process theories t d) with
            | Infer.Error m | Located (_, m) -> fail "module %s, line %d: %s" base d.line m)
          ds;
        Hashtbl.replace theories name t;
        Hashtbl.replace module_of_theory name file;
        name
      in
      let items = parse_file file in
      let tops = List.filter_map (function Top d -> Some d | Theory _ -> None) items in
      let names =
        List.filter_map (function Theory (n, ds) -> Some (add n ds) | Top _ -> None) items
        @ if tops = [] then [] else [ add base tops ]
      in
      Hashtbl.replace loaded_modules file names;
      names

(* Integrate differential equations numerically, with everything in base
   units, then show the result in each quantity's units. *)
and simulate _theories th sim =
  let t = sim.over in
  let tv = check_var th t in
  if not_scalar tv.attrs || tv.deps <> [] then fail "`%s` must be a plain scalar variable to integrate over" t;
  List.iter
    (fun x ->
      let xv = check_var th x in
      if not_scalar xv.attrs then fail "simulate the components of `%s`, declared as separate scalars" x;
      if xv.deps <> [ t ] then fail "`%s` must depend on %s alone: declare it as `var %s(%s) : ...`" x t x t)
    sim.unknowns;
  let laws = List.map (eval th []) sim.laws in
  let equations =
    List.concat_map
      (fun v ->
        let q = map_eq (prepare th) v.veq in
        match snd (check_eq th q) with
        | Shape.Scalar -> [ q ]
        | Shape.Vector n -> List.init n (fun i -> map_eq (fun e -> tidy (component th (i + 1) e)) q)
        | Shape.Matrix n ->
            List.concat (List.init n (fun i -> List.init n (fun j -> map_eq (fun e -> tidy (entry th (i + 1) (j + 1) e)) q))))
      laws
  in
  let numeric_eqs = List.map (fun q -> tidy (Sub (in_base_units th q.lhs, in_base_units th q.rhs))) equations in
  (* the unknowns, their orders, and nothing else unknown *)
  let orders =
    List.map
      (fun x ->
        let k = List.fold_left (fun acc e -> max acc (order_of t x e)) (-1) numeric_eqs in
        if k <= 0 then fail "`%s` is never differentiated by %s in these equations" x t;
        (x, k))
      sim.unknowns
  in
  (match List.filter (fun y -> not (List.mem y (t :: sim.unknowns))) (List.concat_map (free_vars th) numeric_eqs) with
  | [] -> ()
  | ys ->
      fail "give values for %s: put them in with `law[g := 9.81 [m/s^2]]`, or declare them with `const`"
        (String.concat ", " (List.map (fun y -> "`" ^ y ^ "`") (List.sort_uniq compare ys))));
  ignore (check_eq th { lhs = Var t; rhs = sim.t0 });
  ignore (check_eq th { lhs = Var t; rhs = sim.t1 });
  let t0 = base_number th sim.t0 and t1 = base_number th sim.t1 in
  if Q.leq (Q.of_string t1) (Q.of_string t0) then fail "the end, %s, must come after the start, %s" (Pretty.expr sim.t1) (Pretty.expr sim.t0);
  (* initial values: x(t0) = ... or at(diff(x, t), t, t0) = ... *)
  let rec diffs e = match e with Call ("diff", [ f; Var tt ]) when tt = t -> Option.map (fun (x, k) -> (x, k + 1)) (diffs f) | Var x -> Some (x, 0) | _ -> None in
  let start_of ic p =
    if not (Q.equal (Q.of_string (base_number th p)) (Q.of_string t0)) then
      fail "the initial value `%s` is not at the start, %s = %s" (Pretty.eq ic) t (Pretty.expr sim.t0)
  in
  let ics =
    List.map
      (fun ic ->
        ignore (check_eq th ic);
        let x, k =
          match ic.lhs with
          | Call (x, [ p ]) when List.mem x sim.unknowns -> start_of ic p; (x, 0)
          | Call ("at", [ d; Var tt; p ]) when tt = t -> (
              start_of ic p;
              match diffs d with
              | Some (x, k) when List.mem x sim.unknowns -> (x, k)
              | _ -> fail "`%s` is not the value of an unknown or of its derivatives" (Pretty.expr ic.lhs))
          | _ -> fail "an initial value looks like `x(0 [s]) = ...` or `at(diff(x, t), t, 0 [s]) = ...`, not `%s`" (Pretty.eq ic)
        in
        if k >= List.assoc x orders then
          fail "`%s` is not needed: %s appears differentiated at most %d time(s)" (Pretty.eq ic) x (List.assoc x orders);
        if k = 0 then check_bare th x ic.rhs (fun v -> Pretty.expr ic.lhs ^ " = " ^ v);
        (x, k, base_number th ic.rhs))
      sim.initial
  in
  let derivative x k = if k = 0 then sprintf "%s(%s)" x (Pretty.expr sim.t0) else sprintf "the %s derivative of %s at the start" (match k with 1 -> "first" | 2 -> "second" | _ -> string_of_int k ^ "th") x in
  List.iter
    (fun (x, n) ->
      for k = 0 to n - 1 do
        match List.filter (fun (y, j, _) -> y = x && j = k) ics with
        | [ _ ] -> ()
        | [] -> fail "an initial value is needed for %s" (derivative x k)
        | _ -> fail "%s is given more than once" (derivative x k)
      done)
    orders;
  let points = Option.value sim.points ~default:400 in
  if points < 2 || points > 5000 then fail "points must be between 2 and 5000";
  let r =
    Cas.simulate ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) numeric_eqs sim.unknowns t t0 t1 ics points
  in
  (* show each quantity in its unit: its declared one, or one picked for it *)
  let shown name (vi : var_info) values =
    let u, f = result_unit th vi.vdim ~asked:None ~declared:vi.vunit ~statement:"simulate" in
    let f = Q.to_float f.q *. (Float.pi ** float_of_int f.pi) in
    (name, u, vi.vdim, List.map (fun v -> v /. f) values)
  in
  let tname, tu, _, times = shown t tv r.times in
  {
    title = sim.sname;
    equations = List.map (fun v -> v.veq) laws;
    axis = (tname, tu, times);
    curves = List.map2 (fun x vs -> shown x (check_var th x) vs) sim.unknowns r.series;
    solver = r.method_;
  }

(* A free-body diagram: Newton's second law from its forces, and what to draw. *)
and diagram th name items =
  let pick what f = List.filter_map f items |> function
    | [ x ] -> Some x
    | [] -> None
    | _ -> fail "the diagram `%s` has more than one %s" name what
  in
  let body = match pick "body" (function Body m -> Some m | _ -> None) with Some m -> m | None -> fail "the diagram `%s` needs a `body m` line, with its mass" name in
  let draw = List.concat_map (function Draw bs -> bs | _ -> []) items in
  (* up, down, left, right, angle(θ), or any vector *)
  let direction e =
    let named = [ ("up", [ 0; 1 ]); ("down", [ 0; -1 ]); ("left", [ -1; 0 ]); ("right", [ 1; 0 ]) ] in
    let d =
      match e with
      | Var v when find_var th v = None && List.mem_assoc v named -> Call ("vec", List.map (fun k -> Num (Q.of_int k)) (List.assoc v named))
      | Call ("angle", [ a ]) -> Call ("vec", [ Call ("cos", [ a ]); Call ("sin", [ a ]) ])
      | _ -> e
    in
    (match Shape.infer (shape_env th) d with
    | Shape.V _ -> ()
    | _ -> fail "a direction is a vector, such as `up`, `angle(α)` or `vec(1, 1)`, but `%s` is not" (Pretty.expr e));
    let dd = Infer.check_eq (env th) { lhs = d; rhs = d } in
    if not (Dim.is_one dd) then fail "a direction has no dimension, but `%s` is [%s]" (Pretty.expr e) (Dim.to_string dd);
    (* a unit vector: divide by the length unless it simplifies to 1 *)
    let simplify e = match e with Num _ | Var _ -> e | _ -> tidy (Cas.simplify ~attrs_of:(attrs_of th) ~deps_of:(cas_deps th) e) in
    let n = simplify (prepare th (Call ("norm", [ d ]))) in
    let u = if n = Num Q.one then d else tidy (Div (d, n)) in
    (* each component simplified once: angle(α + pi/2) is (-sin α, cos α) *)
    match u with Call ("vec", xs) -> Call ("vec", List.map simplify xs) | _ -> u
  in
  let forces =
    List.filter_map
      (function
        | Force (n, m, d) ->
            let mag = match m with Some e -> e | None -> ignore (check_var th n); Var n in
            (match Shape.infer (shape_env th) mag with Shape.V _ -> fail "the size of force `%s` is a scalar; its direction goes after `toward`" n | _ -> ());
            Some (n, mag, direction d)
        | _ -> None)
      items
  in
  if forces = [] then fail "the diagram `%s` has no forces" name;
  (* every force has the dimension of the first *)
  let dim_of e = Infer.check_eq (env th) { lhs = e; rhs = e } in
  let n0, m0, _ = List.hd forces in
  List.iter
    (fun (n, m, _) ->
      if not (Dim.equal (dim_of m) (dim_of m0)) then
        fail "force `%s` is [%s], but force `%s` is [%s]" n (Dim.to_string (dim_of m)) n0 (Dim.to_string (dim_of m0)))
    forces;
  let accel = pick "acceleration" (function Accelerates (a, d) -> Some (a, Option.map direction d) | _ -> None) in
  let plane = pick "plane" (function Plane d -> Some (direction d) | _ -> None) in
  let sum = function [] -> Num Q.zero | x :: xs -> List.fold_left (fun a b -> Add (a, b)) x xs in
  let rhs = sum (List.map (fun (_, m, u) -> Mul (m, u)) forces) in
  let lhs =
    match accel with
    | None -> Num Q.zero
    | Some (a, Some u) -> Mul (body, Mul (a, u))
    | Some (a, None) -> Mul (body, a)
  in
  let law = { lhs = tidy lhs; rhs = tidy rhs } in
  let law_dim = check_eq th law in
  (* numbers for the picture: the drawing values and constants put in *)
  let missing = ref [] in
  let numbers u =
    match u with
    | Call ("vec", [ ux; uy ]) -> (
        let value e =
          let e = in_base_units th (subst_expr draw (prepare th e)) in
          match free_vars th e with
          | [] -> Some (float_of_string (Cas.evaluate ~digits:8 e))
          | xs -> missing := List.sort_uniq compare (!missing @ xs); None
        in
        match (value ux, value uy) with Some x, Some y -> Some (x, y) | _ -> None)
    | Call ("vec", _) -> None (* only flat diagrams are drawn *)
    | _ -> missing := List.sort_uniq compare (!missing @ [ "a direction written as a vector" ]); None
  in
  (* angle marks: each end is a force, the acceleration, the plane, or a direction *)
  let marks =
    List.filter_map (function Mark (l, a, b) -> Some (l, a, b) | _ -> None) items
    |> List.map (fun (label, a, b) ->
           let ends e =
             match e with
             | Var "plane" -> (match plane with Some u -> u | None -> fail "`mark ... plane ...` needs a `plane` line")
             | Var n when List.exists (fun (f, _, _) -> f = n) forces -> (fun (_, _, u) -> u) (List.find (fun (f, _, _) -> f = n) forces)
             | _ when (match accel with Some (Var x, Some _) -> e = Var x | _ -> false) -> Option.get (snd (Option.get accel))
             | _ -> direction e
           in
           let dl = Infer.check_eq (env th) { lhs = label; rhs = label } in
           if not (Dim.is_one dl) then fail "an angle has no dimension, but `%s` is [%s]" (Pretty.expr label) (Dim.to_string dl);
           let ua = numbers (ends a) and ub = numbers (ends b) in
           (* with the drawing values, the angle between the two must be the label's *)
           (match (ua, ub) with
           | Some (ax, ay), Some (bx, by) -> (
               let between = Float.acos (Float.max (-1.) (Float.min 1. ((ax *. bx) +. (ay *. by)))) in
               let lv = in_base_units th (subst_expr draw (prepare th label)) in
               match free_vars th lv with
               | [] ->
                   let v = Float.abs (float_of_string (Cas.evaluate ~digits:8 lv)) in
                   let v = Float.rem v (2. *. Float.pi) in
                   let v = if v > Float.pi then (2. *. Float.pi) -. v else v in
                   if Float.abs (v -. between) > 1e-6 then
                     fail "the angle between %s and %s is %.4g rad (%.1f°) with the drawing values, but `%s` is %.4g rad (%.1f°)"
                       (Pretty.expr a) (Pretty.expr b) between (between *. 180. /. Float.pi) (Pretty.expr label) v
                       (v *. 180. /. Float.pi)
               | _ -> ())
           | _ -> ());
           (* the slope's angle with the horizontal is drawn at its foot *)
           let horizontal e = List.mem e [ Var "left"; Var "right" ] in
           let foot = (a = Var "plane" && horizontal b) || (b = Var "plane" && horizontal a) in
           (label, ua, ub, foot))
  in
  {
    dname = name;
    law;
    law_dim;
    body;
    arrows = List.map (fun (n, m, u) -> (n, m, numbers u)) forces;
    accel = Option.map (fun (a, u) -> (a, Option.bind u numbers)) accel;
    plane = Option.bind plane numbers;
    missing = !missing;
    marks;
  }

(* Theories that come with Landau, such as SI, loaded on their first import. *)
and builtin theories n =
  match List.assoc_opt n Prelude.theories with
  | None -> None
  | Some source ->
      let items =
        try Parser.file Lexer.token (Lexing.from_string source)
        with _ -> failwith ("the built-in theory " ^ n ^ " does not parse")
      in
      List.iter
        (function
          | Theory (name, ds) ->
              let t = new_theory name in
              List.iter
                (fun d ->
                  try ignore (process theories t d)
                  with Infer.Error m -> failwith (sprintf "built-in theory %s, line %d: %s" name d.line m))
                ds;
              Hashtbl.replace theories name t
          | Top _ -> ())
        items;
      Hashtbl.find_opt theories n

(* An equation like 0 = 0 has every dimension: its dimension is a free variable. *)
let law_dim d = if Dim.vars d <> [] then "any" else Dim.to_string d

let dim_shape (d, s) = match s with Shape.Vector _ | Shape.Matrix _ -> Shape.to_string s ^ " " ^ law_dim d | Shape.Scalar -> law_dim d

(* A derivation that ends in x = x proves an identity. *)
let identity q = q.lhs = q.rhs

(* A scale factor for reading: 0.3048 and 1.602176634e-19 rather than the
   exact fractions they are stored as. *)
let number_string q =
  if Z.equal (Q.den q) Z.one && Q.lt (Q.abs q) (Q.of_int 1_000_000_000) then Q.to_string q
  else sprintf "%.10g" (Q.to_float q)

(* With pi exact: pi/180, 2*pi *)
let factor_parts f =
  let pis = if abs f.pi = 1 then "pi" else sprintf "pi^%d" (abs f.pi) in
  let n = Q.num f.q and d = Q.den f.q in
  let times a b = if Z.equal a Z.one then b else Z.to_string a ^ "*" ^ b in
  if f.pi > 0 then (times n pis, if Z.equal d Z.one then None else Some (Z.to_string d))
  else (Z.to_string n, Some (times d pis))

let factor_string f =
  if f.pi = 0 then number_string f.q
  else match factor_parts f with top, None -> top | top, Some bottom -> top ^ "/" ^ bottom

let factor_latex f =
  if f.pi = 0 then number_string f.q
  else
    (* the parts have only digits, pi, ^ and *: pi -> \pi, * -> a thin space *)
    let tex s =
      String.concat "" (List.map (function "*" -> "\\," | "p" -> "\\" ^ "p" | c -> c) (List.init (String.length s) (fun i -> String.make 1 s.[i])))
    in
    match factor_parts f with top, None -> tex top | top, Some bottom -> sprintf "\\frac{%s}{%s}" (tex top) (tex bottom)

let text_lines verbose = function
  | SImport n -> [ sprintf "  import %s" n ]
  | SDim ns ->
      [ sprintf "  dim %s"
          (String.concat ", " (List.map (fun (n, sym) -> match sym with Some s -> sprintf "%s (%s)" n s | None -> n) ns)) ]
  | SDiagram dg ->
      let dir = function Some (x, y) -> sprintf "(%.3g, %.3g)" x y | None -> "(not drawn)" in
      sprintf "  diagram %s : %s   [%s]" dg.dname (Pretty.eq dg.law) (dim_shape dg.law_dim)
      :: List.map (fun (n, m, d) -> sprintf "      force %s = %s toward %s" n (Pretty.expr m) (dir d)) dg.arrows
  | SEigen e ->
      sprintf "  eigen %s : %s%s" e.eigname (Pretty.expr e.ea) (match e.eb with Some b -> ", " ^ Pretty.expr b | None -> "")
      :: List.concat
           (List.mapi
              (fun i (l, m, vs) ->
                sprintf "      λ%d = %s   [%s]%s" (i + 1) (Pretty.expr l) (Dim.to_string e.ldim)
                  (if m > 1 then sprintf "   (%d times)" m else "")
                :: List.map (fun v -> sprintf "          v = %s" (Pretty.expr (Call ("vec", v)))) vs)
              e.pairs)
  | SGroups g ->
      sprintf "  groups %s : %s%s" g.gname
        (match g.target with Some t -> t ^ " from " | None -> "")
        (String.concat ", " g.gvars)
      :: List.mapi (fun i e -> sprintf "      Π%d = %s" (i + 1) (Pretty.expr e)) g.groups
      @ (if g.groups = [] then [ "      no dimensionless groups" ] else [])
      @ (match g.solved with
        | Some q -> [ sprintf "      %s%s" (Pretty.eq q) (if List.length g.groups = 1 then "   (C: a dimensionless constant)" else "") ]
        | None -> [])
      @ List.map
          (fun (x, d) -> sprintf "      %s cannot appear: no product of the others has its dimension [%s]" x (Dim.to_string d))
          g.absent
  | SSimulate s ->
      let tname, tu, times = s.axis in
      let last l = List.nth l (List.length l - 1) in
      let range l = (List.fold_left min infinity l, List.fold_left max neg_infinity l) in
      let unit u = if u = DOne then "" else " [" ^ Pretty.dexpr_to_string u ^ "]" in
      sprintf "  simulate %s: %s from %g to %g%s, %d points (%s)" s.title tname (List.hd times) (last times) (unit tu)
        (List.length times) s.solver
      :: List.map
           (fun (x, u, _, vs) ->
             let lo, hi = range vs in
             sprintf "      %s: starts at %.6g, ends at %.6g, between %.6g and %.6g%s" x (List.hd vs) (last vs) lo hi (unit u))
           s.curves
  | SCompute (name, e, value, d) ->
      [ sprintf "  compute %s%s = %s   [%s]"
          (match name with Some n -> n ^ " = " | None -> "")
          (Pretty.expr e) (Pretty.expr value) (Dim.to_string d) ]
  | SConst cs ->
      List.map
        (fun (n, q, u, d) -> sprintf "  const %s = %s   [%s]" n (Pretty.expr (Quantity (q, u))) (Dim.to_string d))
        cs
  | SUnits us ->
      [ sprintf "  unit %s"
          (String.concat ", "
             (List.map
                (fun (n, u) ->
                  if u.base then sprintf "%s : %s" n (Dim.to_string u.udim)
                  else if is_unscaled u.factor then sprintf "%s = [%s]" n (Dim.to_string u.udim)
                  else sprintf "%s = %s [%s]" n (factor_string u.factor) (Dim.to_string u.udim))
                us)) ]
  | SAlias (n, v) -> [ sprintf "  dim %s = %s" n (Dim.to_string v) ]
  | SVar (ns, vdim, attrs, vunit) ->
      let with_deps (n, ds) = if ds = [] then n else n ^ "(" ^ String.concat ", " ds ^ ")" in
      let ty = match vunit with Some u -> sprintf "%s   [%s]" (Pretty.dexpr_to_string u) (Dim.to_string vdim) | None -> Dim.to_string vdim in
      [ sprintf "  var %s : %s%s" (String.concat ", " (List.map with_deps ns)) ty
          (String.concat "" (List.map (fun a -> ", " ^ a) attrs)) ]
  | SDef (n, _, _, scheme, shapes) ->
      [ sprintf "  def %s : %s" n (Infer.scheme_to_string scheme) ]
      @ Option.fold ~none:[] ~some:(fun t -> [ "      shapes  " ^ Shape.table_to_string t ]) shapes
  | SLaw (n, q, dq) -> [ sprintf "  law %s : %s   [%s]" n (Pretty.eq q) (dim_shape dq) ]
  | SDerive (n, v, dq, trace) ->
      [ sprintf "  derive %s : %s   [%s]%s" n (Pretty.eq v.veq) (dim_shape dq)
          (if identity v.veq then "   (holds identically)" else "");
        sprintf "      from    %s" (String.concat ", " v.vuses) ]
      @ (if v.vassumes <> [] then [ sprintf "      assumes %s" (String.concat ", " v.vassumes) ] else [])
      @ (if v.vconsts <> [] then
           [ sprintf "      constants %s"
               (String.concat ", " (List.map (fun (n, d) -> sprintf "%s [%s]" n (Dim.to_string d)) v.vconsts)) ]
         else [])
      @ [ sprintf "      via     %s" (String.concat ", " (List.map (fun ((st : step), _) -> describe st.body) trace)) ]
      @
      if verbose then
        List.map
          (fun ((st : step), v) ->
            sprintf "        %s%s" (match st.name with Some n -> n ^ " := " | None -> "") (Pretty.eq v.veq))
          trace
      else []

(* ---- JSON report, for the web frontend ---- *)

let jstr s = `String s
let jlist f l = `List (List.map f l)
(* both LaTeX forms, so the app can switch between L/T and L T^{-1} *)
(* Both LaTeX forms, so the app can switch between L/T and L T^{-1}, and the
   same in units when they are known: the given ones (a variable's declared
   unit) or the ones picked by auto_units. *)
let jdim th ?units d =
  (* declared units keep the order they were written in *)
  let order = Option.map Pretty.unit_names units in
  let units = match units with Some u -> Some (Pretty.unit_vector u) | None -> auto_units th d in
  `Assoc
    ([ ("text", jstr (Dim.to_string d)); ("latex", jstr (Dim.to_latex d)); ("powers", jstr (Dim.to_latex ~powers:true d)) ]
    @
    match units with
    | Some u ->
        [ ("units_text", jstr (Dim.to_string ?order u)); ("units", jstr (Dim.to_latex ~roman:true ?order u));
          ("units_powers", jstr (Dim.to_latex ~roman:true ~powers:true ?order u)) ]
    | None -> [])
let jshape s = jstr (Shape.to_string s)

let jlaw_dim th ?units d =
  if Dim.vars d <> [] then `Assoc [ ("text", jstr "any"); ("latex", jstr "\\text{any}"); ("powers", jstr "\\text{any}") ]
  else jdim th ?units d

let jscheme th (sc : Infer.scheme) =
  `Assoc
    [ ("text", jstr (Infer.scheme_to_string sc));
      ("params", jlist (jdim th) sc.params);
      ("result", jdim th sc.result) ]

let shown_json th line sh : Yojson.Safe.t =
  (* a law x = ... is shown in the unit x was declared with: torque in N*m, not J *)
  let lhs_units q =
    match q with
    | { rhs = Quantity (_, u); _ } when u <> DOne -> Some u (* an evaluated result, in the unit it was given in *)
    | { lhs = Var x; _ } -> Option.bind (find_var th x) (fun v -> v.vunit)
    | _ -> None
  in
  let vec = is_vector th in
  let jeq q = `Assoc [ ("text", jstr (Pretty.eq q)); ("latex", jstr (Pretty.latex_eq ~vec q)) ] in
  let jexpr ?(vec = vec) e = `Assoc [ ("text", jstr (Pretty.expr e)); ("latex", jstr (Pretty.latex ~vec e)) ] in
  let item kind fields = `Assoc ([ ("kind", jstr kind); ("line", `Int line) ] @ fields) in
  match sh with
  | SImport n -> item "import" [ ("name", jstr n) ]
  | SDim ns ->
      item "dim"
        [ ("names", jlist (fun (n, _) -> jstr n) ns);
          ("symbols", jlist (fun (n, s) -> jstr (Option.value s ~default:n)) ns) ]
  | SAlias (n, v) -> item "alias" [ ("name", jstr n); ("dim", jdim th v) ]
  | SDiagram dg ->
      let dir = function Some (x, y) -> `List [ `Float x; `Float y ] | None -> `Null in
      let r e = `Assoc [ ("text", jstr (Pretty.expr e)); ("latex", jstr (Pretty.latex ~vec e)) ] in
      item "diagram"
        [ ("name", jstr dg.dname); ("eq", `Assoc [ ("text", jstr (Pretty.eq dg.law)); ("latex", jstr (Pretty.latex_eq ~vec dg.law)) ]);
          ("dim", jlaw_dim th (fst dg.law_dim)); ("shape", jshape (snd dg.law_dim)); ("body", r dg.body);
          ( "forces",
            jlist (fun (n, m, d) -> `Assoc [ ("name", jstr n); ("symbol", jstr (Pretty.name n)); ("magnitude", r m); ("dir", dir d) ]) dg.arrows );
          ("acceleration", match dg.accel with Some (a, d) -> `Assoc [ ("magnitude", r a); ("dir", dir d) ] | None -> `Null);
          ("plane", dir dg.plane); ("missing", jlist jstr dg.missing);
          ( "marks",
            jlist
              (fun (l, a, b, foot) ->
                `Assoc [ ("label", r l); ("from", dir a); ("to", dir b); ("at", jstr (if foot then "foot" else "center")) ])
              dg.marks ) ]
  | SEigen e ->
      let r e = `Assoc [ ("text", jstr (Pretty.expr e)); ("latex", jstr (Pretty.latex ~vec e)) ] in
      item "eigen"
        [ ("name", jstr e.eigname); ("a", r e.ea); ("b", match e.eb with Some b -> r b | None -> `Null);
          ("dim", jdim th e.ldim);
          ( "values",
            jlist
              (fun (l, m, vs) ->
                `Assoc [ ("value", r l); ("multiplicity", `Int m); ("vectors", jlist (fun v -> r (Call ("vec", v))) vs) ])
              e.pairs ) ]
  | SGroups g ->
      let r e = `Assoc [ ("text", jstr (Pretty.expr e)); ("latex", jstr (Pretty.latex ~vec e)) ] in
      let named x = `Assoc [ ("name", jstr x); ("symbol", jstr (Pretty.name x)) ] in
      item "groups"
        [ ("name", jstr g.gname);
          ("target", match g.target with Some t -> named t | None -> `Null);
          ("vars", jlist named g.gvars);
          ("groups", jlist r g.groups);
          ("solved", match g.solved with Some q -> jeq q | None -> `Null);
          ("absent", jlist (fun (x, d) -> `Assoc [ ("name", jstr x); ("symbol", jstr (Pretty.name x)); ("dim", jdim th d) ]) g.absent) ]
  | SSimulate sm ->
      (* NaN and infinities are not JSON *)
      let num f = if Float.is_finite f then `Float f else `Null in
      let unit u = `Assoc [ ("text", jstr (Pretty.dexpr_to_string u)); ("latex", jstr (if u = DOne then "" else Pretty.unit_latex u)) ] in
      let tname, tu, times = sm.axis in
      item "simulate"
        [ ("name", jstr sm.title); ("solver", jstr sm.solver);
          ("equations", jlist (fun q -> jstr (Pretty.latex_eq ~vec q)) sm.equations);
          ("t", `Assoc [ ("name", jstr tname); ("symbol", jstr (Pretty.name tname)); ("unit", unit tu); ("values", jlist num times) ]);
          ( "series",
            jlist
              (fun (x, u, d, vs) ->
                `Assoc
                  [ ("name", jstr x); ("symbol", jstr (Pretty.name x)); ("unit", unit u); ("dim", jstr (Dim.to_string d));
                    ("values", jlist num vs) ])
              sm.curves ) ]
  | SCompute (name, e, value, d) ->
      let r e = `Assoc [ ("text", jstr (Pretty.expr e)); ("latex", jstr (Pretty.latex ~vec e)) ] in
      item "compute"
        ([ ("expr", r e); ("value", r value);
           ("dim", jdim th ?units:(match value with Quantity (_, u) when u <> DOne -> Some u | _ -> None) d) ]
        @ match name with Some n -> [ ("name", jstr n); ("symbol", jstr (Pretty.name n)) ] | None -> [])
  | SConst cs ->
      item "const"
        [ ( "consts",
            jlist
              (fun (n, q, u, d) ->
                `Assoc
                  [ ("name", jstr n); ("symbol", jstr (Pretty.name n));
                    ("dim", jdim th ?units:(if u = DOne then None else Some u) d);
                    ("value", `Assoc [ ("text", jstr (Pretty.expr (Quantity (q, u)))); ("latex", jstr (Pretty.latex (Quantity (q, u)))) ]) ])
              cs ) ]
  | SUnits us ->
      item "units"
        [ ( "units",
            jlist
              (fun (n, u) ->
                `Assoc
                  [ ("name", jstr n); ("latex", jstr (Dim.to_latex ~roman:true (Dim.base n))); ("dim", jdim th u.udim);
                    ("factor", jstr (factor_string u.factor)); ("factor_latex", jstr (factor_latex u.factor));
                    ("base", `Bool u.base) ])
              us ) ]
  | SVar (ns, d, attrs, vunit) ->
      let vec = is_vector_attrs attrs in
      (* x(t) shows its arguments: E(r, t) *)
      let symbol (n, ds) =
        Pretty.name ~vec n
        ^ if ds = [] then "" else "(" ^ String.concat ", " (List.map (fun d -> Pretty.name ~vec:(is_vector th d) d) ds) ^ ")"
      in
      item "var"
        [ ("names", jlist (fun (n, _) -> jstr n) ns); ("symbols", jlist (fun v -> jstr (symbol v)) ns);
          ("dim", jdim th ?units:vunit d);
          ("deps", jlist (fun (_, ds) -> jlist jstr ds) ns);
          ("attrs", jlist jstr attrs); ("shape", jshape (shape_of_attrs attrs)) ]
  | SDef (n, ps, body, sc, shapes) ->
      (* parameters shadow variables of the same name, and their shape varies *)
      let vec x = (not (List.mem x ps)) && vec x in
      item "def"
        ([ ("name", jstr n); ("params", jlist jstr ps); ("body", jexpr ~vec body); ("scheme", jscheme th sc);
           ("latex", jstr (Pretty.fn_name n ^ Pretty.call_args (List.map (fun p -> Pretty.name p) ps))) ]
        @ Option.fold ~none:[] ~some:(fun t -> [ ("shapes", jstr (Shape.table_to_string t)) ]) shapes)
  | SLaw (n, q, (d, s)) -> item "law" [ ("name", jstr n); ("eq", jeq q); ("dim", jlaw_dim th ?units:(lhs_units q) d); ("shape", jshape s) ]
  | SDerive (n, v, (d, s), trace) ->
      let step ((st : step), v) =
        `Assoc
          [ ("name", match st.name with Some n -> jstr n | None -> `Null);
            ("op", jstr (describe st.body));
            ("line", `Int st.sline);
            ("eq", jeq v.veq) ]
      in
      item "derive"
        [ ("name", jstr n); ("eq", jeq v.veq); ("dim", jlaw_dim th ?units:(lhs_units v.veq) d); ("shape", jshape s);
          ("identity", `Bool (identity v.veq)); ("uses", jlist jstr v.vuses);
          ("assumes", jlist jstr v.vassumes);
          ("constants", jlist (fun (n, d) -> `Assoc [ ("name", jstr n); ("latex", jstr (Pretty.name n)); ("dim", jdim th d) ]) v.vconsts);
          ("steps", jlist step trace) ]

(* ---- files ---- *)

type reporter = {
  theory_start : string -> unit;
  theory_end : unit -> unit;
  item : theory -> int -> shown -> unit;
  error : theory option -> int -> int option -> string -> unit;
}

let check_items rep items =
  let theories = Hashtbl.create 8 in
  let run th d =
    (Pretty.vector_size := fun v -> vector_size (attrs_of th v));
    (Pretty.deps_of := fun v -> deps_of th v);
    (Pretty.is_vector_expr := fun e -> match shape th e with Shape.V _ -> true | _ -> false);
    (Pretty.is_matrix := fun v -> is_matrix_attrs (attrs_of th v));
    (Pretty.is_time :=
       fun v ->
         match Option.map (fun i -> Dim.K.bindings i.vdim) (find_var th v) with
         | Some [ (Dim.Base b, q) ] -> Q.equal q Q.one && Dim.display b = "T"
         | _ -> false);
    (Pretty.independent :=
       fun v ->
         Option.fold ~none:false ~some:(fun (p, _) -> p = v) (position th)
         || List.exists (fun (_, e) -> List.mem v e.v.deps) th.vars);
    try rep.item th d.line (process theories th d) with
    | Infer.Error m -> rep.error (Some th) d.line None m
    | Located (l, m) -> rep.error (Some th) l None m
    | (Stack_overflow | Out_of_memory) as e -> raise e
    | e -> rep.error (Some th) d.line None ("internal error: " ^ Printexc.to_string e)
  in
  let main = ref None in
  List.iter
    (function
      | Theory (n, ds) ->
          rep.theory_start n;
          let th = new_theory n in
          List.iter (run th) ds;
          (match Hashtbl.find_opt module_of_theory n with
          | Some f ->
              rep.error (Some th) (match ds with d :: _ -> d.line | [] -> 1) None
                (sprintf "the theory `%s` is also defined in the imported module %s; rename one of them" n (module_name f))
          | None -> Hashtbl.replace theories n th);
          rep.theory_end ()
      | Top d ->
          let th =
            match !main with
            | Some t -> t
            | None ->
                let t = new_theory "Main" in
                main := Some t;
                Hashtbl.replace theories "Main" t;
                t
          in
          run th d)
    items

let parse lexbuf =
  try Ok (Parser.file Lexer.token lexbuf) with
  | Lexer.Error m -> Error m
  | Parser.Error -> Error "syntax error"
  | Syntax_error m -> Error m

(* Before checking a file: where its modules are, and a fresh start. *)
let setup_modules file =
  let home = Filename.concat (Cas.home ()) "modules" in
  let file = match (file, !stdin_as) with "-", Some f -> f | _ -> file in
  let own = if file = "-" then [] else [ Filename.dirname file ] in
  (* the same directory may be named in several ways: compare real paths *)
  let real = !realpath_hook in
  module_path :=
    List.fold_left (fun acc d -> if List.mem (real d) acc then acc else acc @ [ real d ]) [] (own @ !extra_module_dirs @ [ home ]);
  current_file := (if file = "-" then None else Some file);
  Hashtbl.reset loaded_modules;
  Hashtbl.reset module_of_theory;
  loading := [];
  (* in the browser one process checks file after file *)
  Dim.order := [];
  Hashtbl.reset Dim.symbols

(* [source] is the text of the file, when it does not come from disk *)
let with_source ?source file k =
  setup_modules file;
  let ic = if source <> None then None else Some (if file = "-" then stdin else open_in_bin file) in
  let lexbuf =
    match (source, ic) with Some s, _ -> Lexing.from_string s | None, Some ic -> Lexing.from_channel ic | None, None -> assert false
  in
  Lexing.set_filename lexbuf file;
  let parsed = parse lexbuf in
  if file <> "-" then Option.iter close_in ic;
  k lexbuf parsed

let run_file ~verbose file =
  with_source file @@ fun lexbuf parsed ->
  match parsed with
  | Error m ->
      let p = lexbuf.lex_start_p in
      eprintf "%s:%d:%d: %s\n%!" file p.pos_lnum (p.pos_cnum - p.pos_bol) m;
      false
  | Ok items ->
      let ok = ref true in
      check_items
        {
          theory_start = (fun n -> printf "theory %s\n%!" n);
          theory_end = print_newline;
          item = (fun _ _ sh -> List.iter print_endline (text_lines verbose sh); flush stdout);
          error =
            (fun _ line _ m ->
              flush stdout;
              eprintf "%s:%d: error: %s\n%!" file line m;
              ok := false);
        }
        items;
      !ok

(* The whole report as one JSON object (run_file_json prints it):
   { "ok", "errors": [{line, col, message, theory}], "theories": [{name, items}] }
   Errors also appear among their theory's items, in source order. *)
let json_report ?source file =
  with_source ?source file @@ fun lexbuf parsed ->
  let errors = ref [] and theories = ref [] in
  let add_item th it =
    match List.assoc_opt th !theories with
    | Some l -> l := it :: !l
    | None -> theories := !theories @ [ (th, ref [ it ]) ]
  in
  let error th line col m =
    let j =
      `Assoc
        [ ("kind", jstr "error"); ("line", `Int line); ("col", match col with Some c -> `Int c | None -> `Null);
          ("message", jstr m); ("theory", match th with Some t -> jstr t.tname | None -> `Null) ]
    in
    errors := j :: !errors;
    Option.iter (fun t -> add_item t.tname j) th
  in
  (match parsed with
  | Error m ->
      let p = lexbuf.lex_start_p in
      error None p.pos_lnum (Some (p.pos_cnum - p.pos_bol)) m
  | Ok items ->
      check_items
        {
          theory_start = (fun n -> if not (List.mem_assoc n !theories) then theories := !theories @ [ (n, ref []) ]);
          theory_end = ignore;
          item = (fun th line sh -> add_item th.tname (shown_json th line sh));
          error;
        }
        items);
  let report =
    `Assoc
      [ ("ok", `Bool (!errors = []));
        ("errors", `List (List.rev !errors));
        ( "theories",
          jlist (fun (n, l) -> `Assoc [ ("name", jstr n); ("items", `List (List.rev !l)) ]) !theories ) ]
  in
  report

let run_file_json file =
  let report = json_report file in
  print_endline (Yojson.Safe.to_string report);
  match report with `Assoc (("ok", `Bool ok) :: _) -> ok | _ -> false
