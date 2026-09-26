# Proofs: the field readers of the strict codec
# =============================================
#
# Lemmas about the readers that TraceParentV00.parse, TraceId.parse and
# SpanId.parse are built from: Parse.digit, Parse.digits, Parse.separator,
# Parse.end, Parse.nonzero and Parse.version of trace_context.bend (imported
# as TC). PROOF.bend calls none of them directly; other proof modules do.
# digits_roundtrip serves law roundtrip (proofs/context.bend), laws
# trace_id_accepts and span_id_roundtrip (proofs/ids.bend) and law
# hex_injective (proofs/conversion.bend). The views serve law inverse
# (proofs/inverse.bend) and laws trace_id_parse and span_id_parse
# (proofs/ids.bend).
#
# Two directions are proved. From digits to text, digits_roundtrip reads the
# text of known digits back, by induction on their number, rewriting the read
# of each character with digit_roundtrip. From text to digits, each reader has
# a view: a type that is Unit for a failure and, for a success, the equation
# that ties what the reader returned to its input (DigitView, DigitsView,
# SeparatorView, EndView, NonZeroView, VersionView). A `*_view` law proves a
# reader's view for every input. `match` cannot inspect a computed value, so a
# `*_step` law receives the computed value (a decoded character, a comparison,
# a zero check) as a parameter, together with its own view, and matches on it.
# In these statements, `-x` binders are erased (only the types mention them)
# and `+x` binders may be used several times; neither changes what a law says.

import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ./hex.bend as HexProof
import ./chars.bend as CharsProof

# Reading the character of any digit, at any offset, gives back that digit:
# HexProof.roundtrip (decoding inverts encoding) carried through
# Parse.digit_result with Equal.cong. digits_roundtrip uses it for each digit.
law digit_roundtrip:
  for digit: Hex.Digit
  for offset: Nat
  {TC.Parse.digit(Hex.Digit.to_char(digit), offset) == Done{digit} : Result<&2, &2, TC.Error, Hex.Digit>}

def digit_roundtrip(digit, offset):
  Equal.cong(Maybe<&2, Hex.Digit>, Result<&2, &2, TC.Error, Hex.Digit>,
    value => TC.Parse.digit_result(value, offset),
    Hex.Digit.from_char(Hex.Digit.to_char(digit)), Some{digit}, HexProof.roundtrip(digit))

