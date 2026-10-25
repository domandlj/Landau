(* Client for the SymPy worker (cas/worker.py).

   Expressions travel as JSON trees, one request per line. Variables are
   renamed to s0, s1, ... so that any Landau name (θ, v0, x') is safe on
   the Python side, and their assumptions (real, positive, nonzero) are
   sent along so SymPy can simplify accordingly. *)

open Syntax
open Printf

let fail fmt = ksprintf (fun s -> raise (Infer.Error s)) fmt

let home () =
  match Sys.getenv_opt "LANDAU_HOME" with
  | Some h -> h
  | None ->
      (* Skip _build/default: dune copies cas/worker.py there only for the
         tests, so between test runs that copy is out of date. *)
      let in_build d = Filename.basename (Filename.dirname d) = "_build" in
      let rec up d n =
        if n = 0 then Sys.getcwd ()
        else if Sys.file_exists (Filename.concat d "cas/worker.py") && not (in_build d) then d
        else up (Filename.dirname d) (n - 1)
      in
      up (Filename.dirname Sys.executable_name) 8

(* The .venv next to Landau, or in a directory above it: a build copies
   cas/worker.py into _build/default, but the .venv stays at the top. *)
let python home =
  match Sys.getenv_opt "LANDAU_PYTHON" with
  | Some p -> p
  | None ->
      let rec up d n =
        let venv = Filename.concat d ".venv/bin/python" in
        if Sys.file_exists venv then venv
        else if n = 0 || Filename.dirname d = d then "python3"
        else up (Filename.dirname d) (n - 1)
      in
      up home 4

let worker = ref None

let channels () =
  match !worker with
  | Some w -> w
  | None ->
      let h = home () in
      let py = python h in
      (* Python orders sets differently in every process unless the hash
         seed is fixed, and SymPy's results can follow that order: fix it, so
         the same file always gives the same output *)
      Unix.putenv "PYTHONHASHSEED" "0";
      let w = Unix.open_process_args py [| py; Filename.concat h "cas/worker.py" |] in
      worker := Some w;
      w

(* Another way to reach the worker: in the browser there is no process to
   start, and a request line goes to cas/worker.py running in Pyodide. *)
let transport : (string -> string) option ref = ref None

let request (req : Yojson.Safe.t) =
  let line =
    match !transport with
    | Some send -> send (Yojson.Safe.to_string req)
    | None -> (
        let ic, oc = channels () in
        output_string oc (Yojson.Safe.to_string req);
        output_char oc '\n';
        flush oc;
        try input_line ic
        with End_of_file -> fail "the SymPy worker stopped (is SymPy installed? set LANDAU_PYTHON)")
  in
  match Yojson.Safe.from_string line with
  | `Assoc [ ("ok", `List xs) ] -> xs
  | `Assoc [ ("error", `String m) ] -> fail "SymPy: %s" m
  | _ -> fail "unexpected reply from the SymPy worker: %s" line

(* ---- Landau -> JSON ---- *)

let num q = `Assoc [ ("num", `String (Q.to_string q)) ]

(* [sym x] is the SymPy name of variable x; [is_var f] says whether a call
   f(...) is a variable evaluated at a point, like x(0). *)
