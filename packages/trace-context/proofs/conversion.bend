import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./parser.bend as ParserProof
import ./strings.bend as StringsProof
import ./words.bend as WordsProof
import ../src/hex.bend as Hex

# The text of concatenated digits is the concatenation of their texts.
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

# A candidate trace ID is the four words' digits, in the order they were read.
def TraceWordsView(first: U32, second: U32, third: U32, fourth: U32,
  candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.to_string(id) ==
        TC.U32.to_hex(first) ++ TC.U32.to_hex(second) ++ TC.U32.to_hex(third) ++ TC.U32.to_hex(fourth) : String}

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

def SpanWordsView(first: U32, second: U32, candidate: Maybe<&2, TC.SpanId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.SpanId.to_string(id) == TC.U32.to_hex(first) ++ TC.U32.to_hex(second) : String}

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

law span_words_view:
  for +first: U32
  for +second: U32
  SpanWordsView(first, second, TC.SpanId.from_words(first, second))

def span_words_view(first, second):
  span_words_step(first, second, Digits.Digits.is_zero(16n,
    Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second))), {==})

# Converting words makes no randomness assertion.
def UnassertedCandidate(candidate: Maybe<&2, TC.TraceId>) -> Type:
  match candidate:
    case None{}:
      Unit
    case Some{id}:
      {TC.TraceId.is_random(id) == False{} : Bool}

law from_digits_unasserted:
  for value: Maybe<&2, Digits.NonZero<32n>>
  UnassertedCandidate(TC.TraceId.from_digits(value))

def from_digits_unasserted(value):
  match value:
    case None{}:
      Unit{}
    case Some{digits}:
      {==}

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

def digits_or(result: Result<&2, &2, TC.Error, TC.Parsed<8n>>, fallback: Digits.Digits(8n)) -> Digits.Digits(8n):
  match result:
    case Fail{error}:
      fallback
    case Done{TC.Parsed{digits, rest}}:
      digits

# Distinct words have distinct texts: the conversion loses no information.
law hex_injective:
  for +left: U32
  for +right: U32
  for same: {TC.U32.to_hex(left) == TC.U32.to_hex(right) : String}
  {left == right : U32}

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
