import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex

# The expected wire strings and errors below are independent protocol fixtures.
def Test.assert(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "FAIL: " ++ name)

def Test.error_equal(actual: TC.Error, expected: TC.Error) -> Bool:
  match actual expected:
    case TC.UnexpectedEnd{a} TC.UnexpectedEnd{b}:
      Nat.is_eq(a, b)
    case TC.InvalidHex{a} TC.InvalidHex{b}:
      Nat.is_eq(a, b)
    case TC.ExpectedSeparator{a} TC.ExpectedSeparator{b}:
      Nat.is_eq(a, b)
    case TC.TrailingInput{} TC.TrailingInput{}:
      True{}
    case TC.ForbiddenVersion{} TC.ForbiddenVersion{}:
      True{}
    case TC.UnsupportedVersion{a} TC.UnsupportedVersion{b}:
      String.eq(a, b)
    case TC.ZeroId{TC.TraceIdField{}} TC.ZeroId{TC.TraceIdField{}}:
      True{}
    case TC.ZeroId{TC.ParentIdField{}} TC.ZeroId{TC.ParentIdField{}}:
      True{}
    case _ _:
      False{}

def Test.reject_result(name: String,
  result: Result<&2, &2, TC.Error, TC.TraceParentV00>, expected: TC.Error) -> IO(Unit):
  match result:
    case Done{_}:
      IO.die(Unit, 1, "FAIL: accepted " ++ name)
    case Fail{actual}:
      Test.assert(name, Test.error_equal(actual, expected))

def Test.reject(name: String, text: String, expected: TC.Error) -> IO(Unit):
  Test.reject_result(name, TC.TraceParentV00.parse(text), expected)

def Test.accept_result(+name: String, text: String, sampled: Bool,
  result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, "FAIL: " ++ name ++ ": " ++ TC.Error.show(error))
    case Done{+context}:
      do IO<Unit>:
        Unit <- Test.assert(name ++ " preserves bytes",
          String.eq(TC.TraceParentV00.format(context), text))
        Test.assert(name ++ " sampled bit",
          Bool.not(Bool.xor(TC.TraceParentV00.is_sampled(context), sampled)))

def Test.accept(name: String, +text: String, sampled: Bool) -> IO(Unit):
  Test.accept_result(name, text, sampled, TC.TraceParentV00.parse(text))

# Replace one character without depending on the parser's field helpers.
def Test.replace(text: String, offset: Nat, char: Char) -> String:
  match text offset:
    case SNil{} 0n:
      SNil{}
    case SCon{_, tail} 0n:
      SCon{char, tail}
    case SNil{} 1n+rest:
      SNil{}
    case SCon{head, tail} 1n+rest:
      SCon{head, Test.replace(tail, rest, char)}

def Test.w3c() -> String:
  "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

def Test.prefix() -> String:
  "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-"

def Test.digits() -> List<&2, Hex.Digit>:
  [Hex.H0{}, Hex.H1{}, Hex.H2{}, Hex.H3{},
   Hex.H4{}, Hex.H5{}, Hex.H6{}, Hex.H7{},
   Hex.H8{}, Hex.H9{}, Hex.Ha{}, Hex.Hb{},
   Hex.Hc{}, Hex.Hd{}, Hex.He{}, Hex.Hf{}]

def Test.render_digits(digits: List<&2, Hex.Digit>) -> String:
  match digits:
    case Nil{}:
      SNil{}
    case Con{digit, tail}:
      SCon{Hex.Digit.to_char(digit), Test.render_digits(tail)}

# All 256 flag bytes. The parity oracle uses an independent numeric counter,
# not Digit.is_odd, and the alphabet is checked against a literal separately.
def Test.flag_suffix(high: Hex.Digit, low: Hex.Digit) -> String:
  SCon{Hex.Digit.to_char(high), SCon{Hex.Digit.to_char(low), SNil{}}}

def Test.flag_lows(+high: Hex.Digit, lows: List<&2, Hex.Digit>, +low_value: U32) -> IO(Unit):
  match lows:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{low, tail}:
      +suffix = Test.flag_suffix(high, low)
      sampled = U32.is_eq(U32.mod(low_value, 2), 1)
      do IO<Unit>:
        Unit <- Test.accept("flags " ++ suffix, Test.prefix() ++ suffix, sampled)
        Test.flag_lows(high, tail, U32.add(low_value, 1))

