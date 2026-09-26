# Proofs: strings, lengths and equality
# =====================================
#
# General facts about Base's strings: the length of a concatenation
# (append_length, joined_length), the empty string and the grouping of `++`
# (append_nil, string_assoc), double reversal (reverse_twice), and the
# soundness of String.eq: every string equals itself (eq_refl), a True
# comparison proves equality (eq_view, eq_sound) and a False one proves
# difference (distinct). Many proof modules build on it.
# Laws.formatted_length (PROOF.bend) uses joined_length. The ID reuse checks
# of the child and restart laws rely on eq_refl, eq_view and distinct, in
# proofs/lifecycle.bend and, for generated IDs, proofs/generation.bend.
# proofs/distinct.bend uses the equality lemmas for tracestate lookups;
# proofs/ids.bend, merge.bend and normal.bend use append_nil and
# string_assoc; proofs/tracestate.bend uses reverse_twice; and true_ne_false
# closes impossible cases in proofs/bools.bend, generation.bend and
# tracestate.bend.
#
# Strategy: the facts about `++` and reversal are inductions on the first
# string. The equality lemmas follow proofs/chars.bend: EqView is Unit for a
# False comparison and the equality for a True one, and eq_view proves it by
# induction on both strings, with eq_char_step and eq_tail_step as the step
# and compare_rest to pass from two strings to their rests. distinct derives
# True == False from eq_refl and refutes it with true_ne_false, which
# rewrites the clash through the motive BoolClash.

import Base
import ./chars.bend as CharsProof

# The length of a concatenation is the sum of the lengths. Induction on a,
# the string that `++` recurses on. Used by joined_length.
law append_length:
  for a: String
  for b: String
  {String.length(a ++ b) == Nat.add(String.length(a), String.length(b)) : Nat}

def append_length(a, b):
  match a:
    case SNil{}:
      {==}
    case SCon{head, tail}:
      %append_length(tail, b) :
        {1n+String.length(tail ++ b) == 1n+_ : Nat}
      {==}

# When a has n characters and b has m, a ++ b has n + m. The form of
# append_length with the lengths as hypotheses, so that it chains:
# Laws.formatted_length (PROOF.bend) adds up the pieces of a traceparent
# text this way, from the innermost outwards.
law joined_length:
  for a: String
  for b: String
  for n: Nat
  for m: Nat
  for a_length: {String.length(a) == n : Nat}
  for b_length: {String.length(b) == m : Nat}
  {String.length(a ++ b) == Nat.add(n, m) : Nat}

def joined_length(a, b, n, m, a_length, b_length):
  %b_length : {String.length(a ++ b) == Nat.add(n, _) : Nat}
  %a_length : {String.length(a ++ b) == Nat.add(_, String.length(b)) : Nat}
  append_length(a, b)

# Appending the empty string changes nothing. `++` recurses on its left
# operand, so this needs an induction on a. Used by proofs/ids.bend
# (id_end_step, id_roundtrip) and NormalProof.roundtrip (proofs/normal.bend),
# which view a text as that text followed by an empty rest.
law append_nil:
  for a: String
  {a ++ "" == a : String}

def append_nil(a):
  match a:
    case SNil{}:
      {==}
    case SCon{head, tail}:
      %append_nil(tail) : {SCon{head, tail ++ ""} == SCon{head, _} : String}
      {==}

# Putting two characters back in front of a comparison (String.cmp.rec)
# keeps the equality it reports: String.eq.fin reads only the Cmp, which
# String.cmp.rec passes on. When the first characters compare EQ, String.cmp
# continues this way, so comparing the rests decides the comparison of the
# whole strings. By computation, once `rest` is split into its parts. Used
# by eq_refl and eq_char_step.
law compare_rest:
  for -first: Char
  for -second: Char
  for rest: (String & String) & Cmp
  {String.eq.fin(String.cmp.rec(first, second, rest)) == String.eq.fin(rest) : Bool}

def compare_rest(first, second, rest):
  match rest:
    case ((left, right), result):
      {==}