# The end of one step of Parse.digits once its first digit is known: put
# `digit` in front of a successful read of the rest. This def and step_result
# name the continuations of Parse.digits, so that the statements of the step
# laws below and the rewrite motives of digits_roundtrip (the P of `%e : P`)
# can refer to the read that each step replaces.
def prepend_result(-n: Nat, digit: Hex.Digit,
  result: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
  do Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
    parsed : TC.Parsed<n> <- result
    return TC.Parsed.prepend(n, digit, parsed)

# One step of Parse.digits as a function of its two reads: `digit`, the read
# of the first character, and `rest`, the read of the remaining text:
# Parse.digits(1n+n, SCon{c, t}, offset) computes to
# step_result(n, Parse.digit(c, offset), Parse.digits(n, t, 1n+offset)).
def step_result(-n: Nat, digit: Result<&2, &2, TC.Error, Hex.Digit>,
  rest: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
  do Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
    value : Hex.Digit <- digit
    prepend_result(n, value, rest)

# Reading n digits from their own text followed by any suffix gives back
# exactly those digits and leaves the suffix unread, whatever the offset. The
# offset is general because each step reads at the next offset. The suffix is
# general because the rest of a traceparent follows each field
# (proofs/context.bend), while a supplied ID (proofs/ids.bend) and the eight
# digits of a word (proofs/conversion.bend) are followed by nothing.
law digits_roundtrip:
  for n: Nat
  for digits: Digits.Digits(n)
  for suffix: String
  for +offset: Nat
  {TC.Parse.digits(n, Digits.Digits.to_string(n, digits) ++ suffix, offset) == Done{TC.Parsed{digits, suffix}} : Result<&2, &2, TC.Error, TC.Parsed<n>>}

# Induction on n: digit_roundtrip rewrites the first read, recursion the rest.
def digits_roundtrip(n, digits, suffix, offset):
  match n:
    case 0n:
      match digits:
        case Digits.DNil{}:
          {==}
    case 1n+p:
      match digits:
        case Digits.DCon{head, tail}:
          %Equal.sym(Result<&2, &2, TC.Error, Hex.Digit>,
            TC.Parse.digit(Hex.Digit.to_char(head), offset), Done{head},
            digit_roundtrip(head, offset)) : {
              step_result(p, _, TC.Parse.digits(p, Digits.Digits.to_string(p, tail) ++ suffix, 1n+offset)) ==
              Done{TC.Parsed{Digits.DCon{head, tail}, suffix}} : Result<&2, &2, TC.Error, TC.Parsed<1n+p>>}
          %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<p>>,
            TC.Parse.digits(p, Digits.Digits.to_string(p, tail) ++ suffix, 1n+offset), Done{TC.Parsed{tail, suffix}},
            digits_roundtrip(p, tail, suffix, 1n+offset)) : {
              prepend_result(p, head, _) == Done{TC.Parsed{Digits.DCon{head, tail}, suffix}} :
              Result<&2, &2, TC.Error, TC.Parsed<1n+p>>}
          {==}

# The views: every success of a reader reproduces the text it read.

# The view of Parse.digit for `char`: Unit for a failure and, for a success,
# the equation saying that `char` is the character of the digit returned.
def DigitView(char: Char, result: Result<&2, &2, TC.Error, Hex.Digit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{digit}:
      {Hex.Digit.to_char(digit) == char : Char}

# When `view` is the decoder's view of `decoded` (HexProof.DecodedView: a
# decoded digit is encoded by `char`), the result that Parse.digit_result
# builds from `decoded` satisfies DigitView. `decoded` stands for
# Hex.Digit.from_char(char), which digit_view passes in because it cannot
# match on a computed value.
law digit_step:
  for -char: Char
  for decoded: Maybe<&2, Hex.Digit>
  for view: HexProof.DecodedView(char, decoded)
  for offset: Nat
  DigitView(char, TC.Parse.digit_result(decoded, offset))

def digit_step(char, decoded, view, offset):
  match decoded:
    case None{}:
      Unit{}
    case Some{digit}:
      view

# Every character that Parse.digit accepts, at any offset, is the character
# of the digit it returns. Quantified over every character, including the
# rejected ones. digits_view uses it for each character it reads.
law digit_view:
  for +char: Char
  for offset: Nat
  DigitView(char, TC.Parse.digit(char, offset))

def digit_view(char, offset):
  digit_step(char, Hex.Digit.from_char(char), HexProof.decoded_view(char), offset)

# The view of Parse.digits for `text`: Unit for a failure and, for a success
# Parsed{digits, rest}, the equation saying that the characters of the n
# digits followed by the unread rest are `text`.
def DigitsView(n: Nat, text: String, result: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{TC.Parsed{digits, rest}}:
      {Digits.Digits.to_string(n, digits) ++ rest == text : String}

# When the first character `char` encodes `digit` (`char_eq`) and the read of
# p digits from `tail` satisfies DigitsView, putting `digit` in front of that
# read (prepend_result) satisfies DigitsView for 1 + p digits read from
# SCon{char, tail}. A success rewrites the text with both equations.
# digits_digit_step uses it.
law digits_rest_step:
  for -p: Nat
  for -char: Char
  for -tail: String
  for -digit: Hex.Digit
  for char_eq: {Hex.Digit.to_char(digit) == char : Char}
  for rest_result: Result<&2, &2, TC.Error, TC.Parsed<p>>
  for rest_view: DigitsView(p, tail, rest_result)
  DigitsView(1n+p, SCon{char, tail}, prepend_result(p, digit, rest_result))

def digits_rest_step(p, char, tail, digit, char_eq, rest_result, rest_view):
  match rest_result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{digits, rest}}:
      %rest_view : {SCon{Hex.Digit.to_char(digit), Digits.Digits.to_string(p, digits) ++ rest} ==
        SCon{char, _} : String}
      %char_eq : {SCon{Hex.Digit.to_char(digit), Digits.Digits.to_string(p, digits) ++ rest} ==
        SCon{_, Digits.Digits.to_string(p, digits) ++ rest} : String}
      {==}

# When the read of the first character satisfies DigitView and the read of
# the rest satisfies DigitsView, one step of Parse.digits (step_result)
# satisfies DigitsView for the whole text. digits_view passes both reads in,
# with their views, because it cannot match on them.
law digits_digit_step:
  for -p: Nat
  for -char: Char
  for -tail: String
  for digit_result: Result<&2, &2, TC.Error, Hex.Digit>
  for digit_view: DigitView(char, digit_result)
  for rest_result: Result<&2, &2, TC.Error, TC.Parsed<p>>
  for rest_view: DigitsView(p, tail, rest_result)
  DigitsView(1n+p, SCon{char, tail}, step_result(p, digit_result, rest_result))

def digits_digit_step(p, char, tail, digit_result, digit_view, rest_result, rest_view):
  match digit_result:
    case Fail{error}:
      Unit{}
    case Done{digit}:
      digits_rest_step(p, char, tail, digit, digit_view, rest_result, rest_view)

# Whatever the text and offset, a successful read of n digits returns digits
# whose characters, followed by the unread rest, are the text. By induction on
# n. proofs/inverse.bend uses it for each field of a traceparent, and
# proofs/ids.bend for the digits of a supplied ID.
law digits_view:
  for +n: Nat
  for text: String
  for +offset: Nat
  DigitsView(n, text, TC.Parse.digits(n, text, offset))

def digits_view(n, text, offset):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match text:
        case SNil{}:
          Unit{}
        case SCon{+char, +tail}:
          digits_digit_step(p, char, tail, TC.Parse.digit(char, offset), digit_view(char, offset),
            TC.Parse.digits(p, tail, 1n+offset), digits_view(p, tail, 1n+offset))

# The view of Parse.separator for `text`: Unit for a failure and, for a
# success returning `tail`, the equation saying that `text` is "-" followed
# by `tail`.
def SeparatorView(text: String, result: Result<&2, &2, TC.Error, String>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{tail}:
      {"-" ++ tail == text : String}

# When `same_view` is the view of `same` as the comparison of `char` with '-'
# (CharsProof.CharView: the equation char == '-' when `same` is True), the
# separator result for SCon{char, tail} satisfies SeparatorView. `same`
# stands for Char.is_eq(char, '-'), which separator_view passes in because it
# cannot match on a computed value.
law separator_step:
  for -char: Char
  for -tail: String
  for same: Bool
  for same_view: CharsProof.CharView(char, '-', same)
  for offset: Nat
  SeparatorView(SCon{char, tail}, TC.Parse.separator_result(tail, same, offset))

def separator_step(char, tail, same, same_view, offset):
  match same:
    case False{}:
      Unit{}
    case True{}:
      %Equal.sym(Char, char, '-', same_view) : {"-" ++ tail == SCon{_, tail} : String}
      {==}

# A successful separator read, at any offset, consumed exactly one "-" and
# returned the rest of the text. proofs/inverse.bend uses it for the three
# separators of a traceparent.
law separator_view:
  for text: String
  for offset: Nat
  SeparatorView(text, TC.Parse.separator(text, offset))

def separator_view(text, offset):
  match text:
    case SNil{}:
      Unit{}
    case SCon{+char, tail}:
      separator_step(char, tail, Char.is_eq(char, '-'), CharsProof.char_view(char, '-'), offset)

# The view of Parse.end for `text`: Unit for a failure and, for a success,
# the equation saying that `text` is empty.
def EndView(text: String, result: Result<&2, &2, TC.Error, Unit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{end}:
      {"" == text : String}

# Parse.end succeeds only on the empty text. proofs/inverse.bend uses it after
# the flags, and proofs/ids.bend after the digits of a supplied ID.
law end_view:
  for text: String
  EndView(text, TC.Parse.end(text))

def end_view(text):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      Unit{}

# The view of Parse.nonzero for `digits`: Unit for a failure and, for a
# success, the equation saying that the value returned has the text of
# `digits`: the check attaches its proof without changing the digits.
def NonZeroView(n: Nat, digits: Digits.Digits(n), result: Result<&2, &2, TC.Error, Digits.NonZero<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.NonZero.to_string(n, value) == Digits.Digits.to_string(n, digits) : String}

# Whatever the outcome `status` of the zero check, the result that
# Parse.nonzero_result builds from Digits.NonZero.new.checked satisfies
# NonZeroView. `status` stands for Digits.Digits.is_zero(n, digits), and the
# erased `evidence` states that equation, as in Digits.NonZero.new.checked;
# nonzero_view passes in the computed check and `{==}`.
law nonzero_step:
  for -n: Nat
  for -digits: Digits.Digits(n)
  for status: Bool
  for -evidence: {Digits.Digits.is_zero(n, digits) == status : Bool}
  for field: TC.Field
  NonZeroView(n, digits, TC.Parse.nonzero_result(n,
    Digits.NonZero.new.checked(n, digits, status, evidence), field))

def nonzero_step(n, digits, status, evidence, field):
  match status:
    case True{}:
      Unit{}
    case False{}:
      {==}

# A successful nonzero check returns a value with the text of the digits it
# checked, whatever field it names. proofs/inverse.bend uses it for the trace
# and parent IDs, and proofs/ids.bend for a supplied ID.
law nonzero_view:
  for +n: Nat
  for +digits: Digits.Digits(n)
  for field: TC.Field
  NonZeroView(n, digits, TC.Parse.nonzero(n, digits, field))

def nonzero_view(n, digits, field):
  nonzero_step(n, digits, Digits.Digits.is_zero(n, digits), {==}, field)

# The view of Parse.version for the two version digits: Unit for a failure
# and, for a success, the equation saying that their text is "00".
def VersionView(version: Digits.Digits(2n), result: Result<&2, &2, TC.Error, Unit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{version_ok}:
      {"00" == Digits.Digits.to_string(2n, version) : String}

# For each of the 256 versions, given as two digits, only 00 passes the
# version check: a success means that the version's text is "00".
# version_view uses it.
law version_digits:
  for high: Hex.Digit
  for low: Hex.Digit
  VersionView(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
    TC.Parse.version(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}))

# Parse.version singles out 00 and ff, so only 0 and f need the second digit.
def version_digits(high, low):
  match high:
    case Hex.H0{}:
      match low:
        case Hex.H0{}:
          {==}
        case Hex.H1{}:
          Unit{}
        case Hex.H2{}:
          Unit{}
        case Hex.H3{}:
          Unit{}
        case Hex.H4{}:
          Unit{}
        case Hex.H5{}:
          Unit{}
        case Hex.H6{}:
          Unit{}
        case Hex.H7{}:
          Unit{}
        case Hex.H8{}:
          Unit{}
        case Hex.H9{}:
          Unit{}
        case Hex.Ha{}:
          Unit{}
        case Hex.Hb{}:
          Unit{}
        case Hex.Hc{}:
          Unit{}
        case Hex.Hd{}:
          Unit{}
        case Hex.He{}:
          Unit{}
        case Hex.Hf{}:
          Unit{}
    case Hex.H1{}:
      Unit{}
    case Hex.H2{}:
      Unit{}
    case Hex.H3{}:
      Unit{}
    case Hex.H4{}:
      Unit{}
    case Hex.H5{}:
      Unit{}
    case Hex.H6{}:
      Unit{}
    case Hex.H7{}:
      Unit{}
    case Hex.H8{}:
      Unit{}
    case Hex.H9{}:
      Unit{}
    case Hex.Ha{}:
      Unit{}
    case Hex.Hb{}:
      Unit{}
    case Hex.Hc{}:
      Unit{}
    case Hex.Hd{}:
      Unit{}
    case Hex.He{}:
      Unit{}
    case Hex.Hf{}:
      match low:
        case Hex.H0{}:
          Unit{}
        case Hex.H1{}:
          Unit{}
        case Hex.H2{}:
          Unit{}
        case Hex.H3{}:
          Unit{}
        case Hex.H4{}:
          Unit{}
        case Hex.H5{}:
          Unit{}
        case Hex.H6{}:
          Unit{}
        case Hex.H7{}:
          Unit{}
        case Hex.H8{}:
          Unit{}
        case Hex.H9{}:
          Unit{}
        case Hex.Ha{}:
          Unit{}
        case Hex.Hb{}:
          Unit{}
        case Hex.Hc{}:
          Unit{}
        case Hex.Hd{}:
          Unit{}
        case Hex.He{}:
          Unit{}
        case Hex.Hf{}:
          Unit{}

# A successful version check, on any two version digits, means the version
# is 00. proofs/inverse.bend uses it to rewrite the version's text into "00".
law version_view:
  for version: Digits.Digits(2n)
  VersionView(version, TC.Parse.version(version))

def version_view(version):
  match version:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      version_digits(high, low)