let rec to_json ?(is_var = fun _ -> false) sym e : Yojson.Safe.t =
  let t = to_json ~is_var sym in
  match e with
  | Num q -> num q
  | Var x -> `Assoc [ ("sym", `String (sym x)) ]
  | Const "pi" -> `Assoc [ ("const", `String "pi") ]
  | Const "inf" -> `Assoc [ ("const", `String "oo") ]
  | Const _ -> `Assoc [ ("const", `String "I") ]
  | Neg a -> `Assoc [ ("mul", `List [ num Q.minus_one; t a ]) ]
  | Add (a, b) -> `Assoc [ ("add", `List [ t a; t b ]) ]
  | Sub (a, b) -> `Assoc [ ("add", `List [ t a; `Assoc [ ("mul", `List [ num Q.minus_one; t b ]) ] ]) ]
  | Mul (a, b) -> `Assoc [ ("mul", `List [ t a; t b ]) ]
  | Div (a, b) -> `Assoc [ ("mul", `List [ t a; `Assoc [ ("pow", `List [ t b; num Q.minus_one ]) ] ]) ]
  | Pow (a, b) -> `Assoc [ ("pow", `List [ t a; t b ]) ]
  | Quantity _ -> fail "internal error: a quantity reached SymPy without being hidden"
  | Call (f, args) when is_var f -> `Assoc [ ("eval", `String (sym f)); ("args", `List (List.map t args)) ]
  | Call (f, args) -> `Assoc [ ("fn", `String f); ("args", `List (List.map t args)) ]

(* ---- JSON -> Landau, rebuilding readable forms (a/b, sqrt, -x) ---- *)

let product = function [] -> Num Q.one | x :: xs -> List.fold_left (fun a b -> Mul (a, b)) x xs

let pow_of b e =
  match e with
  | Num q when Q.equal q (Q.of_ints 1 2) -> Call ("sqrt", [ b ])
  | Num q when Q.equal q (Q.of_ints (-1) 2) -> Div (Num Q.one, Call ("sqrt", [ b ]))
  | Num q when Q.equal q Q.minus_one -> Div (Num Q.one, b)
  | Num q when Q.sign q < 0 -> Div (Num Q.one, Pow (b, Num (Q.neg q)))
  | _ -> Pow (b, e)

let mul_of factors =
  let coef = ref Q.one and num = ref [] and den = ref [] in
  List.iter
    (function
      | Num q -> coef := Q.mul !coef q
      | Div (Num o, d) when Q.equal o Q.one -> den := !den @ [ d ]
      | f -> num := !num @ [ f ])
    factors;
  let c = !coef in
  let p = Q.num (Q.abs c) and q = Q.den c in
  let num = (if Z.equal p Z.one then [] else [ Num (Q.of_bigint p) ]) @ !num in
  let den = (if Z.equal q Z.one then [] else [ Num (Q.of_bigint q) ]) @ !den in
  let e = match den with [] -> product num | _ -> Div (product num, product den) in
  if Q.sign c < 0 then Neg e else e

let rec of_json back (j : Yojson.Safe.t) =
  let t = of_json back in
  match j with
  | `Assoc [ ("num", `String s) ] -> Num (Q.of_string s)
  | `Assoc [ ("sym", `String s) ] -> Var (back s)
  | `Assoc [ ("const", `String "pi") ] -> Const "pi"
  | `Assoc [ ("const", `String "oo") ] -> Const "inf"
  | `Assoc [ ("const", `String "I") ] -> Const "im"
  | `Assoc [ ("const", `String "E") ] -> Call ("exp", [ Num Q.one ])
  | `Assoc [ ("add", `List ts) ] -> (
      match List.map t ts with [] -> Num Q.zero | x :: xs -> List.fold_left (fun a b -> Add (a, b)) x xs)
  | `Assoc [ ("mul", `List fs) ] -> mul_of (List.map t fs)
  | `Assoc [ ("pow", `List [ b; e ]) ] -> pow_of (t b) (t e)
  | `Assoc [ ("fn", `String f); ("args", `List args) ] -> Call (f, List.map t args)
  | `Assoc [ ("eval", `String s); ("args", `List args) ] -> Call (back s, List.map t args)
  | _ -> fail "unexpected term from SymPy: %s" (Yojson.Safe.to_string j)

(* A component of a variable, comp(v, 1), travels as its own symbol "v.x":
   components of real vectors are real numbers. *)
let rec atomize e =
  match e with
  | Call ("comp", [ Var v; Num k ]) -> Var (v ^ "." ^ string_of_int (Q.to_int k))
  | Call ("entry", [ Var v; Num i; Num j ]) -> Var (sprintf "%s.%d.%d" v (Q.to_int i) (Q.to_int j))
  | _ -> map_children atomize e

let rec deatomize e =
  match e with
  | Var x when (match String.split_on_char '.' x with [ _; i; j ] -> int_of_string_opt i <> None && int_of_string_opt j <> None | _ -> false) -> (
      (* an entry of a matrix, A.1.2 *)
      match String.split_on_char '.' x with
      | [ a; i; j ] -> Call ("entry", [ Var a; Num (Q.of_string i); Num (Q.of_string j) ])
      | _ -> e)
  | Var x when String.contains x '.' -> (
      let i = String.rindex x '.' in
      match component_index (String.sub x (i + 1) (String.length x - i - 1)) with
      | Some k -> Call ("comp", [ Var (String.sub x 0 i); Num (Q.of_int k) ])
      | None -> e)
  | _ -> map_children deatomize e

(* In symbolic steps a quantity such as 9.81 [m/s^2] stays as it is: it
   travels as a positive symbol "#q0" and comes back unchanged, so units are
   never mixed into the algebra. *)
let hide_quantities exprs =
  let table = ref [] in
  let rec hide e =
    match e with
    | Quantity _ -> (
        match List.find_opt (fun (_, q) -> q = e) !table with
        | Some (n, _) -> Var n
        | None ->
            let n = sprintf "#q%d" (List.length !table) in
            table := (n, e) :: !table;
            Var n)
    | _ -> map_children hide e
  in
  let exprs = List.map hide exprs in
  let reveal e =
    let rec go e = match e with Var n when List.mem_assoc n !table -> List.assoc n !table | _ -> map_children go e in
    go e
  in
  let attrs attrs_of x =
    match List.assoc_opt x !table with
    | Some (Quantity (q, _)) -> if Q.sign q > 0 then [ "positive" ] else if Q.sign q < 0 then [ "nonzero" ] else []
    | _ -> attrs_of x
  in
  (exprs, reveal, attrs)

(* ---- requests ---- *)

(* [deps_of x] lists what x depends on; such variables become functions in
   SymPy, x(t), so that derivatives of them are not 0. *)
let symbols ~attrs_of ~deps_of exprs =
  let vs = List.fold_left vars [] exprs in
  (* variables evaluated at a point, x(0), are symbols too *)
  let rec heads acc e =
    let acc = match e with Call (f, _) when deps_of f <> [] && not (List.mem f acc) -> acc @ [ f ] | _ -> acc in
    List.fold_left heads acc (children e)
  in
  let vs = List.fold_left heads vs exprs in
  let vs = List.fold_left (fun acc x -> List.fold_left (fun acc d -> if List.mem d acc then acc else acc @ [ d ]) acc (deps_of x)) vs vs in
  let names = List.mapi (fun i x -> (x, sprintf "s%d" i)) vs in
  let syms =
    `Assoc
      (List.map
         (fun (x, s) ->
           let a = attrs_of x in
           let flag f = if List.mem f a then [ (f, `Bool true) ] else [] in
           (* vectors travel as plain symbols: only linear algebra and opaque operators touch them *)
           let vector = List.exists (fun a -> List.exists (fun p -> String.starts_with ~prefix:p a) [ "vector"; "position"; "matrix" ]) a in
           let real = if List.mem "complex" a || vector then [] else [ ("real", `Bool true) ] in
           let deps = match deps_of x with [] -> [] | ds -> [ ("deps", `List (List.map (fun d -> `String (List.assoc d names)) ds)) ] in
           (s, `Assoc (real @ flag "positive" @ flag "nonzero" @ flag "integer" @ deps)))
         names)
  in
  let sym x = List.assoc x names in
  (* names SymPy made up, like the constants C1, C2 of dsolve, come back as they are *)
  let back s = match List.find_opt (fun (_, s') -> s' = s) names with Some (x, _) -> x | None -> s in
  let is_var f = deps_of f <> [] && List.mem_assoc f names in
  (sym, back, syms, is_var)

let simplify ~attrs_of ~deps_of e =
  let e, reveal, attrs = match hide_quantities [ e ] with [ e ], r, a -> (e, r, a) | _ -> assert false in
  let attrs_of = attrs attrs_of in
  let e = atomize e in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of [ e ] in
  match request (`Assoc [ ("op", `String "simplify"); ("expr", to_json ~is_var sym e); ("syms", syms) ]) with
  | [ r ] -> reveal (deatomize (of_json back r))
  | _ -> fail "unexpected reply to simplify"

