# Proofs: identifiers from source words
# =====================================
#
# Proves the laws of section 5 of LAWS.bend about IDs built from 32-bit
# words. TraceId.from_words and SpanId.from_words give the words' digits in
# the order the words were given (laws trace_words and span_words), a
# converted trace ID makes no randomness assertion (words_unasserted), and
# U32.to_hex loses no information (hex_injective). Laws.trace_words,
# Laws.span_words and Laws.words_unasserted in PROOF.bend rewrite their
# hypothesis into the views TraceWordsView, SpanWordsView and
# UnassertedCandidate; Laws.hex_injective calls hex_injective. The other law
# of section 5, word_hex, is proved in proofs/words.bend.
#
# Strategy: views. Each view is Unit for an all-zero candidate (None) and
# the law's claim for a built ID. Bend matches only on parameters, so the
# *_step lemmas receive the zero check of NonZero.new.checked as a Bool,
# with an equation that says what it is, and match on it; in the accepting
# case append_text splits the text of the appended digits into the texts of
# the words. hex_injective parses the common text back into each word's
# digits (ParserProof.digits_roundtrip) and turns equal digits into equal
# words (WordsProof.u32_roundtrip).

import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./parser.bend as ParserProof
import ./strings.bend as StringsProof
import ./words.bend as WordsProof
import ../src/hex.bend as Hex

# The text of two concatenated digit sequences is the concatenation of their
# texts: Digits.to_string of Digits.append(m, n, left, right) is the text of
# left followed by the text of right. Induction on m. Used by
# trace_words_step and span_words_step.
law append_text:
  for +m: Nat
  for -n: Nat
  for left: Digits.Digits(m)
  for right: Digits.Digits(n)
  {Digits.Digits.to_string(Nat.add(m, n), Digits.Digits.append(m, n, left, right)) ==
    Digits.Digits.to_string(m, left) ++ Digits.Digits.to_string(n, right) : String}

def append_text(m, n, left, right):
  match m:
    case 0n:
      match left:
        case Digits.DNil{}:
          {==}
    case 1n+p:
      match left:
        case Digits.DCon{head, tail}:
          %Equal.sym(String, Digits.Digits.to_string(Nat.add(p, n), Digits.Digits.append(p, n, tail, right)),
            Digits.Digits.to_string(p, tail) ++ Digits.Digits.to_string(n, right),
            append_text(p, n, tail, right)) : {SCon{Hex.Digit.to_char(head), _} ==
            SCon{Hex.Digit.to_char(head), Digits.Digits.to_string(p, tail) ++ Digits.Digits.to_string(n, right)} : String}
          {==}

# The view of a trace ID converted from four words: Unit for None (an
# all-zero candidate), and for Some{id} the claim of law trace_words: the
# ID's text is the eight digits of each word, in the order the words were
# given.
def TraceWordsView(first: U32, second: U32, third: U32, fourth: U32,
  candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.to_string(id) ==
        TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth) : String}

# The trace view holds for the candidate that NonZero.new.checked makes from
# the four words' 32 digits, whatever the zero check reported: `evidence`
# says that `status` is Digits.is_zero of those digits. When True, the
# candidate is None; when False, the ID's text is Digits.to_string of the
# appended digits.
law trace_words_step:
  for +first: U32
  for +second: U32
  for +third: U32
  for +fourth: U32
  for status: Bool
  for -evidence: {Digits.Digits.is_zero(32n, Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
    Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
      Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))) == status : Bool}
  TraceWordsView(first, second, third, fourth, TC.TraceId.from_digits(Digits.NonZero.new.checked(32n,
    Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
      Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
        Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth)))), status, evidence)))

# Three rewrites with append_text split the text of the 32 digits by word.
def trace_words_step(first, second, third, fourth, status, evidence):
  match status:
    case True{}:
      Unit{}
    case False{}:
      %Equal.sym(String,
        Digits.Digits.to_string(Nat.add(8n, 24n), Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
          Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
            Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))),
        TC.U32.to_hex(first) ++ Digits.Digits.to_string(24n, Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth)))),
        append_text(8n, 24n, Digits.Digits.of_u32(first), Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))) :
        {_ == TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth) : String}
      %Equal.sym(String,
        Digits.Digits.to_string(Nat.add(8n, 16n), Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth)))),
        TC.U32.to_hex(second) ++ Digits.Digits.to_string(16n,
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))),
        append_text(8n, 16n, Digits.Digits.of_u32(second),
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth)))) :
        {TC.U32.to_hex(first) ++ _ ==
          TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth) : String}
      %Equal.sym(String,
        Digits.Digits.to_string(Nat.add(8n, 8n),
          Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))),
        TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth),
        append_text(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))) :
        {TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ _ ==
          TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth) : String}
      {==}

# Every trace ID converted from four words satisfies the trace view.
# TraceId.from_words validates the appended digits with NonZero.new, which
# is NonZero.new.checked applied to the zero check, so trace_words_step with
# that check and {==} proves it. Laws.trace_words (PROOF.bend) rewrites its
# hypothesis into this view.
law trace_words_view:
  for +first: U32
  for +second: U32
  for +third: U32
  for +fourth: U32
  TraceWordsView(first, second, third, fourth, TC.TraceId.from_words(first, second, third, fourth))

def trace_words_view(first, second, third, fourth):
  trace_words_step(first, second, third, fourth,
    Digits.Digits.is_zero(32n, Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
      Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
        Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))), {==})

# The view of a span ID converted from two words: Unit for None (an all-zero
# candidate), and for Some{id} the claim of law span_words: the ID's text is
# the first word's eight digits followed by the second's.
def SpanWordsView(first: U32, second: U32, candidate: Maybe<&2, TC.SpanId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.SpanId.to_string(id) == TC.U32.to_hex(first) ++ TC.U32.to_hex(second) : String}

