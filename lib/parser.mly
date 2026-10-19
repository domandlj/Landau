%{
open Syntax
%}

%token <string> ID
%token <Q.t> NUM
%token THEORY END IMPORT DIM VAR DEF LAW DERIVE SOLVE FOR SUBST INTO SIMPLIFY UNFOLD ROOT
%token COMPONENT OF EXPAND DIFFERENTIATE BY APPLY TO INTEGRATE FROM WITH UNIT
%token EVALUATE IN DIGITS CONST COMPUTE APPROXIMATE WHERE ORDER LIMIT AS MUCHLESS ARROW
%token NUMERICALLY NEAR SIMULATE POINTS DIAGRAM BODY FORCE TOWARD ACCELERATES PLANE DRAW MARK BETWEEN AND GROUPS
%token COLON COMMA EQ ASSIGN PLUS MINUS STAR SLASH CARET
%token LPAREN RPAREN LBRACK RBRACK DOT EOF

(* An expression can end a step (`... to T`) and a step can start with `(`;
   `T (` is read as a call. *)
%nonassoc below_LPAREN
%nonassoc LPAREN
%left PLUS MINUS
%left STAR SLASH
%nonassoc UMINUS
%right CARET
%nonassoc DOT

%start <Syntax.item list> file

%%

file:
  | items = list(item) EOF { items }

item:
  | THEORY name = ID ds = list(decl) END { Theory (name, ds) }
  | d = decl { Top d }

decl:
  | d = decl_desc { { desc = d; line = $startpos.Lexing.pos_lnum } }

decl_desc:
  | IMPORT n = ID m = option(preceded(FROM, ID)) { Import (n, m) }
  | DIM ns = separated_nonempty_list(COMMA, dimname) { DimBase ns }
  | UNIT us = separated_nonempty_list(COMMA, unitdecl) { Units us }
  | CONST cs = separated_nonempty_list(COMMA, constdecl) { ConstDecl cs }
  | COMPUTE n = ID EQ e = expr u = option(preceded(IN, dexpr)) d = option(preceded(DIGITS, NUM))
    { Compute (Some n, e, u, Option.map Q.to_int d) }
  | COMPUTE e = expr u = option(preceded(IN, dexpr)) d = option(preceded(DIGITS, NUM))
    { Compute (None, e, u, Option.map Q.to_int d) }
  | DIAGRAM n = ID COLON items = list(ditem) END { Diagram (n, items) }
  | GROUPS n = ID COLON t = ID FROM xs = separated_nonempty_list(COMMA, ID) { Groups (n, Some t, xs) }
  | GROUPS n = ID COLON xs = separated_nonempty_list(COMMA, ID) { Groups (n, None, xs) }
  | SIMULATE n = ID COLON laws = separated_nonempty_list(COMMA, satom) FOR xs = separated_nonempty_list(COMMA, ID)
    FROM t = ID EQ a = expr TO b = expr WITH ics = separated_nonempty_list(COMMA, equation)
    p = option(preceded(POINTS, NUM))
    { Simulate { sname = n; laws; unknowns = xs; over = t; t0 = a; t1 = b; initial = ics; points = Option.map Q.to_int p } }
  | DIM n = ID EQ d = dexpr { DimAlias (n, d) }
  | VAR ns = separated_nonempty_list(COMMA, vname) COLON d = dexpr attrs = list(preceded(COMMA, attr))
    { VarDecl (ns, d, attrs) }
  | DEF n = ID LPAREN ps = separated_list(COMMA, param) RPAREN EQ body = expr
    { Def (n, ps, body) }
  | LAW n = ID COLON l = expr EQ r = expr { Law (n, { lhs = l; rhs = r }) }
  | DERIVE n = ID COLON steps = list(step) END { Derive (n, steps) }

(* dim Time (T): T is how Time is shown *)
dimname:
  | n = ID { (n, None) }
  | n = ID LPAREN s = ID RPAREN { (n, Some s) }

(* const g = 9.81 [m/s^2], n = 1.33 *)
constdecl:
  | n = ID EQ q = signed { (n, q, DOne) }
  | n = ID EQ q = signed LBRACK u = dexpr RBRACK { (n, q, u) }

signed:
  | q = NUM { q }
  | MINUS q = NUM { Q.neg q }

unitdecl:
  | n = ID COLON d = dexpr { (n, UBase d) }
  | n = ID EQ d = dexpr { (n, UDerived d) }

(* x(t) declares that x depends on t *)
vname:
  | n = ID { (n, []) }
  | n = ID LPAREN ds = separated_nonempty_list(COMMA, ID) RPAREN { (n, ds) }

(* vector(2) is kept as the string "vector(2)" *)
attr:
  | a = ID { a }
  | a = ID LPAREN n = NUM RPAREN { a ^ "(" ^ Q.to_string n ^ ")" }

param:
  | n = ID { (n, None) }
  | n = ID COLON d = dexpr { (n, Some d) }

(* ---- dimensions ---- *)

dexpr:
  | a = dexpr STAR b = dterm { DMul (a, b) }
  | a = dexpr SLASH b = dterm { DDiv (a, b) }
  | t = dterm { t }

dterm:
  | a = datom { a }
  | a = datom CARET q = rat { DPow (a, q) }

datom:
  | n = ID { DName n }
  | q = NUM { if Q.equal q Q.one then DOne else DNum q }
  | LPAREN d = dexpr RPAREN { d }

rat:
  | q = NUM { q }
  | MINUS q = NUM { Q.neg q }
  | LPAREN r = srat RPAREN { r }

