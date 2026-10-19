Importing theories and module files, and what goes wrong: cycles, a theory
in two files, clashes, a module with errors, a module importing itself.
The search path in the "unknown module" message ends with Landau's own
modules directory, which depends on where Landau is; it is shown as <landau>.

  $ landau --modules ../modules cases/imports/uses.lan
  theory Uses
  cases/imports/uses.lan:2: error: a theory `Maxwell` is defined in maxwell.lan and maxwell.lan; say which one, as in `import Maxwell from maxwell`
  cases/imports/uses.lan:4: error: unknown law `gauss`
  
  theory UsesAtwood
  cases/imports/uses.lan:9: error: a theory `Atwood` is defined in clash.lan and forces.lan and systems.lan and forces.lan and systems.lan; say which one, as in `import Atwood from clash`
  cases/imports/uses.lan:11: error: unknown law `heavy`
  
  theory UsesKin
    import Kinematics from projectile
  
  theory WholeFile
  cases/imports/uses.lan:20: error: the theories of module systems clash when imported together (variable `m1` is already defined in ElasticCollision); import one of them: `import ElasticCollision from systems`, `import Atwood from systems`, `import Kirchhoff from systems`
  
  [1]

  $ landau cases/imports/cyca.lan
  theory A1
  cases/imports/cyca.lan:2: error: module cycb, line 2: modules import each other in a circle: cyca -> cycb -> cyca
  
  [1]

  $ landau --modules ../modules cases/imports/ambiguous.lan
  theory X
  cases/imports/ambiguous.lan:2: error: a theory `Kinematics` is defined in numbers.lan and projectile.lan and numbers.lan and projectile.lan; say which one, as in `import Kinematics from numbers`
  
  [1]

  $ landau cases/imports/missing.lan 2>&1 | sed -E 's|, /[^ ]*/modules$|, <landau>/modules|'
  theory Q
  cases/imports/missing.lan:2: error: unknown theory or module `nosuch`: a theory must be defined before it is imported, and module files are looked for in $TESTCASE_ROOT/cases/imports, <landau>/modules
  

  $ landau --modules ../modules cases/imports/clash.lan
  theory Atwood
  
  theory Z
  cases/imports/clash.lan:4: error: the module systems has a theory `Atwood`, and so does this file
  
  [1]

  $ landau --modules ../modules cases/imports/broken_module.lan
  theory W
  cases/imports/broken_module.lan:2: error: module errors, line 9: cannot add `v*t` [L] and `v` [L/T]
  
  [1]

  $ landau --modules ../modules cases/imports/wrong_from.lan
  theory P
  cases/imports/wrong_from.lan:2: error: the module systems has no theory `Kinematics`; it has ElasticCollision, Atwood, Kirchhoff
  
  [1]

  $ landau cases/imports/self_import.lan
  theory ZZ
  cases/imports/self_import.lan:2: error: a module cannot import itself
  
  [1]
