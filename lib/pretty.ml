open Syntax

(* Precedence levels: 1 = + -, 2 = * / and unary minus, 4 = ^, 5 = atoms. *)

let is_int q = Z.equal (Q.den q) Z.one

(* ---- units ---- *)

(* A unit or dimension expression as written: kg*m/s^2 *)
let rec dexpr_to_string = function
  | DOne -> "1"
  | DNum q -> Q.to_string q
  | DName n -> n
  | DMul (a, b) -> dexpr_to_string a ^ "*" ^ dexpr_to_string b
  | DDiv (a, b) -> (
      dexpr_to_string a ^ "/" ^ match b with DMul _ | DDiv _ -> "(" ^ dexpr_to_string b ^ ")" | _ -> dexpr_to_string b)
  | DPow (a, q) ->
      (match a with DName _ -> dexpr_to_string a | _ -> "(" ^ dexpr_to_string a ^ ")")
      ^ "^" ^ if is_int q then Q.to_string q else "(" ^ Q.to_string q ^ ")"

(* The unit names of an expression, in the order written. *)
let rec unit_names = function
  | DName n -> [ n ]
  | DMul (a, b) | DDiv (a, b) -> unit_names a @ unit_names b
  | DPow (a, _) -> unit_names a
  | DOne | DNum _ -> []

(* Units for display reuse Dim.t, with unit names as the keys: N*m is {N: 1, m: 1}. *)
let rec unit_vector = function
  | DName n -> Dim.base n
  | DMul (a, b) -> Dim.add (unit_vector a) (unit_vector b)
  | DDiv (a, b) -> Dim.sub (unit_vector a) (unit_vector b)
  | DPow (a, q) -> Dim.scale q (unit_vector a)
  | DOne | DNum _ -> Dim.one

(* A measured number for reading: 9.81, 299792458, 6.6743e-11 *)
let number q =
  if is_int q && Q.lt (Q.abs q) (Q.of_int 1_000_000_000) then Q.to_string q
  else
    let s = Printf.sprintf "%.12g" (Q.to_float q) in
    (* 8.24e-08 -> 8.24e-8 *)
    match String.index_opt s 'e' with
    | Some i -> String.sub s 0 (i + 1) ^ string_of_int (int_of_string (String.sub s (i + 1) (String.length s - i - 1)))
    | None -> s

let number_latex q =
  let s = number q in
  match String.index_opt s 'e' with
  | None -> s
  | Some i ->
      let m = String.sub s 0 i and e = String.sub s (i + 1) (String.length s - i - 1) in
      let e = if e.[0] = '+' then String.sub e 1 (String.length e - 1) else e in
      let e = match int_of_string_opt e with Some k -> string_of_int k | None -> e in
      m ^ " \\times 10^{" ^ e ^ "}"

let unit_latex u = Dim.to_latex ~roman:true ~order:(unit_names u) (unit_vector u)

(* If [e] prints with a leading minus, return the expression without it. *)
let rec neg_lead = function
  | Num q when Q.sign q < 0 -> Some (Num (Q.neg q))
  | Quantity (q, u) when Q.sign q < 0 -> Some (Quantity (Q.neg q, u))
  | Neg a -> Some a
  | Mul (a, b) -> Option.map (fun a -> Mul (a, b)) (neg_lead a)
  | Div (a, b) -> Option.map (fun a -> Div (a, b)) (neg_lead a)
  | _ -> None

(* Components of vectors with more than 3 entries print as numbers (X.4),
   the others as x, y, z. The checker sets this to look up vector sizes. *)
let vector_size : (string -> int option) ref = ref (fun _ -> None)

(* What each variable depends on, to write dx/dt rather than ∂x/∂t when x
   depends on t alone. Also set by the checker. *)
let deps_of : (string -> string list) ref = ref (fun _ -> [])

(* Whether an expression is a vector: F·dr or f dl in a line integral. *)
let is_vector_expr : (expr -> bool) ref = ref (fun _ -> false)