srat:
  | q = NUM { q }
  | MINUS q = NUM { Q.neg q }
  | a = NUM SLASH b = NUM { Q.div a b }
  | MINUS a = NUM SLASH b = NUM { Q.neg (Q.div a b) }

(* ---- derivations ---- *)

step:
  | n = ID ASSIGN s = sexpr { { name = Some n; body = s; sline = $startpos.Lexing.pos_lnum } }
  | s = sexpr { { name = None; body = s; sline = $startpos.Lexing.pos_lnum } }

sexpr:
  | SOLVE ss = separated_nonempty_list(COMMA, satom) FOR xr = unknowns t = solve_tail
    { match (t, ss, xr) with
      | `Ics ics, _, (xs, r) -> Solve (ss, xs, Option.map Q.to_int r, ics)
      | `Near (g, d), [ s ], ([ x ], None) -> NSolve (s, x, g, Option.map Q.to_int d)
      | `Near _, _, _ -> raise (Syntax_error "`solve ... numerically` takes one equation and one unknown") }
  | SUBST a = satom INTO b = satom { Subst (a, b) }
  | SIMPLIFY s = satom { Simplify s }
  | UNFOLD s = satom { Unfold s }
  | EXPAND s = satom { Expand s }
  | DIFFERENTIATE s = satom BY x = ID { Differentiate (s, x) }
  | EVALUATE s = satom u = option(preceded(IN, dexpr)) d = option(preceded(DIGITS, NUM))
    { Evaluate (s, u, Option.map Q.to_int d) }
  | APPROXIMATE s = satom WHERE smalls = separated_nonempty_list(COMMA, small) o = option(preceded(ORDER, NUM))
    { Approximate (s, smalls, Option.map Q.to_int o) }
  | LIMIT s = satom AS x = ID ARROW p = expr { Limit (s, x, p) }

  | APPLY f = ID TO s = satom { Apply (f, s) }
  | INTEGRATE s = satom BY x = ID FROM a = expr TO b = expr { Integrate (s, x, a, b) }
  | COMPONENT c = comp OF s = satom { Component (s, fst c, snd c) }
  | s = satom { s }

satom:
  | q = qid { Ref (fst q, snd q) }
  | q = qid LBRACK subs = separated_nonempty_list(COMMA, binding) RBRACK
    { Inst (Ref (fst q, snd q), subs) }
  | LPAREN s = sexpr RPAREN { s }
  | LPAREN s = sexpr RPAREN LBRACK subs = separated_nonempty_list(COMMA, binding) RBRACK
    { Inst (s, subs) }

qid:
  | n = ID { (None, n) }
  | t = ID DOT n = ID { (Some t, n) }

comp:
  | c = ID { match component_index c with Some k -> (k, c) | None -> raise (Syntax_error ("unknown component `" ^ c ^ "`: use x, y, z or a number")) }
  | n = NUM { let c = Q.to_string n in match component_index c with Some k -> (k, c) | None -> raise (Syntax_error "components are numbered from 1") }

ditem:
  | BODY m = expr { Body m }
  | FORCE n = ID m = option(preceded(EQ, expr)) TOWARD d = expr { Force (n, m, d) }
  | ACCELERATES a = expr d = option(preceded(TOWARD, expr)) { Accelerates (a, d) }
  | PLANE d = expr { Plane d }
  | DRAW bs = separated_nonempty_list(COMMA, dbinding) { Draw bs }
  | MARK l = expr BETWEEN a = mark_end AND b = mark_end { Mark (l, a, b) }

(* a force's name, a, plane, or a direction; `plane` is a keyword, so spelled out here *)
mark_end:
  | PLANE { Var "plane" }
  | e = expr { e }

dbinding:
  | x = ID EQ e = expr { (x, e) }

(* with x(0) = x0, ...; or numerically near 2 [s] *)
solve_tail:
  | ics = loption(preceded(WITH, separated_nonempty_list(COMMA, equation))) { `Ics ics }
  | NUMERICALLY NEAR g = expr d = option(preceded(DIGITS, NUM)) { `Near (g, d) }

(* x, y, root 2: after a comma, `root` or a name decides which *)
unknowns:
  | x = ID { ([ x ], None) }
  | x = ID COMMA ROOT n = NUM { ([ x ], Some n) }
  | x = ID COMMA rest = unknowns { (x :: fst rest, snd rest) }

(* v << c: v is small compared with c *)
small:
  | x = ID MUCHLESS e = expr { (x, e) }

equation:
  | l = expr EQ r = expr { { lhs = l; rhs = r } }

binding:
  | x = ID ASSIGN e = expr { (x, e) }

(* ---- expressions ---- *)

expr:
  | q = NUM { Num q }
  | q = NUM LBRACK u = dexpr RBRACK { Quantity (q, u) }
  | x = ID %prec below_LPAREN { if List.mem x [ "pi"; "im"; "inf" ] then Const x else Var x }
  | f = ID LPAREN args = separated_list(COMMA, expr) RPAREN { Call (f, args) }
  | LPAREN e = expr RPAREN { e }
  | a = expr PLUS b = expr { Add (a, b) }
  | a = expr MINUS b = expr { Sub (a, b) }
  | a = expr STAR b = expr { Mul (a, b) }
  | a = expr SLASH b = expr { Div (a, b) }
  | a = expr CARET b = expr { Pow (a, b) }
  | MINUS a = expr %prec UMINUS { Neg a }
  | a = expr DOT k = comp { Call ("comp", [ a; Num (Q.of_int (fst k)) ]) }
