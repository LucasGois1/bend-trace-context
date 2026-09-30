# Proofs: the driver of the generation machines
# =============================================
#
# Drive in trace_context.bend runs the three machines of generation: a trace
# ID draw (TraceStep, fed by TraceDraw.next), a span ID draw (SpanStep, fed
# by SpanDraw.next) and a generation (Step, fed by Draw.feed). Each machine
# gives the driver, as templates, `waiting`, the draw that a step feeds its
# next word to while it waits for one, and `feed`, the step after that word,
# and the driver keeps each step beside its view, what `waiting` says of it.
# The lemmas below hold of every machine, over tapes, and are proved once;
# proofs/separate.bend and proofs/generation.bend instantiate them:
#
# - Termination. Within(view, n) says that a machine whose step has the view
#   `view` ends within n more words, whatever they are. drive_ends turns a
#   bound equal to the fuel into Drive.ended for every tape, given `fails`,
#   the machine's proof that a source error ends it at once; within_plus
#   loosens a bound.
# - Invariants. Holds(p, step, view) says that a step keeps an invariant with
#   the parameter `p`: Final(p, step), what the invariant says of the step
#   once it has ended, and, while it waits, Pending(p, draw) of its draw.
#   When every word result keeps it (`kept`), drive_keeps shows that the
#   final step of every drive has Final.
# - IO. drive_read shows that Drive.read over Source.tape computes Drive.run,
#   whatever function of the outcome the continuation emits, and drive_same
#   that two continuations that agree on every outcome make Drive.read give
#   the same. The tape is linear, so each induction reads it once, and the
#   two cannot be joined by Equal.trans.
#
# The statements use Tape of LAWS.bend.

import Base
import ../trace_context.bend as TC
import ../LAWS.bend as Laws

# Termination
# ===========

# The claim "a machine whose step has the view `view` ends within n more
# words, whatever they are", as a type: Unit for an ended step (None{}),
# Empty for a waiting one when n is 0, and otherwise, for every word, the
# bound n - 1 of the step that feeding the word gives (`@word: U32 -> ...` is
# a function type, so such a proof is a function of the word). Only
# successful words count: a source error ends every machine at once, which
# drive_ends takes as `fails`.
def Within(~T: Data, ~D: Data, ~waiting: T -> Maybe<&2, D>, ~feed: Result<&1, &1, U32 & String, U32> -> D -> T,
  view: Maybe<&2, D>, n: Nat) -> Type:
  match view n:
    case None{} _:
      Unit
    case Some{draw} 0n:
      Empty
    case Some{draw} 1n+p:
      @word: U32 -> Within(~T, ~D, ~waiting, ~feed, waiting(feed(Done{word}, draw)), p)

# An ended step ends within any number of words: when `view` is None{}
# (`ended`), the bound is Unit. drive_ends uses it after a source error.
law ended_within:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for -view: Maybe<&2, D>
  for n: Nat
  for ended: {view == None{} : Maybe<&2, D>}
  Within(~T, ~D, ~waiting, ~feed, view, n)

def ended_within(T, D, waiting, feed, view, n, ended):
  %Equal.sym(Maybe<&2, D>, view, None{}, ended) : Within(~T, ~D, ~waiting, ~feed, _, n)
  Unit{}

# A bound can be loosened by any number of words: a step that ends within m
# words ends within m + n. Induction on m. proofs/generation.bend uses it for
# a trace ID drawn before its draw's bound was reached.
law within_plus:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for +m: Nat
  for +n: Nat
  for view: Maybe<&2, D>
  for bound: Within(~T, ~D, ~waiting, ~feed, view, m)
  Within(~T, ~D, ~waiting, ~feed, view, Nat.add(m, n))

def within_plus(T, D, waiting, feed, m, n, view, bound):
  match m view:
    case _ None{}:
      Unit{}
    case 0n Some{draw}:
      Empty.absurd(Within(~T, ~D, ~waiting, ~feed, Some{draw}, Nat.add(0n, n)), bound)
    case 1n+p Some{+draw}:
      +word => within_plus(~T, ~D, ~waiting, ~feed, p, n, waiting(feed(Done{word}, draw)), bound(word))

# Driving a machine with enough fuel ends it, whatever the tape holds: when
# the step, whose view is `view` (`same`), ends within `fuel` words
# (`bound`), Drive.run with that fuel returns an ended step. `fails` is the
# machine's proof that a source error ends it at once. Induction on the fuel
# along the tape: a word uses the bound at that word, and an error, the end
# of the tape included, ends the step, which stays ended.
law drive_ends:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for ~fails: @draw: D -> @code: U32 -> @message: String ->
    {waiting(feed(Fail{(code, message)}, draw)) == None{} : Maybe<&2, D>}
  for +fuel: Nat
  for +step: T
  for view: Maybe<&2, D>
  for same: {waiting(step) == view : Maybe<&2, D>}
  for bound: Within(~T, ~D, ~waiting, ~feed, view, fuel)
  for tape: Laws.Tape()
  {TC.Drive.ended(~T, ~D, ~waiting, TC.Drive.run(~T, ~D, ~waiting, ~feed, fuel, (tape, (step, view)))) == True{} :
    Bool}