# Every string is equal to itself by String.eq. Induction on the text. Used
# by distinct below, by proofs/lifecycle.bend (child_reuse, restart_reuse,
# where a reused ID is found equal) and by proofs/distinct.bend
# (eq_symmetric_step, get_first).
law eq_refl:
  for +text: String
  {String.eq(text, text) == True{} : Bool}

# The first codes compare EQ (word_cmp_refl); compare_rest moves to the tails.
def eq_refl(text):
  match text:
    case SNil{}:
      {==}
    case SCon{Chr{U32{+code}}, +tail}:
      %Equal.sym(Cmp, Word.cmp(32n, code, code), EQ{}, CharsProof.word_cmp_refl(32n, code)) :
        {String.eq.fin(String.cmp.fin(tail, tail, ((Chr{U32{code}}, Chr{U32{code}}), _))) == True{} : Bool}
      Equal.trans(Bool,
        String.eq.fin(String.cmp.rec(Chr{U32{code}}, Chr{U32{code}}, String.cmp(tail, tail))),
        String.eq.fin(String.cmp(tail, tail)), True{},
        compare_rest(Chr{U32{code}}, Chr{U32{code}}, String.cmp(tail, tail)), eq_refl(tail))

# The motive that refutes {True{} == False{}}: Empty for False and Unit for
# True. Rewriting with the clash turns the goal Empty, which is
# BoolClash(False{}), into BoolClash(True{}), which is Unit. Used by
# true_ne_false.
def BoolClash(value: Bool) -> Type:
  match value:
    case False{}:
      Empty
    case True{}:
      Unit

# True and False are different: an equation {True{} == False{}} yields
# Empty, the type without values, so a case that assumes it cannot happen.
# Used by distinct below, by proofs/bools.bend (absurd, or_right_false),
# GenerationProof.ended_stays (proofs/generation.bend) and
# StateProof.read_over (proofs/tracestate.bend).
law true_ne_false:
  for clash: {True{} == False{} : Bool}
  Empty

def true_ne_false(clash):
  %clash : BoolClash(_)
  Unit{}

# When String.eq(a, b) is False, a and b are different strings.
# `{a != b : String}` is a function from a proof of {a == b} to Empty, so
# the proof receives `same` and derives a contradiction. Used by
# proofs/lifecycle.bend (child_step, restart_step), proofs/generation.bend
# (span_distinct, trace_distinct) and DistinctProof.eq_symmetric_false.
law distinct:
  for +a: String
  for -b: String
  for different: {String.eq(a, b) == False{} : Bool}
  {a != b : String}

# From `same`: True == String.eq(a, a) == String.eq(a, b) == False, a clash.
def distinct(a, b, different):
  same => true_ne_false(Equal.trans(Bool, True{}, String.eq(a, b), False{},
    Equal.trans(Bool, True{}, String.eq(a, a), String.eq(a, b),
      Equal.sym(Bool, String.eq(a, a), True{}, eq_refl(a)),
      Equal.cong(String, Bool, x => String.eq(a, x), a, b, same)),
    different))

# The view of a string comparison: Unit when `same` is False, and the
# equality {a == b : String} when it is True. eq_view proves it for
# `same` = String.eq(a, b). proofs/lifecycle.bend also uses it
# (child_accepts_step, restart_accepts_step) to rule out a reuse check that
# reports equal texts when they are known to differ.
def EqView(a: String, b: String, same: Bool) -> Type:
  match same:
    case False{}:
      Unit
    case True{}:
      {a == b : String}

# The last part of the step of eq_view: when the first characters' codes wx
# and wy are equal (`char_view`) and `same` satisfies the view of the rests,
# `same` also satisfies the view of the whole strings. When `same` is True,
# the rests' equality and then the codes' equality rewrite one string into
# the other. Used by eq_char_step.
law eq_tail_step:
  for -wx: Word(32n)
  for -wy: Word(32n)
  for -left: String
  for -right: String
  for char_view: {wx == wy : Word(32n)}
  for same: Bool
  for tail_view: EqView(left, right, same)
  EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right}, same)

def eq_tail_step(wx, wy, left, right, char_view, same, tail_view):
  match same:
    case False{}:
      Unit{}
    case True{}:
      %tail_view : {SCon{Chr{U32{wx}}, left} == SCon{Chr{U32{wy}}, _} : String}
      %char_view : {SCon{Chr{U32{wx}}, left} == SCon{Chr{U32{_}}, left} : String}
      {==}

