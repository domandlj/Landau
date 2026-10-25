The JSON report the web app reads is valid JSON for every module, and says
whether the file checked.

  $ for m in ../modules/*.lan; do landau --json $m | python3 -c 'import json, sys; r = json.load(sys.stdin); print(sys.argv[1], r["ok"])' $(basename $m); done
  approximations.lan True
  constant_force.lan True
  derivatives.lan True
  dimensional.lan True
  energy.lan True
  errors.lan False
  forces.lan True
  integrals.lan True
  lagrange.lan True
  landau.lan True
  matrices.lan True
  maxwell.lan True
  motion.lan True
  numbers.lan True
  numerical.lan True
  projectile.lan True
  quantum.lan True
  series.lan True
  systems.lan True
  units.lan True
  work.lan True