(* Matrices, shown in bold. Set by the checker. *)
let is_matrix : (string -> bool) ref = ref (fun _ -> false)

(* Independent variables: the position, and anything a variable depends on. *)
let independent : (string -> bool) ref = ref (fun _ -> false)

(* Variables that measure time (dimension T), whose derivatives may be dots. *)
let is_time : (string -> bool) ref = ref (fun _ -> false)

let comp_name a k =
  match a with
  | Var v when Option.value (!vector_size v) ~default:3 > 3 -> string_of_int k
  | _ -> component_name k

let rec go p e =
  let paren q s = if q < p then "(" ^ s ^ ")" else s in
  match e with
  | Num q when Q.sign q < 0 -> paren 2 ("-" ^ go 3 (Num (Q.neg q)))
  | Num q -> if is_int q then Q.to_string q else paren 2 (Q.to_string q)
  | Quantity (q, u) when Q.sign q < 0 -> paren 2 ("-" ^ go 3 (Quantity (Q.neg q, u)))
  | Quantity (q, DOne) -> number q
  (* in parentheses inside a product or quotient: E1/(2 [s]), not E1/2 [s] *)
  | Quantity (q, u) -> paren 2 (number q ^ " [" ^ dexpr_to_string u ^ "]")
  | Var x | Const x -> x
  | Neg (Mul (a, b)) -> go p (Mul (Neg a, b))
  | Neg (Div (a, b)) -> go p (Div (Neg a, b))
  | Neg a -> paren 2 ("-" ^ go 3 a)
  | Add (a, b) -> (
      match neg_lead b with
      | Some b' -> paren 1 (go 1 a ^ " - " ^ go 2 b')
      | None -> paren 1 (go 1 a ^ " + " ^ go 2 b))
  | Sub (a, b) -> (
      match neg_lead b with
      | Some b' -> paren 1 (go 1 a ^ " + " ^ go 2 b')
      | None -> paren 1 (go 1 a ^ " - " ^ go 2 b))
  | Mul (a, b) -> paren 2 (go 2 a ^ "*" ^ go 3 b)
  | Div (a, b) -> paren 2 (go 2 a ^ "/" ^ go 3 b)
  | Pow (a, b) -> paren 4 (go 5 a ^ "^" ^ go 4 b)
  | Call ("comp", [ a; Num k ]) when is_int k -> go 6 a ^ "." ^ comp_name a (Q.to_int k)
  | Call (f, args) -> f ^ "(" ^ String.concat ", " (List.map (go 0) args) ^ ")"

let expr e = go 0 e
let eq q = expr q.lhs ^ " = " ^ expr q.rhs

(* ---- LaTeX, for the web frontend ---- *)

let greek =
  [ ("α", "alpha"); ("β", "beta"); ("γ", "gamma"); ("δ", "delta"); ("ε", "varepsilon"); ("ζ", "zeta");
    ("η", "eta"); ("θ", "theta"); ("ι", "iota"); ("κ", "kappa"); ("λ", "lambda"); ("μ", "mu"); ("ν", "nu");
    ("ξ", "xi"); ("π", "pi"); ("ρ", "rho"); ("σ", "sigma"); ("τ", "tau"); ("υ", "upsilon"); ("φ", "varphi");
    ("χ", "chi"); ("ψ", "psi"); ("ω", "omega"); ("Γ", "Gamma"); ("Δ", "Delta"); ("Θ", "Theta");
    ("Λ", "Lambda"); ("Ξ", "Xi"); ("Π", "Pi"); ("Σ", "Sigma"); ("Φ", "Phi"); ("Ψ", "Psi"); ("Ω", "Omega");
    ("ϱ", "varrho"); ("ϑ", "vartheta"); ("ϕ", "phi"); ("ς", "varsigma"); ("ϵ", "epsilon"); ("ħ", "hbar"); ("ℓ", "ell") ]