let solve ~attrs_of ~deps_of (q : eq) x =
  let l, reveal, attrs = match hide_quantities [ q.lhs; q.rhs ] with [ l; r ], rv, a -> ({ lhs = l; rhs = r }, rv, a) | _ -> assert false in
  let attrs_of = attrs attrs_of in
  let q = map_eq atomize l in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of [ q.lhs; q.rhs; Var x ] in
  request
    (`Assoc
      [ ("op", `String "solve"); ("lhs", to_json ~is_var sym q.lhs); ("rhs", to_json ~is_var sym q.rhs);
        ("for", `String (sym x)); ("syms", syms) ])
  |> List.map (fun r -> reveal (deatomize (of_json back r)))

(* Solve a differential equation for the function x, with initial
   conditions such as x(0) = x0. *)
let dsolve ~attrs_of ~deps_of (q : eq) x (ics : eq list) =
  let rec pairs = function a :: b :: r -> { lhs = a; rhs = b } :: pairs r | _ -> [] in
  let hidden, reveal, attrs = hide_quantities (List.concat_map (fun i -> [ i.lhs; i.rhs ]) (q :: ics)) in
  let attrs_of = attrs attrs_of in
  let q, ics = match pairs hidden with q :: ics -> (q, ics) | [] -> assert false in
  let q = map_eq atomize q and ics = List.map (map_eq atomize) ics in
  let all = q.lhs :: q.rhs :: Var x :: List.concat_map (fun i -> [ i.lhs; i.rhs ]) ics in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of all in
  let j = to_json ~is_var sym in
  request
    (`Assoc
      [ ("op", `String "dsolve"); ("lhs", j q.lhs); ("rhs", j q.rhs); ("for", `String (sym x));
        ("ics", `List (List.map (fun i -> `List [ j i.lhs; j i.rhs ]) ics)); ("syms", syms) ])
  |> List.map (fun r -> reveal (deatomize (of_json back r)))

