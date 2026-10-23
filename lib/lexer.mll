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
