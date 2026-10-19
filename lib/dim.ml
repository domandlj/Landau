(* Dimensions as sparse vectors of rational exponents.

   A dimension like M*L^2/T^2 is the map {M -> 1, L -> 2, T -> -2}.
   Keys are either base dimensions or inference variables; a dimension
   that mentions variables is a linear expression over them, which is
   what makes inference plain linear algebra over Q. *)

type key = Base of string | Var of int

module K = Map.Make (struct
  type t = key

  let compare = compare
end)

(* Invariant: no key maps to zero. *)
type t = Q.t K.t

let one : t = K.empty
let base b : t = K.singleton (Base b) Q.one
let var v : t = K.singleton (Var v) Q.one

let add (a : t) (b : t) : t =
  K.union
    (fun _ x y ->
      let s = Q.add x y in
      if Q.equal s Q.zero then None else Some s)
    a b

let scale q (d : t) : t = if Q.equal q Q.zero then one else K.map (Q.mul q) d
let sub a b = add a (scale Q.minus_one b)
let is_one (d : t) = K.is_empty d
let equal (a : t) (b : t) = K.equal Q.equal a b
let coeff k (d : t) = Option.value (K.find_opt k d) ~default:Q.zero
let remove_var v (d : t) : t = K.remove (Var v) d

let vars (d : t) =
  K.fold (fun k _ acc -> match k with Var v -> v :: acc | Base _ -> acc) d []
  |> List.rev

(* Replace every variable [v] by [f v]. *)
let map_vars f (d : t) : t =
  K.fold
    (fun k c acc ->
      match k with
      | Var v -> add acc (scale c (f v))
      | Base _ -> add acc (K.singleton k c))
    d one

let subst v s d = map_vars (fun w -> if w = v then s else var w) d

(* Base dimensions print in the order they were declared (M, L, T, ...). *)
let order : string list ref = ref []
let register b = if not (List.mem b !order) then order := !order @ [ b ]

let rank = function
  | Var v -> (0, v, "")
  | Base b ->
      let rec idx i = function
        | [] -> i
        | x :: r -> if x = b then i else idx (i + 1) r
      in
      (1, idx 0 !order, b)

let var_name v =
  let letter = String.make 1 (Char.chr (97 + (v mod 26))) in
  if v < 26 then "'" ^ letter else "'" ^ letter ^ string_of_int (v / 26)

(* How a base dimension is shown, when it differs from its name: dim Time (T). *)
let symbols : (string, string) Hashtbl.t = Hashtbl.create 8
let display b = Option.value (Hashtbl.find_opt symbols b) ~default:b
let key_name = function Base b -> display b | Var v -> var_name v

let exponent q =
  if Q.equal q Q.one then ""
  else if Z.equal (Q.den q) Z.one then "^" ^ Q.to_string q
  else "^(" ^ Q.to_string q ^ ")"

(* [order] lists names to put first, in that order: a unit as it was written,
   N*m rather than the declaration order's m N. *)
let sorted ?(order = []) (d : t) =
  let key k =
    match k with
    | Base b -> (
        let rec idx i = function [] -> None | x :: r -> if x = b then Some i else idx (i + 1) r in
        match idx 0 order with Some i -> (0, i, "") | None -> (1, 0, "") )
    | Var _ -> (1, 0, "")
  in
  K.bindings d |> List.sort (fun (a, _) (b, _) -> compare (key a, rank a) (key b, rank b))

let to_string ?order (d : t) =
  if is_one d then "1"
  else
    let items =
      sorted ?order d
    in
    let pos = List.filter (fun (_, q) -> Q.sign q > 0) items in
    let neg =
      List.filter_map (fun (k, q) -> if Q.sign q < 0 then Some (k, Q.neg q) else None) items
    in
    let fmt l = String.concat "*" (List.map (fun (k, q) -> key_name k ^ exponent q) l) in
    let den l = match l with [ _ ] -> fmt l | _ -> "(" ^ fmt l ^ ")" in
    match (pos, neg) with
    | _, [] -> fmt pos
    | [], _ -> "1/" ^ den neg
    | _ -> fmt pos ^ "/" ^ den neg

(* ---- LaTeX, for the web frontend ---- *)

let greek_vars = [| "\\alpha"; "\\beta"; "\\gamma"; "\\delta"; "\\epsilon"; "\\zeta"; "\\eta"; "\\kappa" |]

(* Dimensions are sans-serif; [~roman] is for units, which reuse this type
   with unit names as keys: kg m s^{-2}. *)
let key_latex ?(roman = false) = function
  | Base b -> (if roman then "\\mathrm{" else "\\mathsf{") ^ display b ^ "}"
  | Var v ->
      let n = Array.length greek_vars in
      if v < n then greek_vars.(v) else greek_vars.(v mod n) ^ "_{" ^ string_of_int (v / n) ^ "}"

(* With [~powers:true], negative exponents stay in the product, SI style:
   L T^{-1} rather than L/T. Positive powers come first either way. *)
let to_latex ?(powers = false) ?(roman = false) ?order (d : t) =
  let key_latex = key_latex ~roman in
  if is_one d then "1"
  else
    let items = sorted ?order d in
    if powers then
      let pos = List.filter (fun (_, q) -> Q.sign q > 0) items and neg = List.filter (fun (_, q) -> Q.sign q < 0) items in
      String.concat "\\,"
        (List.map (fun (k, q) -> key_latex k ^ if Q.equal q Q.one then "" else "^{" ^ Q.to_string q ^ "}") (pos @ neg))
    else
    let pos = List.filter (fun (_, q) -> Q.sign q > 0) items in
    let neg = List.filter_map (fun (k, q) -> if Q.sign q < 0 then Some (k, Q.neg q) else None) items in
    let fmt l =
      String.concat "\\,"
        (List.map
           (fun (k, q) -> key_latex k ^ if Q.equal q Q.one then "" else "^{" ^ Q.to_string q ^ "}")
           l)
    in
    match (pos, neg) with
    | _, [] -> fmt pos
    | _ ->
        let den = match neg with [ _ ] -> fmt neg | _ -> "(" ^ fmt neg ^ ")" in
        (if pos = [] then "1" else fmt pos) ^ "/" ^ den