(* Solve several equations for several unknowns. Each solution set gives the
   value of every unknown, or None when the equations leave it free. *)
let solve_system ~attrs_of ~deps_of (qs : eq list) xs =
  let hidden, reveal, attrs = hide_quantities (List.concat_map (fun q -> [ q.lhs; q.rhs ]) qs) in
  let attrs_of = attrs attrs_of in
  let rec pairs = function a :: b :: r -> { lhs = a; rhs = b } :: pairs r | _ -> [] in
  let qs = List.map (map_eq atomize) (pairs hidden) in
  let all = List.concat_map (fun q -> [ q.lhs; q.rhs ]) qs @ List.map (fun x -> Var x) xs in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of all in
  let j = to_json ~is_var sym in
  request
    (`Assoc
      [ ("op", `String "solve_system");
        ("eqs", `List (List.map (fun q -> `List [ j q.lhs; j q.rhs ]) qs));
        ("for", `List (List.map (fun x -> `String (sym x)) xs));
        ("syms", syms) ])
  |> List.map (function
       | `List vals -> List.map (function `Null -> None | v -> Some (reveal (deatomize (of_json back v)))) vals
       | r -> fail "unexpected reply to solve_system: %s" (Yojson.Safe.to_string r))

(* The numeric value of an expression with no variables left: a number with
   [digits] significant figures, as a decimal string. *)
let evaluate ~digits e =
  let sym, _, syms, is_var = symbols ~attrs_of:(fun _ -> []) ~deps_of:(fun _ -> []) [ e ] in
  match
    request
      (`Assoc [ ("op", `String "evaluate"); ("expr", to_json ~is_var sym e); ("digits", `Int digits); ("syms", syms) ])
  with
  | [ `String v ] -> v
  | _ -> fail "unexpected reply to evaluate"

