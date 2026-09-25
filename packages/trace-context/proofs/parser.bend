import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ./hex.bend as HexProof
import ./chars.bend as CharsProof

law digit_roundtrip:
  for digit: Hex.Digit
  for offset: Nat
  {TC.Parse.digit(Hex.Digit.to_char(digit), offset) == Done{digit} : Result<&2, &2, TC.Error, Hex.Digit>}

def digit_roundtrip(digit, offset):
  Equal.cong(Maybe<&2, Hex.Digit>, Result<&2, &2, TC.Error, Hex.Digit>,
    value => TC.Parse.digit_result(value, offset),
    Hex.Digit.from_char(Hex.Digit.to_char(digit)), Some{digit}, HexProof.roundtrip(digit))

# Name the two pure Result continuations used by Parse.digits, so the motives
# can state exactly which computation is replaced by each induction step.
def prepend_result(-n: Nat, digit: Hex.Digit,
  result: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
  do Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
    parsed : TC.Parsed<n> <- result
    return TC.Parsed.prepend(n, digit, parsed)

def step_result(-n: Nat, digit: Result<&2, &2, TC.Error, Hex.Digit>,
  rest: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
  do Result<&2, &2, TC.Error, TC.Parsed<1n+n>>:
    value : Hex.Digit <- digit
    prepend_result(n, value, rest)

law digits_roundtrip:
  for n: Nat
  for digits: Digits.Digits(n)
  for suffix: String
  for +offset: Nat
  {TC.Parse.digits(n, Digits.Digits.to_string(n, digits) ++ suffix, offset) == Done{TC.Parsed{digits, suffix}} : Result<&2, &2, TC.Error, TC.Parsed<n>>}

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

# The inverse direction: every value a reader accepts reproduces the text it read.

def DigitView(char: Char, result: Result<&2, &2, TC.Error, Hex.Digit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{digit}:
      {Hex.Digit.to_char(digit) == char : Char}

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

law digit_view:
  for +char: Char
  for offset: Nat
  DigitView(char, TC.Parse.digit(char, offset))

def digit_view(char, offset):
  digit_step(char, Hex.Digit.from_char(char), HexProof.decoded_view(char), offset)

def DigitsView(n: Nat, text: String, result: Result<&2, &2, TC.Error, TC.Parsed<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{TC.Parsed{digits, rest}}:
      {Digits.Digits.to_string(n, digits) ++ rest == text : String}

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

def SeparatorView(text: String, result: Result<&2, &2, TC.Error, String>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{tail}:
      {"-" ++ tail == text : String}

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

def EndView(text: String, result: Result<&2, &2, TC.Error, Unit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{end}:
      {"" == text : String}

law end_view:
  for text: String
  EndView(text, TC.Parse.end(text))

def end_view(text):
  match text:
    case SNil{}:
      {==}
    case SCon{char, tail}:
      Unit{}

def NonZeroView(n: Nat, digits: Digits.Digits(n), result: Result<&2, &2, TC.Error, Digits.NonZero<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.NonZero.to_string(n, value) == Digits.Digits.to_string(n, digits) : String}

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

law nonzero_view:
  for +n: Nat
  for +digits: Digits.Digits(n)
  for field: TC.Field
  NonZeroView(n, digits, TC.Parse.nonzero(n, digits, field))

def nonzero_view(n, digits, field):
  nonzero_step(n, digits, Digits.Digits.is_zero(n, digits), {==}, field)

def VersionView(version: Digits.Digits(2n), result: Result<&2, &2, TC.Error, Unit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{version_ok}:
      {"00" == Digits.Digits.to_string(2n, version) : String}

# Every one of the 256 versions is examined; only 00 is accepted.
law version_digits:
  for high: Hex.Digit
  for low: Hex.Digit
  VersionView(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
    TC.Parse.version(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}))

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

law version_view:
  for version: Digits.Digits(2n)
  VersionView(version, TC.Parse.version(version))

def version_view(version):
  match version:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      version_digits(high, low)
