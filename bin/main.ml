let () =
  (Landau.Check.same_file_hook :=
     fun a b ->
       try
         let sa = Unix.stat a and sb = Unix.stat b in
         sa.st_dev = sb.st_dev && sa.st_ino = sb.st_ino
       with Unix.Unix_error _ -> a = b);
  (Landau.Check.realpath_hook := fun d -> try Unix.realpath d with Unix.Unix_error _ -> d);
  let verbose = ref false and json = ref false and files = ref [] in
  Arg.parse
    [ ("-v", Arg.Set verbose, " show every step of each derivation");
      ("--json", Arg.Set json, " print the report as JSON (for the web frontend)");
      ("--modules", Arg.String (fun d -> Landau.Check.extra_module_dirs := !Landau.Check.extra_module_dirs @ [ d ]),
       "DIR also look for imported modules in DIR");
      ("--as", Arg.String (fun f -> Landau.Check.stdin_as := Some f), "FILE the source on stdin is FILE (for its imports)");
      ("-", Arg.Unit (fun () -> files := "-" :: !files), " read a file from stdin") ]
    (fun f -> files := f :: !files)
    "usage: landau [-v] [--json] file.lan ...   (use - to read stdin)";
  if !files = [] then (
    prerr_endline "usage: landau [-v] [--json] file.lan ...   (use - to read stdin)";
    exit 2);
  let run f = if !json then Landau.Check.run_file_json f else Landau.Check.run_file ~verbose:!verbose f in
  let ok = List.fold_left (fun ok f -> run f && ok) true (List.rev !files) in
  exit (if ok then 0 else 1)