(* Split a string into its UTF-8 characters. *)
let uchars s =
  let rec go i acc =
    if i >= String.length s then List.rev acc
    else
      let n = Uchar.utf_decode_length (String.get_utf_8_uchar s i) in
      go (i + n) (String.sub s i n :: acc)
  in
  go 0 []

let symbol s =
  let cs = uchars s in
  let tex = String.concat "" (List.map (fun c -> match List.assoc_opt c greek with Some g -> "\\" ^ g ^ " " | None -> c) cs) in
  if List.length cs <= 1 then tex else "\\mathit{" ^ tex ^ "}"

(* The part after _: words upright, Greek as its command, a further _ written
   out. v_θmax -> \theta\mathrm{max}, a_b_c -> \mathrm{b\_c} *)
let subscript s =
  let buf = Buffer.create 16 and run = Buffer.create 16 in
  let flush () =
    if Buffer.length run > 0 then Buffer.add_string buf ("\\mathrm{" ^ Buffer.contents run ^ "}");
    Buffer.clear run
  in
  List.iter
    (fun c ->
      match List.assoc_opt c greek with
      | Some g -> flush (); Buffer.add_string buf ("\\" ^ g ^ " ")
      | None -> Buffer.add_string run (if c = "_" then "\\_" else c))
    (uchars s);
  flush ();
  Buffer.contents buf

(* x0 -> x_{0}, v_max -> v_{\mathrm{max}}, x' stays a prime; vectors get an
   arrow and matrices are bold *)
let name ?(vec = false) ?(mat = false) s =
  let n = String.length s in
  let primes = ref n in
  while !primes > 0 && s.[!primes - 1] = '\'' do decr primes done;
  let core = String.sub s 0 !primes and tail = String.sub s !primes (n - !primes) in
  let split =
    match String.index_opt core '_' with
    | Some i when i > 0 -> Some (String.sub core 0 i, subscript (String.sub core (i + 1) (String.length core - i - 1)))
    | _ ->
        let j = ref (String.length core) in
        while !j > 0 && core.[!j - 1] >= '0' && core.[!j - 1] <= '9' do decr j done;
        if !j > 0 && !j < String.length core then Some (String.sub core 0 !j, String.sub core !j (String.length core - !j))
        else None
  in
  let bold b =
    (* \mathit inside \boldsymbol would undo the bold: Mm -> \boldsymbol{Mm} *)
    let t = symbol b and it = "\\mathit{" in
    let n = String.length it in
    if String.length t > n && String.sub t 0 n = it then "\\boldsymbol{" ^ String.sub t n (String.length t - n) else "\\boldsymbol{" ^ t ^ "}"
  in
  let sym b = if vec then "\\vec{" ^ symbol b ^ "}" else if mat then bold b else symbol b in
  (match split with Some (b, sub) -> sym b ^ "_{" ^ sub ^ "}" | None -> sym core) ^ tail

let tex_fns =
  [ ("sin", "\\sin"); ("cos", "\\cos"); ("tan", "\\tan"); ("asin", "\\arcsin"); ("acos", "\\arccos");
    ("atan", "\\arctan"); ("sinh", "\\sinh"); ("cosh", "\\cosh"); ("tanh", "\\tanh"); ("exp", "\\exp");
    ("log", "\\log") ]

let fn_name f =
  let c = function "_" -> "\\_" | c -> (match List.assoc_opt c greek with Some g -> "\\" ^ g ^ " " | None -> c) in
  "\\operatorname{" ^ String.concat "" (List.map c (uchars f)) ^ "}"

let lparen s = "\\left(" ^ s ^ "\\right)"