def Test.flag_highs(highs: List<&2, Hex.Digit>) -> IO(Unit):
  match highs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{high, tail}:
      do IO<Unit>:
        Unit <- Test.flag_lows(high, Test.digits(), 0)
        Test.flag_highs(tail)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- Test.accept("W3C example, 55 characters", Test.w3c(), True{})
    Unit <- Test.accept("flags 00", Test.prefix() ++ "00", False{})
    Unit <- Test.accept("flags 01", Test.prefix() ++ "01", True{})
    Unit <- Test.accept("flags 02", Test.prefix() ++ "02", False{})
    Unit <- Test.accept("flags 03", Test.prefix() ++ "03", True{})
    Unit <- Test.accept("flags ff", Test.prefix() ++ "ff", True{})
    Unit <- IO.print("OK: W3C example and reserved flag bits")

    Unit <- Test.reject("empty", "", TC.UnexpectedEnd{0n})
    Unit <- Test.reject("one version digit", "0", TC.UnexpectedEnd{1n})
    Unit <- Test.reject("version without separator", "00", TC.UnexpectedEnd{2n})
    Unit <- Test.reject("54 characters", String.take(Test.w3c(), 54n), TC.UnexpectedEnd{54n})
    Unit <- Test.reject("56 characters", Test.w3c() ++ "0", TC.TrailingInput{})
    Unit <- Test.reject("v00 extension", Test.w3c() ++ "-vendor", TC.TrailingInput{})
    Unit <- Test.reject("suffix whitespace", Test.w3c() ++ " ", TC.TrailingInput{})
    Unit <- Test.reject("suffix newline", Test.w3c() ++ "\n", TC.TrailingInput{})
    Unit <- Test.reject("version ff", "ff" ++ String.drop(Test.w3c(), 2n), TC.ForbiddenVersion{})
    Unit <- Test.reject("future version 01", "01" ++ String.drop(Test.w3c(), 2n),
      TC.UnsupportedVersion{"01"})
    Unit <- IO.print("OK: lengths, suffixes and version policy")

    Unit <- Test.reject("uppercase version", Test.replace(Test.w3c(), 1n, 'A'), TC.InvalidHex{1n})
    Unit <- Test.reject("uppercase trace ID", Test.replace(Test.w3c(), 4n, 'A'), TC.InvalidHex{4n})
    Unit <- Test.reject("uppercase parent ID", Test.replace(Test.w3c(), 36n, 'B'), TC.InvalidHex{36n})
    Unit <- Test.reject("uppercase flag high", Test.replace(Test.w3c(), 53n, 'F'), TC.InvalidHex{53n})
    Unit <- Test.reject("uppercase flag low", Test.replace(Test.w3c(), 54n, 'F'), TC.InvalidHex{54n})
    Unit <- Test.reject("invalid ASCII", Test.replace(Test.w3c(), 12n, 'g'), TC.InvalidHex{12n})
    Unit <- Test.reject("embedded space", Test.replace(Test.w3c(), 12n, ' '), TC.InvalidHex{12n})
    Unit <- Test.reject("embedded tab", Test.replace(Test.w3c(), 12n, '\t'), TC.InvalidHex{12n})
    Unit <- Test.reject("fullwidth digit", Test.replace(Test.w3c(), 3n, '０'), TC.InvalidHex{3n})
    Unit <- Test.reject("fullwidth letter", Test.replace(Test.w3c(), 4n, 'ａ'), TC.InvalidHex{4n})
    Unit <- Test.reject("non-BMP character", Test.replace(Test.w3c(), 36n, '😀'), TC.InvalidHex{36n})
    Unit <- IO.print("OK: lowercase ASCII alphabet and character offsets")

    Unit <- Test.reject("separator at 2", Test.replace(Test.w3c(), 2n, ':'), TC.ExpectedSeparator{2n})
    Unit <- Test.reject("separator at 35", Test.replace(Test.w3c(), 35n, ':'), TC.ExpectedSeparator{35n})
    Unit <- Test.reject("separator at 52", Test.replace(Test.w3c(), 52n, ':'), TC.ExpectedSeparator{52n})
    Unit <- Test.reject("zero trace ID",
      "00-00000000000000000000000000000000-b7ad6b7169203331-01",
      TC.ZeroId{TC.TraceIdField{}})
    Unit <- Test.reject("zero parent ID",
      "00-0af7651916cd43dd8448eb211c80319c-0000000000000000-01",
      TC.ZeroId{TC.ParentIdField{}})
    Unit <- Test.accept("last digits establish nonzero IDs",
      "00-00000000000000000000000000000001-0000000000000001-00", False{})
    Unit <- Test.accept("first digits establish nonzero IDs",
      "00-10000000000000000000000000000000-1000000000000000-00", False{})
    Unit <- IO.print("OK: separators and nonzero IDs")

    Unit <- Test.assert("hexadecimal alphabet",
      String.eq(Test.render_digits(Test.digits()), "0123456789abcdef"))
    Unit <- Test.flag_highs(Test.digits())
    IO.print("OK: all 256 flag bytes preserve format and sampled bit")