(* det, inv or eigen of square matrices given by their entries, rows first.
   Returns SymPy's reply and how to read an expression in it back. *)
let matrices ~attrs_of ~deps_of fn (ms : expr list list list) =
  let hidden, reveal, attrs = hide_quantities (List.concat (List.concat ms)) in
  let attrs_of = attrs attrs_of in
  let hidden = List.map atomize hidden in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of hidden in
  let rest = ref hidden in
  let next () = match !rest with x :: r -> rest := r; to_json ~is_var sym x | [] -> assert false in
  let json = `List (List.map (fun m -> `List (List.map (fun row -> `List (List.map (fun _ -> next ()) row)) m)) ms) in
  let reply = request (`Assoc [ ("op", `String "matrix"); ("fn", `String fn); ("matrices", json); ("syms", syms) ]) in
  (reply, fun j -> reveal (deatomize (of_json back j)))

let det ~attrs_of ~deps_of rows =
  match matrices ~attrs_of ~deps_of "det" [ rows ] with [ r ], back -> back r | _ -> fail "unexpected reply to det"

let inv ~attrs_of ~deps_of rows =
  match matrices ~attrs_of ~deps_of "inv" [ rows ] with
  | [ `List rs ], back -> List.map (function `List xs -> List.map back xs | _ -> fail "unexpected reply to inv") rs
  | _ -> fail "unexpected reply to inv"

(* The eigenvalues of a (or of K v = λ M v, with b = M), each with its
   multiplicity and eigenvectors. *)
let eigen ~attrs_of ~deps_of a b =
  match matrices ~attrs_of ~deps_of "eigen" (a :: Option.to_list b) with
  | [ `List vs ], back ->
      List.map
        (function
          | `List [ value; `Int mult; `List vectors ] ->
              (back value, mult, List.map (function `List xs -> List.map back xs | _ -> fail "unexpected reply to eigen") vectors)
          | _ -> fail "unexpected reply to eigen")
        vs
  | _ -> fail "unexpected reply to eigen"

(* A basis of the nullspace of a rational matrix with [cols] columns. *)
let nullspace (rows : Q.t list list) cols =
  let row r = `List (List.map (fun q -> `String (Q.to_string q)) r) in
  request (`Assoc [ ("op", `String "nullspace"); ("matrix", `List (List.map row rows)); ("cols", `Int cols); ("syms", `Assoc []) ])
  |> List.map (function
       | `List xs -> List.map (function `String q -> Q.of_string q | _ -> fail "unexpected reply to nullspace") xs
       | _ -> fail "unexpected reply to nullspace")

(* The expansion of [e] in the bookkeeping symbol [eps] to [order], with eps
   set to 1, and the first term left out, if found. *)
let series ~attrs_of ~deps_of e eps order =
  let e, reveal, attrs = match hide_quantities [ e ] with [ e ], r, a -> (e, r, a) | _ -> assert false in
  let attrs_of = attrs attrs_of in
  let e = atomize e in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of [ e; Var eps ] in
  let back_expr j = reveal (deatomize (of_json back j)) in
  match
    request
      (`Assoc
        [ ("op", `String "series"); ("expr", to_json ~is_var sym e); ("eps", `String (sym eps)); ("order", `Int order);
          ("syms", syms) ])
  with
  | [ kept; `Null ] -> (back_expr kept, None)
  | [ kept; next ] -> (back_expr kept, Some (back_expr next))
  | _ -> fail "unexpected reply to series"

(* The limit of [e] as the variable [x] goes to [point]. *)
let limit ~attrs_of ~deps_of e x point =
  let e, point, reveal, attrs =
    match hide_quantities [ e; point ] with [ e; p ], r, a -> (e, p, r, a) | _ -> assert false
  in
  let attrs_of = attrs attrs_of in
  let e = atomize e and point = atomize point in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of [ e; Var x; point ] in
  match
    request
      (`Assoc
        [ ("op", `String "limit"); ("expr", to_json ~is_var sym e); ("var", `String (sym x));
          ("point", to_json ~is_var sym point); ("syms", syms) ])
  with
  | [ v ] -> reveal (deatomize (of_json back v))
  | _ -> fail "unexpected reply to limit"

(* The Euler–Lagrange expression d/dt ∂L/∂ẋ - ∂L/∂x of the Lagrangian [l]
   for the coordinate x(t). *)
let euler_lagrange ~attrs_of ~deps_of l x t =
  let l, reveal, attrs = match hide_quantities [ l ] with [ l ], r, a -> (l, r, a) | _ -> assert false in
  let attrs_of = attrs attrs_of in
  let l = atomize l in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of [ l; Var x; Var t ] in
  match
    request
      (`Assoc
        [ ("op", `String "euler_lagrange"); ("expr", to_json ~is_var sym l); ("for", `String (sym x));
          ("by", `String (sym t)); ("syms", syms) ])
  with
  | [ v ] -> reveal (deatomize (of_json back v))
  | _ -> fail "unexpected reply to euler_lagrange"

(* What Noether's theorem gives for the symmetry [by] of the Lagrangian [l]:
   with [by] the time t, ∂L/∂t and the energy Σ ẋ ∂L/∂ẋ - L over the
   coordinates; with [by] a coordinate x, ∂L/∂x and the momentum ∂L/∂ẋ. The
   quantity is conserved when the derivative is 0. *)
let conserved ~attrs_of ~deps_of l coords t by =
  let l, reveal, attrs = match hide_quantities [ l ] with [ l ], r, a -> (l, r, a) | _ -> assert false in
  let attrs_of = attrs attrs_of in
  let l = atomize l in
  let sym, back, syms, is_var = symbols ~attrs_of ~deps_of (l :: Var t :: List.map (fun c -> Var c) coords) in
  match
    request
      (`Assoc
        [ ("op", `String "conserved"); ("expr", to_json ~is_var sym l);
          ("coords", `List (List.map (fun c -> `String (sym c)) coords)); ("by", `String (sym t));
          ("for", `String (sym by)); ("syms", syms) ])
  with
  | [ d; q ] -> (reveal (deatomize (of_json back d)), reveal (deatomize (of_json back q)))
  | _ -> fail "unexpected reply to conserved"

