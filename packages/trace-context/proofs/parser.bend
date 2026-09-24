import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ./hex.bend as HexProof

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
