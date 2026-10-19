Free-body diagrams and angle marks; the wrong mark is rejected.

  $ landau cases/diagrams/diagrams.lan
  theory Incline
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var α, μ : 1, positive
    var N, f : N   [M*L/T^2]
    var a : m/s^2   [L/T^2]
    diagram sliding : vec(-m*a*cos(α), -m*a*sin(α)) = vec(-N*sin(α) + μ*N*cos(α), -m*g + N*cos(α) + μ*N*sin(α))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force N = N toward (-0.479, 0.878)
        force f = μ*N toward (0.878, 0.479)
    derive acceleration : a = g*(-μ*cos(α) + sin(α))   [L/T^2]
        from    Incline.sliding
        assumes m > 0, α > 0, μ > 0, g > 0
        via     component x, component y, solve for a, N
    derive normal : N = m*g*cos(α)   [M*L/T^2]
        from    Incline.sliding
        assumes m > 0, α > 0, μ > 0, g > 0
        via     component x, component y, solve for N, a
  
  theory Hanging
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var T1, T2 : N   [M*L/T^2]
    var β : 1, positive
    diagram knot : 0 = vec(-T1*cos(β) + T2*cos(β), -m*g + T1*sin(β) + T2*sin(β))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force T1 = T1 toward (-0.825, 0.565)
        force T2 = T2 toward (0.825, 0.565)
    derive tension : T1 = m*g/(2*sin(β))   [M*L/T^2]
        from    Hanging.knot
        assumes β > 0, m > 0, g > 0
        via     component x, component y, solve for T1, T2
  
  theory Bad
    import SI
    var m : kg   [M]
    var g : m/s^2   [L/T^2]
    var v : m/s   [L/T]
    var θ : 1
  cases/diagrams/diagrams.lan:57: error: force `P` is [M*L/T], but force `W` is [M*L/T^2]
  cases/diagrams/diagrams.lan:62: error: a direction is a vector, such as `up`, `angle(α)` or `vec(1, 1)`, but `3` is not
  cases/diagrams/diagrams.lan:66: error: the diagram `b3` needs a `body m` line, with its mass
    diagram b4 : 0 = vec(m*g*cos(θ), m*g*sin(θ))   [2-vector M*L/T^2]
        force W = m*g toward (not drawn)
  
  [1]

  $ landau cases/diagrams/marks.lan
  theory Incline
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var α, μ : 1, positive
    var N : N   [M*L/T^2]
    var a : m/s^2   [L/T^2]
    diagram sliding : vec(-m*a*cos(α), -m*a*sin(α)) = vec(-N*sin(α) + μ*N*cos(α), -m*g + N*cos(α) + μ*N*sin(α))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force N = N toward (-0.479, 0.878)
        force f = μ*N toward (0.878, 0.479)
  cases/diagrams/marks.lan:19: error: the angle between N and right is 2.071 rad (118.6°) with the drawing values, but `α` is 0.5 rad (28.6°)
  
  theory Knot
    import SI
    var m : kg   [M], positive
    var g : m/s^2   [L/T^2], positive
    var T1, T2 : N   [M*L/T^2]
    var β : 1, positive
    diagram hanging : 0 = vec(-T1*cos(β) + T2*cos(β), -m*g + T1*sin(β) + T2*sin(β))   [2-vector M*L/T^2]
        force W = m*g toward (0, -1)
        force T1 = T1 toward (-0.825, 0.565)
        force T2 = T2 toward (0.825, 0.565)
  
  [1]