(* A numerical root of [e] = 0 for x near [guess]; everything else must be a
   number already. The root is in base units, as a decimal string. *)
let nsolve ~attrs_of ~deps_of e x guess =
  let sym, _, syms, is_var = symbols ~attrs_of ~deps_of [ e; Var x; guess ] in
  match
    request
      (`Assoc
        [ ("op", `String "nsolve"); ("expr", to_json ~is_var sym e); ("for", `String (sym x));
          ("guess", to_json ~is_var sym guess); ("syms", syms) ])
  with
  | [ `String v ] -> v
  | _ -> fail "unexpected reply to nsolve"

type simulation_result = { times : float list; series : float list list; method_ : string }

(* Integrate the differential equations eqs = 0 for the unknowns [xs] of
   [t], numerically, from t0 to t1 (numbers in base units). Initial values
   are (unknown, derivative order, value). *)
let simulate ~attrs_of ~deps_of (eqs : expr list) xs t t0 t1 (ics : (string * int * string) list) points =
  let sym, _, syms, is_var = symbols ~attrs_of ~deps_of (eqs @ List.map (fun x -> Var x) (t :: xs)) in
  let floats = function
    | `List vs -> List.map (function `Float f -> f | `Int i -> float_of_int i | _ -> nan) vs
    | _ -> fail "unexpected numbers from the simulation"
  in
  match
    request
      (`Assoc
        [ ("op", `String "simulate"); ("eqs", `List (List.map (to_json ~is_var sym) eqs));
          ("for", `List (List.map (fun x -> `String (sym x)) xs)); ("t", `String (sym t));
          ("t0", `String t0); ("t1", `String t1); ("points", `Int points);
          ( "ics",
            `List
              (List.map
                 (fun (x, k, v) -> `Assoc [ ("var", `String (sym x)); ("order", `Int k); ("value", `String v) ])
                 ics) ); ("syms", syms) ])
  with
  | [ `Assoc r ] ->
      let get k = match List.assoc_opt k r with Some v -> v | None -> fail "the simulation returned no %s" k in
      {
        times = floats (get "t");
        series = (match get "series" with `List ss -> List.map floats ss | _ -> []);
        method_ = (match get "method" with `String m -> m | _ -> "");
      }
  | _ -> fail "unexpected reply to simulate"
