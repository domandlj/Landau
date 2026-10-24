(* Landau in the browser. Defines globalThis.landau:

     landau.setCas(f)            f(requestLine) answers a SymPy request line
                                 (cas/worker.py running in Pyodide)
     landau.addModule(name, src) a module file, for imports
     landau.check(src, module)   the JSON report, as `landau --json` prints it;
                                 module (or null) is the module being edited

   Module files live in js_of_ocaml's in-memory file system. *)

open Js_of_ocaml
open Landau

let dir = "/static/modules"
let path name = Printf.sprintf "%s/%s.lan" dir name

let () =
  Check.extra_module_dirs := [ dir ];
  let set_cas f = Cas.transport := Some (fun line -> Js.to_string (Js.Unsafe.fun_call f [| Js.Unsafe.inject (Js.string line) |])) in
  let add_module name src =
    let file = path (Js.to_string name) and content = Js.to_string src in
    if Sys.file_exists file then Sys_js.update_file ~name:file ~content else Sys_js.create_file ~name:file ~content
  in
  let check src modul =
    Check.stdin_as := Js.Opt.to_option (Js.Opt.map modul (fun m -> path (Js.to_string m)));
    Js.string (Yojson.Safe.to_string (Check.json_report ~source:(Js.to_string src) "-"))
  in
  Js.export "landau"
    (Js.Unsafe.obj
       [| ("setCas", Js.Unsafe.inject (Js.wrap_callback set_cas));
          ("addModule", Js.Unsafe.inject (Js.wrap_callback add_module));
          ("check", Js.Unsafe.inject (Js.wrap_callback check)) |])
