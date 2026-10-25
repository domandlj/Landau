{
open Parser

exception Error of string

let keywords =
  [ ("theory", THEORY); ("end", END); ("import", IMPORT); ("dim", DIM); ("var", VAR);
    ("def", DEF); ("law", LAW); ("derive", DERIVE); ("solve", SOLVE); ("for", FOR);
    ("subst", SUBST); ("into", INTO); ("simplify", SIMPLIFY); ("unfold", UNFOLD);
    ("root", ROOT); ("component", COMPONENT); ("of", OF); ("expand", EXPAND);
    ("differentiate", DIFFERENTIATE); ("by", BY); ("apply", APPLY); ("to", TO);
    ("integrate", INTEGRATE); ("from", FROM); ("with", WITH); ("unit", UNIT);
    ("evaluate", EVALUATE); ("in", IN); ("digits", DIGITS); ("const", CONST);
    ("compute", COMPUTE); ("approximate", APPROXIMATE); ("where", WHERE); ("order", ORDER);
    ("limit", LIMIT); ("as", AS); ("numerically", NUMERICALLY); ("near", NEAR);
    ("simulate", SIMULATE); ("points", POINTS); ("diagram", DIAGRAM); ("body", BODY);
    ("force", FORCE); ("toward", TOWARD); ("accelerates", ACCELERATES); ("plane", PLANE); ("draw", DRAW);
    ("mark", MARK); ("between", BETWEEN); ("and", AND); ("groups", GROUPS); ("eigen", EIGEN) ]

(* "9.81" -> 981/100 and "1.6e-19" -> 16/10^20, exactly *)
let decimal s =
  let mant, exp =
    match String.index_from_opt (String.lowercase_ascii s) 0 'e' with
    | Some i -> (String.sub s 0 i, int_of_string (String.sub s (i + 1) (String.length s - i - 1)))
    | None -> (s, 0)
  in
  let q =
    match String.index_opt mant '.' with
    | None -> Q.of_string mant
    | Some i ->
        let ip = String.sub mant 0 i and fp = String.sub mant (i + 1) (String.length mant - i - 1) in
        Q.make (Z.of_string (ip ^ fp)) (Z.pow (Z.of_int 10) (String.length fp))
  in
  let ten = Q.of_bigint (Z.pow (Z.of_int 10) (abs exp)) in
  if exp >= 0 then Q.mul q ten else Q.div q ten

(* The lines of a text block without their common indentation, and without
   blank lines at the start and the end. *)
let dedent s =
  let lines = String.split_on_char '\n' s |> List.map (fun l -> if String.ends_with ~suffix:"\r" l then String.sub l 0 (String.length l - 1) else l) in
  let blank l = String.trim l = "" in
  let indent l = let n = String.length l in let rec go i = if i < n && (l.[i] = ' ' || l.[i] = '\t') then go (i + 1) else i in go 0 in
  let cut = List.fold_left (fun m l -> if blank l then m else min m (indent l)) max_int lines in
  let rec drop = function l :: r when blank l -> drop r | ls -> ls in
  lines |> drop |> List.rev |> drop |> List.rev
  |> List.map (fun l -> if blank l then "" else String.sub l cut (String.length l - cut))
  |> String.concat "\n"
}

let digit = ['0'-'9']
(* bytes >= 128 let UTF-8 names like θ or ω through *)
let idstart = ['a'-'z' 'A'-'Z' '_' '\128'-'\255']
let idchar = idstart | digit | '\''

rule token = parse
  | [' ' '\t' '\r']+ { token lexbuf }
  | '\n' { Lexing.new_line lexbuf; token lexbuf }
  | "--" [^ '\n']* { token lexbuf }
  | '#' [^ '\n']* { token lexbuf }
  | "text" [' ' '\t' '\r']* '\n'
    { (* the block's position is where `text` is, not its last line *)
      let start = lexbuf.lex_start_p in
      Lexing.new_line lexbuf;
      let t = try Some (text_block (Buffer.create 256) lexbuf) with Exit -> None in
      lexbuf.lex_start_p <- start;
      let t = match t with Some t -> t | None -> raise (Error "this `text` block has no `end` on a line of its own") in
      TEXT (dedent t) }
  | digit+ ('.' digit+)? (['e' 'E'] '-'? digit+)? as s { NUM (decimal s) }
  | ":=" { ASSIGN }
  | "<<" { MUCHLESS }
  | "->" { ARROW }
  | ':' { COLON }
  | ',' { COMMA }
  | '=' { EQ }
  | '+' { PLUS }
  | '-' { MINUS }
  | '*' { STAR }
  | '/' { SLASH }
  | '^' { CARET }
  | '(' { LPAREN }
  | ')' { RPAREN }
  | '[' { LBRACK }
  | ']' { RBRACK }
  | '.' { DOT }
  | idstart idchar* as s { match List.assoc_opt s keywords with Some k -> k | None -> ID s }
  | eof { EOF }
  | _ as c { raise (Error (Printf.sprintf "unexpected character %C" c)) }

(* text ... end: everything up to a line holding only `end`, as written *)
and text_block buf = parse
  | [' ' '\t']* "end" [' ' '\t' '\r']* ("--" [^ '\n']*)? ('\n' as nl)? { if nl <> None then Lexing.new_line lexbuf; Buffer.contents buf }
  | [^ '\n']* '\n' as l { Lexing.new_line lexbuf; Buffer.add_string buf l; text_block buf lexbuf }
  | [^ '\n']+ as l { Buffer.add_string buf l; text_block buf lexbuf }
  | eof { raise Exit }
