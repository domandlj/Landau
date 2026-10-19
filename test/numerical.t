simulate: what it rejects, with the user's names in the messages.

  $ landau cases/numerical/simulate_errors.lan
  theory E
    import SI
    const g = 9.81 [m/s^2]   [L/T^2]
    var t : s   [T]
    var x(t) : m   [L]
    var y : m   [L]
    var k : 1/s^2   [1/T^2]
    var z(t) : m   [L]
    law fall : diff(diff(x, t), t) = -g   [L/T^2]
    law spring : diff(diff(x, t), t) = -k*x   [L/T^2]
    law alg : z = 2*x   [L]
  cases/numerical/simulate_errors.lan:12: error: an initial value is needed for the first derivative of x at the start
  cases/numerical/simulate_errors.lan:13: error: `at(diff(diff(x, t), t), t, 0) = 0 [m/s^2]` is not needed: x appears differentiated at most 2 time(s)
  cases/numerical/simulate_errors.lan:14: error: give values for `k`: put them in with `law[g := 9.81 [m/s^2]]`, or declare them with `const`
  cases/numerical/simulate_errors.lan:15: error: `y` must depend on t alone: declare it as `var y(t) : ...`
  cases/numerical/simulate_errors.lan:16: error: the initial value `x(1 [s]) = 0 [m]` is not at the start, t = 0 [s]
  cases/numerical/simulate_errors.lan:17: error: the end, 0 [s], must come after the start, 2 [s]
  cases/numerical/simulate_errors.lan:18: error: the two sides have different dimensions: `t` is [T] but `2 [m]` is [L]
  cases/numerical/simulate_errors.lan:19: error: `z` is never differentiated by t in these equations
  cases/numerical/simulate_errors.lan:20: error: the two sides have different dimensions: `x(0)` is [L] but `0 [s]` is [T]
  
  [1]