# The ended cases rewrite Drive.ended's view of the step into None{}.
def drive_ends(T, D, waiting, feed, fails, fuel, step, view, same, bound, tape):
  match fuel view:
    case 0n None{}:
      %Equal.sym(Maybe<&2, D>, waiting(step), None{}, same) : {Maybe.is_none(&2, D, _) == True{} : Bool}
      {==}
    case 0n Some{draw}:
      Empty.absurd({TC.Drive.ended(~T, ~D, ~waiting, TC.Drive.run(~T, ~D, ~waiting, ~feed, 0n,
        (tape, (step, Some{draw})))) == True{} : Bool}, bound)
    case 1n+p None{}:
      %Equal.sym(Maybe<&2, D>, waiting(step), None{}, same) : {Maybe.is_none(&2, D, _) == True{} : Bool}
      {==}
    case 1n+p Some{+draw}:
      match tape:
        case Nil{}:
          drive_ends(~T, ~D, ~waiting, ~feed, ~fails, p, feed(Fail{(1, "tape-exhausted")}, draw),
            waiting(feed(Fail{(1, "tape-exhausted")}, draw)), {==},
            ended_within(~T, ~D, ~waiting, ~feed, waiting(feed(Fail{(1, "tape-exhausted")}, draw)), p,
              fails(draw, 1, "tape-exhausted")), Nil{})
        case Con{Fail{(+code, +message)}, rest}:
          drive_ends(~T, ~D, ~waiting, ~feed, ~fails, p, feed(Fail{(code, message)}, draw),
            waiting(feed(Fail{(code, message)}, draw)), {==},
            ended_within(~T, ~D, ~waiting, ~feed, waiting(feed(Fail{(code, message)}, draw)), p,
              fails(draw, code, message)), rest)
        case Con{Done{+next}, rest}:
          drive_ends(~T, ~D, ~waiting, ~feed, ~fails, p, feed(Done{next}, draw), waiting(feed(Done{next}, draw)),
            {==}, bound(next), rest)

# Invariants
# ==========

# The claim that a machine's step keeps an invariant with the parameter `p`:
# Final(p, step), what the invariant says of the step once it has ended, and,
# while the step waits for a word (`view` Some{draw}), Pending(p, draw) of the
# draw that it feeds. Final says nothing of a waiting step in the machines of
# the package, so its proof is then Unit{}.
def Holds(~T: Data, ~D: Data, ~P: Data, ~Final: P -> T -> Type, ~Pending: P -> D -> Type, +p: P, step: T,
  view: Maybe<&2, D>) -> Type:
  match view:
    case None{}:
      Final(p, step)
    case Some{draw}:
      Final(p, step) & Pending(p, draw)

# The view of Drive.run's result: Final of its final step, the unread tape
# ignored. A law about the step that a drive ends with rewrites its
# hypothesis {run == (rest, step)} through Ends, which turns its conclusion
# into Ends of the drive, proved by drive_keeps.
def Ends(~T: Data, ~P: Data, ~Final: P -> T -> Type, p: P, result: Laws.Tape() & T) -> Type:
  match result:
    case Tuple{tape, step}:
      Final(p, step)

# When a step keeps an invariant (`valid`) and every word result keeps it
# (`kept`: from Pending of a draw, the step after any word keeps it), the
# final step of Drive.run has Final, for every fuel and every tape.
# Induction on the fuel: a drive that stops has the step it was given, and
# otherwise it goes on from the step after the tape's next word.
law drive_keeps:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for ~P: Data
  for ~Final: P -> T -> Type
  for ~Pending: P -> D -> Type
  for ~kept: @+p: P -> @draw: D -> @valid: Pending(p, draw) -> @word: Result<&1, &1, U32 & String, U32> ->
    Holds(~T, ~D, ~P, ~Final, ~Pending, p, feed(word, draw), waiting(feed(word, draw)))
  for +p: P
  for +fuel: Nat
  for step: T
  for view: Maybe<&2, D>
  for tape: Laws.Tape()
  for valid: Holds(~T, ~D, ~P, ~Final, ~Pending, p, step, view)
  Ends(~T, ~P, ~Final, p, TC.Drive.run(~T, ~D, ~waiting, ~feed, fuel, (tape, (step, view))))