# The step of eq_view for two nonempty strings. `result` stands for the
# comparison of the first characters' codes, with `char_view` its word view,
# and `tail_view` is the view of the rests. The conclusion's last argument
# is what String.eq computes for the whole strings. For LT and GT it is
# False and the view is Unit; for EQ, compare_rest reduces it to String.eq
# of the rests, and eq_tail_step concludes.
law eq_char_step:
  for -wx: Word(32n)
  for -wy: Word(32n)
  for +left: String
  for +right: String
  for result: Cmp
  for char_view: CharsProof.WordView(32n, wx, wy, result)
  for tail_view: EqView(left, right, String.eq(left, right))
  EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right},
    String.eq.fin(String.cmp.fin(left, right, ((Chr{U32{wx}}, Chr{U32{wy}}), result))))

def eq_char_step(wx, wy, left, right, result, char_view, tail_view):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      %Equal.sym(Bool,
        String.eq.fin(String.cmp.rec(Chr{U32{wx}}, Chr{U32{wy}}, String.cmp(left, right))),
        String.eq.fin(String.cmp(left, right)),
        compare_rest(Chr{U32{wx}}, Chr{U32{wy}}, String.cmp(left, right))) :
        EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right}, _)
      eq_tail_step(wx, wy, left, right, char_view, String.eq(left, right), tail_view)
    case GT{}:
      Unit{}

# Every string comparison satisfies its view: when String.eq(a, b) is True,
# a and b are the same string. Induction on both strings, with
# CharsProof.word_view (proofs/chars.bend) for the first characters and
# eq_char_step as the step. Used by eq_sound and by proofs/lifecycle.bend
# (child_accepts, restart_accepts).
law eq_view:
  for +a: String
  for +b: String
  EqView(a, b, String.eq(a, b))

def eq_view(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{head, tail}:
      Unit{}
    case SCon{head, tail} SNil{}:
      Unit{}
    case SCon{Chr{U32{+wx}}, +left} SCon{Chr{U32{+wy}}, +right}:
      eq_char_step(wx, wy, left, right, Word.cmp(32n, wx, wy), CharsProof.word_view(32n, wx, wy),
        eq_view(left, right))

# When String.eq(a, b) is True, a and b are the same string: String.eq is
# sound. Used by proofs/distinct.bend (eq_symmetric_step,
# eq_symmetric_false), which shows that String.eq is symmetric.
law eq_sound:
  for +a: String
  for +b: String
  for same: {String.eq(a, b) == True{} : Bool}
  {a == b : String}

def eq_sound(a, b, same):
  %same : EqView(a, b, _)
  eq_view(a, b)

# Reversing twice gives the text back, stated for the accumulator of
# String.reverse.go(text, acc), which is text reversed followed by acc:
# reversing that gives acc reversed followed by text. With acc = "" it is
# String.reverse(String.reverse(text)) == text. Induction on text, with the
# accumulator growing. Used by proofs/tracestate.bend (read_entry_text,
# restore_reversed), whose reading machine keeps a value reversed.
law reverse_twice:
  for text: String
  for acc: String
  {String.reverse.go(String.reverse.go(text, acc), "") == String.reverse.go(acc, text) : String}

def reverse_twice(text, acc):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      reverse_twice(tail, SCon{char, acc})

# Concatenation is associative: (a ++ b) ++ c is a ++ (b ++ c), which is how
# `a ++ b ++ c` groups. Induction on a. Used by proofs/merge.bend
# (read_closed, read_state_then) and proofs/normal.bend (ows_after,
# read_rest_ows) to regroup the formatted text of a tracestate.
law string_assoc:
  for a: String
  for b: String
  for c: String
  {(a ++ b) ++ c == a ++ b ++ c : String}

def string_assoc(a, b, c):
  match a:
    case SNil{}:
      {==}
    case SCon{head, tail}:
      %string_assoc(tail, b, c) : {SCon{head, (tail ++ b) ++ c} == SCon{head, _} : String}
      {==}
