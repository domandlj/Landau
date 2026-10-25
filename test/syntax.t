A syntax error points at its line and column.

  $ landau cases/syntax/syntax_error.lan
  cases/syntax/syntax_error.lan:1:7: syntax error
  [1]

A text block runs to a line holding only `end` (a comment may follow it).
Inside it nothing is Landau: keywords and `--` are words. It loses its
common indentation and is shown where it is, also before any theory.

  $ landau cases/syntax/text.lan
    | Notes before any theory, with $x = v t$ and $$E = m c^2$$
  theory Notes
    dim L, T
    var x : L
    var t : T
    var text : L/T
    | Indented blocks lose their common indentation.
    |   Deeper lines keep the rest.
    | law, var, end and -- are just words in here; an end line with
    | something after it, like the next one, is text too:
    | end of the story
    law speed : text = x/t   [L/T]
    | After the law.
  

In the JSON report a block is an item of kind text, at the line of `text`.

  $ landau --json cases/syntax/text.lan | grep -o '"kind":"text","line":[0-9]*'
  "kind":"text","line":1
  "kind":"text","line":10
  "kind":"text","line":18

A block without its `end` is an error at the line where it starts. (Inside a
theory, the theory's own `end` closes the block, and the theory is left open.)

  $ landau cases/syntax/text_unclosed.lan
  cases/syntax/text_unclosed.lan:5:0: this `text` block has no `end` on a line of its own
  [1]

An empty block is allowed and shows nothing.

  $ printf 'text\n\nend\ndim L\n' | landau -
    dim L
