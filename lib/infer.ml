(* Dimension inference.

   Every operator imposes a linear constraint on exponent vectors:
   x*y adds them, x/y subtracts, x^q scales by q, and x + y requires
   them to be equal. Unknown dimensions are variables, and [unify]
   solves the constraints one at a time by Gaussian elimination over Q. *)

open Syntax
open Printf

exception Error of string

module IM = Map.Make (Int)

(* [sub] maps solved variables to dimensions over unsolved ones only. *)
type state = { mutable next : int; mutable sub : Dim.t IM.t }

let create () = { next = 0; sub = IM.empty }

let fresh st =
  let v = st.next in
  st.next <- v + 1;
  Dim.var v

let apply st d =
  Dim.map_vars (fun v -> match IM.find_opt v st.sub with Some s -> s | None -> Dim.var v) d

(* Require [d1 = d2]; on failure, [err] builds the message. *)
let unify st d1 d2 err =
  let d = apply st (Dim.sub d1 d2) in
  match Dim.vars d with
  | [] -> if not (Dim.is_one d) then raise (Error (err (apply st d1) (apply st d2)))
  | v :: _ ->
      (* c*v + rest = 0, so v = -rest/c *)
      let c = Dim.coeff (Dim.Var v) d in
      let s = Dim.scale (Q.neg (Q.inv c)) (Dim.remove_var v d) in
      st.sub <- IM.add v s (IM.map (Dim.subst v s) st.sub)

(* A polymorphic dimension signature: variables are 0 .. nvars-1. *)
type scheme = { nvars : int; params : Dim.t list; result : Dim.t }

type env = {
  global : string -> Dim.t option;
  scheme_of : string -> scheme option;
  locals : (string * Dim.t) list;
  position : Dim.t option; (* the dimension grad, div, curl and lap differentiate by *)
  deps : string -> string list; (* x(t) depends on t: x(0) evaluates it *)
  unit_dim : dexpr -> Dim.t; (* the dimension of a unit, for quantities like 9.81 [m/s^2] *)
}

let instantiate st sc =
  let m = Array.init sc.nvars (fun _ -> fresh st) in
  let f = Dim.map_vars (fun v -> m.(v)) in
  (List.map f sc.params, f sc.result)

(* Rename the free variables to 0, 1, ... in order of appearance. *)
let generalize params result =
  let seen = ref [] in
  let note d = List.iter (fun v -> if not (List.mem v !seen) then seen := !seen @ [ v ]) (Dim.vars d) in
  List.iter note params;
  note result;
  let idx v =
    let rec go i = function [] -> assert false | x :: r -> if x = v then i else go (i + 1) r in
    go 0 !seen
  in
  let f = Dim.map_vars (fun v -> Dim.var (idx v)) in
  { nvars = List.length !seen; params = List.map f params; result = f result }

(* Value of a constant exponent like 2, -1, 3/2. *)
let rec const_q = function
  | Num q -> Some q
  | Neg a -> Option.map Q.neg (const_q a)
  | Add (a, b) -> lift Q.add a b
  | Sub (a, b) -> lift Q.sub a b
  | Mul (a, b) -> lift Q.mul a b
  | Div (a, b) -> (
      match (const_q a, const_q b) with
      | Some x, Some y when Q.sign y <> 0 -> Some (Q.div x y)
      | _ -> None)
  | _ -> None

and lift f a b = match (const_q a, const_q b) with Some x, Some y -> Some (f x y) | _ -> None

let dimensionless_fns =
  [ "sin"; "cos"; "tan"; "asin"; "acos"; "atan"; "sinh"; "cosh"; "tanh"; "exp"; "log" ]

(* Every built-in function; definitions cannot reuse these names. *)
let builtins =
  dimensionless_fns @ [ "sqrt"; "abs"; "conj"; "atan2"; "dot"; "cross"; "norm"; "grad"; "div"; "curl"; "lap"; "diff"; "vec"; "comp"; "integral"; "at"; "line"; "loop"; "surface"; "volume" ]

let show = Pretty.expr
let ds = Dim.to_string
let ds_ = ds