(* Plain parentheses hug a function name; \left( only when the arguments are tall. *)
let call_args args =
  let s = String.concat ", " args in
  let has_frac a =
    let n = String.length a in
    let rec at i = i + 5 <= n && (String.sub a i 5 = "\\frac" || at (i + 1)) in
    at 0
  in
  let tall = List.exists has_frac args in
  if tall then lparen s else "(" ^ s ^ ")"

(* Same levels as [go]; fractions sit at 3 so they need no parentheses in a
   product. [vec x] says whether the variable x is a vector. *)
let rec tex vec p e =
  let tex = tex vec in
  let paren q s = if q < p then lparen s else s in
  let matrix_rows rows =
    String.concat " \\\\ "
      (List.map (function Call ("vec", xs) -> String.concat " & " (List.map (tex 0) xs) | r -> tex 0 r) rows)
  in
  match e with
  | Num q when Q.sign q < 0 -> paren 2 ("-" ^ tex 3 (Num (Q.neg q)))
  | Num q -> if is_int q then Q.to_string q else paren 3 (Printf.sprintf "\\frac{%s}{%s}" (Z.to_string (Q.num q)) (Z.to_string (Q.den q)))
  | Var x -> name ~vec:(vec x) ~mat:(!is_matrix x) x
  | Quantity (q, u) when Q.sign q < 0 -> paren 2 ("-" ^ tex 3 (Quantity (Q.neg q, u)))
  | Quantity (q, DOne) -> number_latex q
  | Quantity (q, u) -> paren 3 (number_latex q ^ "\\," ^ unit_latex u)
  | Const "pi" -> "\\pi"
  | Const "inf" -> "\\infty"
  | Const _ -> "i"
  | Neg (Mul (a, b)) -> tex p (Mul (Neg a, b))
  | Neg a -> paren 2 ("-" ^ tex 3 a)
  | Add (a, b) -> (
      match neg_lead b with
      | Some b' -> paren 1 (tex 1 a ^ " - " ^ tex 2 b')
      | None -> paren 1 (tex 1 a ^ " + " ^ tex 2 b))
  | Sub (a, b) -> (
      match neg_lead b with
      | Some b' -> paren 1 (tex 1 a ^ " + " ^ tex 2 b')
      | None -> paren 1 (tex 1 a ^ " - " ^ tex 2 b))
  | Mul (a, b) ->
      let rb = tex 3 b in
      let sep = match b with Num _ -> " \\cdot " | _ when rb <> "" && rb.[0] >= '0' && rb.[0] <= '9' -> " \\cdot " | _ -> "\\," in
      paren 2 (tex 2 a ^ sep ^ rb)
  | Div (a, b) -> paren 3 (Printf.sprintf "\\frac{%s}{%s}" (tex 0 a) (tex 0 b))
  | Pow (a, b) -> paren 4 (tex 5 a ^ "^{" ^ tex 0 b ^ "}")
  | Call ("sqrt", [ a ]) -> "\\sqrt{" ^ tex 0 a ^ "}"
  | Call ("abs", [ a ]) -> "\\left|" ^ tex 0 a ^ "\\right|"
  | Call ("norm", [ a ]) -> "\\left\\lVert " ^ tex 0 a ^ "\\right\\rVert"
  | Call ("conj", [ a ]) -> "\\overline{" ^ tex 0 a ^ "}"
  | Call ("dot", [ a; b ]) -> paren 2 (tex 2 a ^ " \\cdot " ^ tex 3 b)
  | Call ("cross", [ a; b ]) -> paren 2 (tex 2 a ^ " \\times " ^ tex 3 b)
  | Call ("grad", [ a ]) -> paren 3 ("\\nabla " ^ tex 5 a)
  | Call ("div", [ a ]) -> paren 2 ("\\nabla \\cdot " ^ tex 5 a)
  | Call ("curl", [ a ]) -> paren 2 ("\\nabla \\times " ^ tex 5 a)
  | Call ("lap", [ a ]) -> paren 3 ("\\nabla^{2} " ^ tex 5 a)
  | Call ("comp", [ Var v; Num k ]) when is_int k ->
      (* E.x -> E_{x}; v0.x -> v_{0,x} *)
      let n = name v and c = comp_name (Var v) (Q.to_int k) in
      let len = String.length n in
      if len > 0 && n.[len - 1] = '}' && String.contains n '_' then String.sub n 0 (len - 1) ^ "," ^ c ^ "}"
      else n ^ "_{" ^ c ^ "}"
  | Call ("comp", [ a; Num k ]) when is_int k -> lparen (tex 0 a) ^ "_{" ^ component_name (Q.to_int k) ^ "}"
  | Call ("vec", xs) -> "\\begin{pmatrix}" ^ String.concat " \\\\ " (List.map (tex 0) xs) ^ "\\end{pmatrix}"
  | Call ("mat", rows) -> "\\begin{pmatrix}" ^ matrix_rows rows ^ "\\end{pmatrix}"
  | Call ("det", [ Call ("mat", rows) ]) -> "\\begin{vmatrix}" ^ matrix_rows rows ^ "\\end{vmatrix}"
  | Call ("det", [ a ]) -> paren 3 ("\\det " ^ tex 5 a)
  | Call ("trace", [ a ]) -> paren 3 ("\\operatorname{tr} " ^ tex 5 a)
  | Call ("inv", [ a ]) -> tex 5 a ^ "^{-1}"
  | Call ("transpose", [ a ]) -> tex 5 a ^ "^{\\mathsf{T}}"
  | Call ("identity", [ n ]) -> "\\mathbf{1}_{" ^ tex 0 n ^ "}"
  | Call ("entry", [ Var v; Num i; Num j ]) when is_int i && is_int j ->
      (* K.1.2 -> K_{12}; K0 -> K_{0,12} *)
      let n = name v and ij = Q.to_string i ^ Q.to_string j in
      let len = String.length n in
      if len > 0 && n.[len - 1] = '}' && String.contains n '_' then String.sub n 0 (len - 1) ^ "," ^ ij ^ "}"
      else n ^ "_{" ^ ij ^ "}"
  | Call ("entry", [ a; Num i; Num j ]) -> lparen (tex 0 a) ^ "_{" ^ Q.to_string i ^ Q.to_string j ^ "}"
  | Call ("diff", [ _; _ ]) ->
      (* diff(diff(f, x), y): collect the variables, innermost first *)
      let rec chain e xs = match e with Call ("diff", [ f; x ]) -> chain f (x :: xs) | f -> (f, xs) in
      let f, xs = chain e [] in
      let xs = List.rev xs in
      (* a total derivative d when everything depends on one variable only; a
         definition's body is unknown here, so calls to one stay partial *)
      let rec known_fns e =
        match e with
        | Call ("comp", [ a; _ ]) -> known_fns a
        | Call (g, args) -> List.mem_assoc g tex_fns && List.for_all known_fns args
        | _ -> List.for_all known_fns (children e)
      in
      let total =
        match xs with
        | (Var x0 as x) :: _ when List.for_all (( = ) x) xs ->
            known_fns f
            && List.for_all
                 (fun v ->
                   (* what v depends on in the end, stopping at x0: x(θ) with
                      θ(t) depends on t alone *)
                   let rec leaves v = if v = x0 || !deps_of v = [] then [ v ] else List.concat_map leaves (!deps_of v) in
                   v = x0 || if !deps_of v = [] then not (!independent v) else List.for_all (( = ) x0) (leaves v))
                 (vars [] f)
        | _ -> false
      in
      let d = if total then "\\mathrm{d}" else "\\partial" in
      let n = List.length xs in
      (* consecutive equal variables group as a power: dt^2 *)
      let rec groups = function
        | [] -> []
        | x :: rest ->
            let rec run k = function y :: l when y = x -> run (k + 1) l | l -> (k, l) in
            let k, rest = run 1 rest in
            (x, k) :: groups rest
      in
      let den =
        String.concat "\\,"
          (List.map (fun (x, k) -> d ^ " " ^ tex 5 x ^ if k > 1 then "^{" ^ string_of_int k ^ "}" else "") (groups xs))
      in
      let dn = if n > 1 then d ^ "^{" ^ string_of_int n ^ "}" else d in
      let leibniz =
        match f with
        | Var _ | Call ("comp", _) -> Printf.sprintf "\\frac{%s %s}{%s}" dn (tex 0 f) den
        | _ -> Printf.sprintf "\\frac{%s}{%s} %s" dn den (tex 5 f)
      in
      (* The web app picks the notation: \landauderiv{ẍ}{x''}{d²x/dt²}. Dots
         only for time derivatives; partial derivatives stay Leibniz. *)
      paren 3
        (match (f, xs) with
        | (Var _ | Call ("comp", _)), Var x :: _ when total && n <= 4 ->
            let dots = [| "dot"; "ddot"; "dddot"; "ddddot" |] in
            let newton = if !is_time x then Printf.sprintf "\\%s{%s}" dots.(n - 1) (tex 0 f) else leibniz in
            let lagrange = if n <= 3 then "{" ^ tex 0 f ^ "}" ^ String.make n '\'' else Printf.sprintf "{%s}^{(%d)}" (tex 0 f) n in
            Printf.sprintf "\\landauderiv{%s}{%s}{%s}" newton lagrange leibniz
        | _ -> leibniz)
  | Call ("integral", [ f; x ]) -> paren 2 ("\\int " ^ tex 2 f ^ "\\,\\mathrm{d}" ^ tex 5 x)
  | Call ("integral", [ f; x; a; b ]) ->
      paren 2 (Printf.sprintf "\\int_{%s}^{%s} %s\\,\\mathrm{d}%s" (tex 0 a) (tex 0 b) (tex 2 f) (tex 5 x))
  | Call ("sum", [ f; k; a; b ]) ->
      paren 2 (Printf.sprintf "\\sum_{%s=%s}^{%s} %s" (tex 0 k) (tex 0 a) (tex 0 b) (tex 2 f))
  | Call ((("line" | "loop") as f), [ g; p; s; a; b ]) ->
      (* ∫_C F·dr over the curve p(s), s from a to b *)
      let sign = if f = "loop" then "\\oint" else "\\int" in
      let body = if !is_vector_expr g then tex 2 g ^ " \\cdot \\mathrm{d}\\vec{r}" else tex 2 g ^ "\\,\\mathrm{d}\\ell" in
      (* a named path goes under the sign; one written out would be too tall there *)
      let under = match p with Var _ -> tex 0 p ^ ",\\ " | _ -> "" in
      paren 2 (Printf.sprintf "%s_{%s%s=%s}^{%s} %s" sign under (tex 0 s) (tex 0 a) (tex 0 b) body)
  | Call ("surface", g :: q :: _) ->
      let body = if !is_vector_expr g then tex 2 g ^ " \\cdot \\mathrm{d}\\vec{A}" else tex 2 g ^ "\\,\\mathrm{d}A" in
      paren 2 (Printf.sprintf "\\iint%s %s" (match q with Var _ -> "_{" ^ tex 0 q ^ "}" | _ -> "") body)
  | Call ("volume", g :: q :: _) ->
      paren 2 (Printf.sprintf "\\iiint%s %s\\,\\mathrm{d}V" (match q with Var _ -> "_{" ^ tex 0 q ^ "}" | _ -> "") (tex 2 g))
  | Call ("at", [ e; x; a ]) -> Printf.sprintf "\\left. %s \\right|_{%s = %s}" (tex 0 e) (tex 0 x) (tex 0 a)
  | Call (f, args) when !deps_of f <> [] ->
      (* a variable evaluated at a point: x(0) *)
      name ~vec:(vec f) f ^ call_args (List.map (tex 0) args)
  | Call (f, args) ->
      let head = match List.assoc_opt f tex_fns with Some t -> t | None -> fn_name f in
      head ^ call_args (List.map (tex 0) args)

let latex ?(vec = fun _ -> false) e = tex vec 0 e
let latex_eq ?vec q = latex ?vec q.lhs ^ " = " ^ latex ?vec q.rhs
