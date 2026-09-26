# Proofs: character and word comparison
# =====================================
#
# Base compares characters by their 32-bit codes: Char.is_eq(a, b) is
# Cmp.is_eq of Word.cmp(32n, x, y), where x and y are the bits of the two
# codes. This module proves that these comparisons are sound: a comparison
# that reports equality carries a proof that its operands are the same
# (word_view, char_view), and every word compares EQ with itself
# (word_cmp_refl). PROOF.bend does not call it directly; it is a foundation
# for other proof modules. proofs/strings.bend lifts it to String.eq
# (eq_view, eq_refl), proofs/hex.bend identifies decoded digits with
# char_view and proofs/parser.bend reads the "-" separator with it. differs,
# at the end, shows that a character a class accepts differs from one the
# class refuses; proofs/tracestate.bend and proofs/normal.bend use it for the
# separators and optional whitespace of tracestate.
#
# Strategy: views. WordView and CharView turn a comparison result into a
# type: Unit for an unequal result and the equality for an equal one.
# word_view proves the word view by induction on the width n, with word_step
# as the inductive step; char_step and char_view lift it to characters.
# word_cmp_refl is a plain induction on the width. The step lemmas exist
# because Bend matches only on parameters: the caller computes the
# comparison and passes it, together with its view, as arguments;
# differs_step does the same for differs.

import Base

# The view of a word comparison: what the result of Word.cmp(n, a, b) says
# about a and b. Unit (nothing) for LT and GT, and the equality
# {a == b : Word(n)} for EQ. word_view proves it for all words, so a
# comparison that reports EQ carries the equality of its operands.
def WordView(n: Nat, a: Word(n), b: Word(n), result: Cmp) -> Type:
  match result:
    case LT{}:
      Unit
    case EQ{}:
      {a == b : Word(n)}
    case GT{}:
      Unit

# The inductive step of word_view: when `tail` is the view of the comparison
# `result` of two tails at and bt, the view holds for the words that put the
# bits ab and bb in front, compared by Word.cmp.fin(ab, bb, result). Only an
# EQ result consults the two bits (the least significant ones); then equal
# bits give EQ, and the tails' equality rewrites one word into the other.
law word_step:
  for -p: Nat
  for -at: Word(p)
  for -bt: Word(p)
  for result: Cmp
  for tail: WordView(p, at, bt, result)
  for +ab: Bool
  for +bb: Bool
  WordView(1n+p, WCon{ab, at}, WCon{bb, bt}, Word.cmp.fin(ab, bb, result))

def word_step(p, at, bt, result, tail, ab, bb):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      match ab bb:
        case False{} False{}:
          %tail : {WCon{False{}, at} == WCon{False{}, _} : Word(1n+p)}
          {==}
        case False{} True{}:
          Unit{}
        case True{} False{}:
          Unit{}
        case True{} True{}:
          %tail : {WCon{True{}, at} == WCon{True{}, _} : Word(1n+p)}
          {==}
    case GT{}:
      Unit{}

# Every word comparison satisfies its view: when Word.cmp(n, a, b) reports
# EQ, a and b are the same word. Induction on the width n, the recursive
# call giving the view of the tails. Used by char_view below and by
# StringsProof.eq_view (proofs/strings.bend).
law word_view:
  for +n: Nat
  for a: Word(n)
  for b: Word(n)
  WordView(n, a, b, Word.cmp(n, a, b))

def word_view(n, a, b):
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          word_step(p, at, bt, Word.cmp(p, at, bt), word_view(p, at, bt), ab, bb)

# The view of a character comparison: Unit when `same` is False, and the
# equality {a == b : Char} when it is True. char_view proves it for
# `same` = Char.is_eq(a, b), so a True comparison carries the equality of
# the two characters.
def CharView(a: Char, b: Char, same: Bool) -> Type:
  match same:
    case False{}:
      Unit
    case True{}:
      {a == b : Char}