let rec infer st env e =
  match e with
  (* 0 and inf are the only literals with every dimension *)
  | Num q -> if Q.equal q Q.zero then fresh st else Dim.one
  | Const "inf" -> fresh st
  | Quantity (_, u) -> env.unit_dim u
  | Const _ -> Dim.one
  | Var x -> (
      match List.assoc_opt x env.locals with
      | Some d -> d
      | None -> (
          match env.global x with
          | Some d -> d
          | None -> raise (Error (sprintf "unknown variable `%s`" x))))
  | Neg a -> infer st env a
  | Add (a, b) | Sub (a, b) ->
      let da = infer st env a in
      let db = infer st env b in
      let verb = match e with Add _ -> "add" | _ -> "subtract" in
      unify st da db (fun da db ->
          sprintf "cannot %s `%s` [%s] and `%s` [%s]" verb (show a) (ds da) (show b) (ds db));
      apply st da
  | Mul (a, b) ->
      let da = infer st env a in
      Dim.add da (infer st env b)
  | Div (a, b) ->
      let da = infer st env a in
      Dim.sub da (infer st env b)
  | Pow (a, b) -> (
      let da = infer st env a in
      let db = infer st env b in
      unify st db Dim.one (fun db _ ->
          sprintf "the exponent `%s` must be dimensionless, but it is [%s]" (show b) (ds db));
      match const_q b with
      | Some q -> Dim.scale q da
      | None ->
          unify st da Dim.one (fun da _ ->
              sprintf "`%s` is raised to the symbolic power `%s`, so it must be dimensionless, but it is [%s]"
                (show a) (show b) (ds da));
          Dim.one)
  | Call (f, args) -> infer_call st env f args

