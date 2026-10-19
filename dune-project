(lang dune 3.0)
(using menhir 2.1)

(package
 (name landau)
 (synopsis "Physics as definitions, laws and derivations, with dimension checking and SymPy")
 (depends ocaml dune menhir zarith yojson))