# Lifts the word view to characters: when `view` is the word view of the
# comparison `result` of two codes x and y, Cmp.is_eq(result) satisfies the
# character view of Chr{U32{x}} and Chr{U32{y}}. Char.is_eq of these two
# characters computes Cmp.is_eq(Word.cmp(32n, x, y)), which char_view
# passes as `result`.
law char_step:
  for -x: Word(32n)
  for -y: Word(32n)
  for result: Cmp
  for view: WordView(32n, x, y, result)
  CharView(Chr{U32{x}}, Chr{U32{y}}, Cmp.is_eq(result))

def char_step(x, y, result, view):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      %view : {Chr{U32{x}} == Chr{U32{_}} : Char}
      {==}
    case GT{}:
      Unit{}

# Every character comparison satisfies its view: when Char.is_eq(a, b) is
# True, a and b are the same character. Used by proofs/hex.bend (find_view),
# proofs/parser.bend (separator_view, for "-") and differs below.
law char_view:
  for a: Char
  for b: Char
  CharView(a, b, Char.is_eq(a, b))

def char_view(a, b):
  match a b:
    case Chr{U32{+x}} Chr{U32{+y}}:
      char_step(x, y, Word.cmp(32n, x, y), word_view(32n, x, y))

# Every word compares EQ with itself. Induction on the width n: the
# recursive call rewrites the tails' comparison to EQ, and Word.cmp.fin of
# two equal bits is then EQ. StringsProof.eq_refl (proofs/strings.bend) uses
# it for the code of each character.
law word_cmp_refl:
  for +n: Nat
  for w: Word(n)
  {Word.cmp(n, w, w) == EQ{} : Cmp}

def word_cmp_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{False{}, +tail}:
          %Equal.sym(Cmp, Word.cmp(p, tail, tail), EQ{}, word_cmp_refl(p, tail)) :
            {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
          {==}
        case WCon{True{}, +tail}:
          %Equal.sym(Cmp, Word.cmp(p, tail, tail), EQ{}, word_cmp_refl(p, tail)) :
            {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
          {==}

# When a class `f` accepts `char` and refuses `other`, any Bool `same` for
# which CharView(char, other, same) holds is False. The view holds
# {char == other : Char} when `same` is True; congruence then gives
# f(char) == f(other), and `holds` and `fails` chain into the goal, which is
# True == False itself. `differs` applies it to Char.is_eq(char, other), a
# computed value that `match` cannot inspect directly.
law differs_step:
  for -f: Char -> Bool
  for -char: Char
  for -other: Char
  for same: Bool
  for view: CharView(char, other, same)
  for holds: {f(char) == True{} : Bool}
  for fails: {f(other) == False{} : Bool}
  {same == False{} : Bool}

def differs_step(f, char, other, same, view, holds, fails):
  match same:
    case False{}:
      {==}
    case True{}:
      Equal.trans(Bool, True{}, f(char), False{}, Equal.sym(Bool, f(char), True{}, holds),
        Equal.trans(Bool, f(char), f(other), False{}, Equal.cong(Char, Bool, f, char, other, view), fails))

# A character a class accepts differs from every character the class refuses:
# when f(char) is True and f(other) is False, Char.is_eq(char, other) is False.
# Callers pass the class as a lambda, such as `x => TC.StateChar.is_key(x)`,
# and prove `fails` by {==} when `other` is a concrete character such as ','.
# proofs/tracestate.bend uses it for its separator and whitespace lemmas and
# read_entry_text, and proofs/normal.bend for key_separators,
# value_separators and whitespace.
law differs:
  for -f: Char -> Bool
  for +char: Char
  for +other: Char
  for holds: {f(char) == True{} : Bool}
  for fails: {f(other) == False{} : Bool}
  {Char.is_eq(char, other) == False{} : Bool}

def differs(f, char, other, holds, fails):
  differs_step(f, char, other, Char.is_eq(char, other), char_view(char, other), holds, fails)