and infer_call st env f args =
  let dims = List.map (infer st env) args in
  let arity n =
    if List.length args <> n then
      raise (Error (sprintf "`%s` takes %d argument(s), but got %d" f n (List.length args)))
  in
  let same a da b db =
    unify st da db (fun da db ->
        sprintf "the arguments of `%s` must have the same dimension, but `%s` is [%s] and `%s` is [%s]" f
          (show a) (ds da) (show b) (ds db))
  in
  if List.mem f dimensionless_fns then (
    arity 1;
    unify st (List.hd dims) Dim.one (fun d _ ->
        sprintf "the argument of `%s` must be dimensionless, but `%s` is [%s]" f (show (List.hd args)) (ds d));
    Dim.one)
  else
    match (f, args, dims) with
    | "sqrt", _, _ ->
        arity 1;
        Dim.scale (Q.of_ints 1 2) (List.hd dims)
    | ("abs" | "conj"), _, _ ->
        arity 1;
        List.hd dims
    | "atan2", [ a; b ], [ da; db ] ->
        same a da b db;
        Dim.one
    | "atan2", _, _ ->
        arity 2;
        Dim.one
    | ("dot" | "cross"), _, _ ->
        arity 2;
        Dim.add (List.hd dims) (List.nth dims 1)
    | "norm", _, _ ->
        arity 1;
        List.hd dims
    | ("grad" | "div" | "curl" | "lap"), _, _ -> (
        arity 1;
        match env.position with
        | None -> raise (Error (sprintf "`%s` needs a position vector: declare one with `var r : L, position`" f))
        | Some p -> Dim.sub (List.hd dims) (Dim.scale (Q.of_int (if f = "lap" then 2 else 1)) p))
    | "diff", _, _ ->
        arity 2;
        Dim.sub (List.hd dims) (List.nth dims 1)
    | "comp", _, _ ->
        arity 2;
        List.hd dims
    | "integral", _, _ -> (
        (* integral(f, x) and integral(f, x, a, b) have the dimension of f*x *)
        let bound b db dx =
          unify st db dx (fun db dx ->
              sprintf "the bound `%s` of `integral` is [%s], but the variable is [%s]" (show b) (ds_ db) (ds_ dx))
        in
        match (args, dims) with
        | [ _; _ ], [ df; dx ] -> Dim.add df dx
        | [ _; _; a; b ], [ df; dx; da; db ] ->
            bound a da dx;
            bound b db dx;
            Dim.add df dx
        | _ -> raise (Error (sprintf "`integral` takes 2 arguments (f, x) or 4 (f, x, a, b), but got %d" (List.length args))))
    | ("line" | "loop" | "surface" | "volume"), _, _ -> (
        (* line(F, p, s, a, b), surface(F, q, u, u1, u2, w, w1, w2) and
           volume(f, q, u, u1, u2, v, v1, v2, w, w1, w2): the integrand times
           a length, an area or a volume of the region q, which lies in space *)
        let n = match f with "line" | "loop" -> 1 | "surface" -> 2 | _ -> 3 in
        arity (2 + (3 * n));
        let p =
          match env.position with
          | Some p -> p
          | None -> raise (Error (sprintf "`%s` needs a position vector: declare one with `var r : L, position`" f))
        in
        let dq = List.nth dims 1 in
        unify st dq p (fun dq p ->
            sprintf "the region `%s` of `%s` must be made of positions [%s], but it is [%s]" (show (List.nth args 1)) f
              (ds_ p) (ds_ dq));
        for i = 0 to n - 1 do
          let k = 2 + (3 * i) in
          let dv = List.nth dims k in
          List.iter
            (fun j ->
              unify st (List.nth dims j) dv (fun db dv ->
                  sprintf "the bound `%s` of `%s` is [%s], but the parameter `%s` is [%s]" (show (List.nth args j)) f
                    (ds_ db) (show (List.nth args k)) (ds_ dv)))
            [ k + 1; k + 2 ]
        done;
        (* the parameters' own dimensions cancel against the derivatives dq/du *)
        Dim.add (List.hd dims) (Dim.scale (Q.of_int n) p))
    | "at", _, _ -> (
        (* at(e, x, a): e with x set to a *)
        arity 3;
        match (args, dims) with
        | [ _; _; a ], [ de; dx; da ] ->
            unify st da dx (fun da dx ->
                sprintf "`%s` is [%s], but it is put in place of a variable that is [%s]" (show a) (ds_ da) (ds_ dx));
            de
        | _ -> Dim.one)
    | _ when env.global f <> None && env.deps f <> [] ->
        (* x(0): the variable x evaluated where its dependencies take these values *)
        let ds = env.deps f in
        arity (List.length ds);
        List.iter2
          (fun (a, da) d ->
            let dd = Option.get (env.global d) in
            unify st da dd (fun da dd ->
                sprintf "in `%s`, `%s` is [%s] but stands for `%s`, which is [%s]" (show (Call (f, args))) (show a)
                  (ds_ da) d (ds_ dd)))
          (List.combine args dims) ds;
        Option.get (env.global f)
    | "vec", a :: rest, d :: ds ->
        (* all components of a vector share one dimension *)
        List.iter2
          (fun b db ->
            unify st d db (fun d db ->
                sprintf "the components of a vector must have the same dimension, but `%s` is [%s] and `%s` is [%s]"
                  (show a) (ds_ d) (show b) (ds_ db)))
          rest ds;
        apply st d
    | _ -> (
        match env.scheme_of f with
        | None -> raise (Error (sprintf "unknown function `%s`" f))
        | Some sc ->
            let ps, r = instantiate st sc in
            arity (List.length ps);
            List.iter2
              (fun (a, d) p ->
                unify st d p (fun d p ->
                    sprintf "the argument `%s` of `%s` is [%s], but `%s` expects [%s] there" (show a) f
                      (ds d) f (ds p)))
              (List.combine args dims) ps;
            apply st r)

(* Infer the polymorphic signature of a definition. *)
let infer_def env params body =
  let st = create () in
  let ps = List.map (fun (p, ann) -> (p, match ann with Some d -> d | None -> fresh st)) params in
  let r = infer st { env with locals = ps } body in
  generalize (List.map (fun (_, d) -> apply st d) ps) (apply st r)

(* Check that both sides of an equation have the same dimension and return it. *)
let check_eq env q =
  let st = create () in
  let dl = infer st env q.lhs in
  let dr = infer st env q.rhs in
  unify st dl dr (fun dl dr ->
      sprintf "the two sides have different dimensions: `%s` is [%s] but `%s` is [%s]" (show q.lhs) (ds dl)
        (show q.rhs) (ds dr));
  (generalize [] (apply st dl)).result

let scheme_to_string sc =
  sprintf "(%s) -> %s" (String.concat ", " (List.map Dim.to_string sc.params)) (Dim.to_string sc.result)