def drive_keeps(T, D, waiting, feed, P, Final, Pending, kept, p, fuel, step, view, tape, valid):
  match fuel view:
    case 0n None{}:
      valid
    case 0n Some{draw}:
      (final, pending) = valid
      final
    case 1n+q None{}:
      valid
    case 1n+q Some{+draw}:
      match tape:
        case Nil{}:
          (final, pending) = valid
          drive_keeps(~T, ~D, ~waiting, ~feed, ~P, ~Final, ~Pending, ~kept, p, q,
            feed(Fail{(1, "tape-exhausted")}, draw), waiting(feed(Fail{(1, "tape-exhausted")}, draw)), Nil{},
            kept(p, draw, pending, Fail{(1, "tape-exhausted")}))
        case Con{Fail{(+code, +message)}, rest}:
          (final, pending) = valid
          drive_keeps(~T, ~D, ~waiting, ~feed, ~P, ~Final, ~Pending, ~kept, p, q, feed(Fail{(code, message)}, draw),
            waiting(feed(Fail{(code, message)}, draw)), rest, kept(p, draw, pending, Fail{(code, message)}))
        case Con{Done{+next}, rest}:
          (final, pending) = valid
          drive_keeps(~T, ~D, ~waiting, ~feed, ~P, ~Final, ~Pending, ~kept, p, q, feed(Done{next}, draw),
            waiting(feed(Done{next}, draw)), rest, kept(p, draw, pending, Done{next}))

# The IO driver over a tape
# =========================

# Over a tape, the IO driver computes what the pure driver computes: running
# Drive.read over Source.tape, followed by a continuation that emits a
# function `f` of the driver's outcome, gives what any `g` that agrees with
# `f` on every outcome (`same`) emits for the outcome of Drive.run, the same
# words read in the same order. Since an IO action is a function of a result
# type and a continuation (IO in Base), this says how Drive.read behaves
# inside a larger action. The induction applies `same` once, to the outcome
# the tape leads to, so the tape, which is linear, is read once.
law drive_read:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for -A: Type
  for -f: Laws.Tape() & T -> A
  for -g: Laws.Tape() & T -> A
  for same: @done: Laws.Tape() & T -> {f(done) == g(done) : A}
  for +fuel: Nat
  for current: Laws.Tape() & (T & Maybe<&2, D>)
  {TC.Drive.read(~T, ~D, ~waiting, ~feed, ~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, done => Emit{f(done)}) ==
    Emit{g(TC.Drive.run(~T, ~D, ~waiting, ~feed, fuel, current))} : IO.OP<A>}

# Splits on the fuel and the view: the drivers compute only once both are
# known. An ended step or an empty fuel emits at once, and a word is fed
# otherwise.
def drive_read(T, D, waiting, feed, A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, Tuple{step, None{}}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, step)), g((tape, step)), same((tape, step)))
    case 0n Tuple{tape, Tuple{step, Some{draw}}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, step)), g((tape, step)), same((tape, step)))
    case 1n+p Tuple{tape, Tuple{step, None{}}}:
      Equal.cong(A, IO.OP<A>, value => Emit{value}, f((tape, step)), g((tape, step)), same((tape, step)))
    case 1n+p Tuple{tape, Tuple{step, Some{draw}}}:
      drive_read(~T, ~D, ~waiting, ~feed, A, f, g, same, p,
        TC.Drive.fed(~T, ~D, ~waiting, ~feed, Laws.Tape(), TC.Tape.next(tape), draw))

# Two continuations `f` and `g` make Drive.read over Source.tape give the
# same whenever they agree on every outcome (`same`). Induction on the fuel,
# as drive_read, whose body it repeats: the tape is linear, so this cannot be
# two uses of drive_read joined by Equal.trans. proofs/separate.bend uses it
# for the compositions of root, child and restart generation, and
# proofs/http.bend, through read_tape_same, for an adapter that follows the
# package's operation with its own translation.
law drive_same:
  for ~T: Data
  for ~D: Data
  for ~waiting: T -> Maybe<&2, D>
  for ~feed: Result<&1, &1, U32 & String, U32> -> D -> T
  for -A: Type
  for -f: Laws.Tape() & T -> IO.OP<A>
  for -g: Laws.Tape() & T -> IO.OP<A>
  for same: @done: Laws.Tape() & T -> {f(done) == g(done) : IO.OP<A>}
  for +fuel: Nat
  for current: Laws.Tape() & (T & Maybe<&2, D>)
  {TC.Drive.read(~T, ~D, ~waiting, ~feed, ~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, f) ==
    TC.Drive.read(~T, ~D, ~waiting, ~feed, ~Laws.Tape(), ~TC.Source.tape, fuel, current)(A, g) : IO.OP<A>}

def drive_same(T, D, waiting, feed, A, f, g, same, fuel, current):
  match fuel current:
    case 0n Tuple{tape, Tuple{step, None{}}}:
      same((tape, step))
    case 0n Tuple{tape, Tuple{step, Some{draw}}}:
      same((tape, step))
    case 1n+p Tuple{tape, Tuple{step, None{}}}:
      same((tape, step))
    case 1n+p Tuple{tape, Tuple{step, Some{draw}}}:
      drive_same(~T, ~D, ~waiting, ~feed, A, f, g, same, p,
        TC.Drive.fed(~T, ~D, ~waiting, ~feed, Laws.Tape(), TC.Tape.next(tape), draw))