# The span view holds for the candidate made from the two words' 16 digits,
# whatever the zero check `status` reported (`evidence` says what it is).
# When False, append_text splits the ID's text into the two words' texts.
law span_words_step:
  for +first: U32
  for +second: U32
  for status: Bool
  for -evidence: {Digits.Digits.is_zero(16n, Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first),
    Digits.Digits.of_u32(second))) == status : Bool}
  SpanWordsView(first, second, TC.SpanId.from_digits(Digits.NonZero.new.checked(16n,
    Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second)), status, evidence)))

def span_words_step(first, second, status, evidence):
  match status:
    case True{}:
      Unit{}
    case False{}:
      append_text(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second))

# Every span ID converted from two words satisfies the span view:
# span_words_step with the zero check that SpanId.from_words computes and
# {==}. Laws.span_words (PROOF.bend) rewrites its hypothesis into this view.
law span_words_view:
  for +first: U32
  for +second: U32
  SpanWordsView(first, second, TC.SpanId.from_words(first, second))

def span_words_view(first, second):
  span_words_step(first, second, Digits.Digits.is_zero(16n,
    Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second))), {==})

# The view of a trace ID candidate without a randomness assertion: Unit for
# None, and for Some{id} the equation TraceId.is_random(id) == False{}, the
# claim of law words_unasserted. Converting words makes no such assertion.
def UnassertedCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == False{} : Bool}

# Every trace ID that TraceId.from_digits builds makes no randomness
# assertion, whatever the digits: it sets the random field to False. By case
# analysis on `value`. Used by words_unasserted.
law from_digits_unasserted:
  for value: Maybe<&2, Digits.NonZero<32n>>
  UnassertedCandidate(TC.TraceId.from_digits(value))

def from_digits_unasserted(value):
  match value:
    case None{}:
      Unit{}
    case Some{digits}:
      {==}

# Every trace ID converted from four words makes no randomness assertion:
# TraceId.from_words is TraceId.from_digits of the validated digits, so
# from_digits_unasserted applies. Laws.words_unasserted (PROOF.bend)
# rewrites its hypothesis into this view.
law words_unasserted:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  UnassertedCandidate(TC.TraceId.from_words(first, second, third, fourth))

def words_unasserted(first, second, third, fourth):
  from_digits_unasserted(Digits.NonZero.new(32n,
    Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
      Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
        Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))))

# The digits of a successful parse of eight digits, or `fallback` for a
# failure. hex_injective applies it with Equal.cong to an equation between
# two parse results, to obtain an equation between their digits.
def digits_or(result: Result<&2, &2, TC.Error, TC.Parsed<8n>>, fallback: Digits.Digits(8n)) -> Digits.Digits(8n):
  match result:
    case Fail{error}:
      fallback
    case Done{TC.Parsed{digits, rest}}:
      digits

# When two words have the same eight-digit text, they are the same word:
# distinct words have distinct texts, so the conversion loses no
# information. Laws.hex_injective (PROOF.bend) calls it.
law hex_injective:
  for +left: U32
  for +right: U32
  for same: {TC.U32.to_hex(left) == TC.U32.to_hex(right) : String}
  {left == right : U32}

# Parsing the common text yields both words' digits, so u32_roundtrip applies.
def hex_injective(left, right, same):
  +parsed = Equal.trans(Result<&2, &2, TC.Error, TC.Parsed<8n>>,
    Done{TC.Parsed{Digits.Digits.of_u32(left), ""}},
    TC.Parse.digits(8n, TC.U32.to_hex(right) ++ "", 0n),
    Done{TC.Parsed{Digits.Digits.of_u32(right), ""}},
    Equal.trans(Result<&2, &2, TC.Error, TC.Parsed<8n>>,
      Done{TC.Parsed{Digits.Digits.of_u32(left), ""}},
      TC.Parse.digits(8n, TC.U32.to_hex(left) ++ "", 0n),
      TC.Parse.digits(8n, TC.U32.to_hex(right) ++ "", 0n),
      Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<8n>>,
        TC.Parse.digits(8n, TC.U32.to_hex(left) ++ "", 0n), Done{TC.Parsed{Digits.Digits.of_u32(left), ""}},
        ParserProof.digits_roundtrip(8n, Digits.Digits.of_u32(left), "", 0n)),
      Equal.cong(String, Result<&2, &2, TC.Error, TC.Parsed<8n>>, text => TC.Parse.digits(8n, text ++ "", 0n),
        TC.U32.to_hex(left), TC.U32.to_hex(right), same)),
    ParserProof.digits_roundtrip(8n, Digits.Digits.of_u32(right), "", 0n))
  +digits = Equal.cong(Result<&2, &2, TC.Error, TC.Parsed<8n>>, Digits.Digits(8n),
    result => digits_or(result, Digits.Digits.of_u32(left)),
    Done{TC.Parsed{Digits.Digits.of_u32(left), ""}}, Done{TC.Parsed{Digits.Digits.of_u32(right), ""}}, parsed)
  Equal.trans(U32, left, Digits.Digits.to_u32(Digits.Digits.of_u32(right)), right,
    Equal.trans(U32, left, Digits.Digits.to_u32(Digits.Digits.of_u32(left)),
      Digits.Digits.to_u32(Digits.Digits.of_u32(right)),
      Equal.sym(U32, Digits.Digits.to_u32(Digits.Digits.of_u32(left)), left, WordsProof.u32_roundtrip(left)),
      Equal.cong(Digits.Digits(8n), U32, digits => Digits.Digits.to_u32(digits),
        Digits.Digits.of_u32(left), Digits.Digits.of_u32(right), digits)),
    WordsProof.u32_roundtrip(right))
