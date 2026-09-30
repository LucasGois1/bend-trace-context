# Proofs: identifiers as bytes
# ============================
#
# Proves the laws of section 16 of LAWS.bend about TraceId.to_bytes,
# SpanId.to_bytes, TraceId.from_bytes and SpanId.from_bytes; PROOF.bend calls
# these lemmas as BytesProof.*, and proves zero_bytes by computation.
# trace_bytes and span_bytes measure the bytes with the laws' own reading of
# hexadecimal text. The round trips, the inverses and the refusals follow the
# byte reader of trace_context.bend (Parse.byte, Parse.bytes,
# Parse.bytes_end, Parse.id_bytes), as proofs/ids.bend and proofs/parser.bend
# follow the text reader.
#
# Strategy: a byte is Digits.to_byte of two digits, their bits followed by 24
# zero bits. digit_bits turns the bits of a digit back into it, so each
# byte's value is that of its digits (byte_value, through
# WordsProof.word_value), and each byte is read back as its digits
# (byte_roundtrip, with byte_below: such a word is at most 255).
# bytes_values and bytes_roundtrip extend this to 2n digits by induction on
# n. From a list of cells to an ID, each reader has a view, as in
# proofs/parser.bend: ByteView, BytesView, BytesEndView, NonZeroDigitsView
# and IdBytesView say that a success is the bytes of the digits it returns.
# The one fact about U32 that they need is byte_of_cell: a cell at most 255
# is the byte of its two digits, since its bits 8 to 31 are zero (zero_cmp,
# below_step). The refusals are inductions over the cells before the refused
# one (bytes_short, bytes_above, bytes_suffix); a list of bytes that are not
# all zero is accepted, since all-zero digits would have all-zero bytes
# (zero_cells); and injectivity follows from the round trips.

import Base
import ../trace_context.bend as TC
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ../LAWS.bend as Laws
import ./bools.bend as BoolsProof
import ./digits.bend as DigitsProof
import ./lists.bend as ListsProof
import ./nats.bend as NatsProof
import ./words.bend as WordsProof

# A digit survives the trip through its four bits: reading them (is_odd,
# has_bit1, has_bit2, has_bit3) and making a digit of them with
# Hex.Digit.from_bits gives the digit back. Sixteen cases, each by
# computation. Used by byte_value and of_to_byte for each digit of a byte.
law digit_bits:
  for digit: Hex.Digit
  {Hex.Digit.from_bits(Hex.Digit.is_odd(digit), Hex.Digit.has_bit1(digit), Hex.Digit.has_bit2(digit),
    Hex.Digit.has_bit3(digit)) == digit : Hex.Digit}

def digit_bits(digit):
  match digit:
    case Hex.H0{}:
      {==}
    case Hex.H1{}:
      {==}
    case Hex.H2{}:
      {==}
    case Hex.H3{}:
      {==}
    case Hex.H4{}:
      {==}
    case Hex.H5{}:
      {==}
    case Hex.H6{}:
      {==}
    case Hex.H7{}:
      {==}
    case Hex.H8{}:
      {==}
    case Hex.H9{}:
      {==}
    case Hex.Ha{}:
      {==}
    case Hex.Hb{}:
      {==}
    case Hex.Hc{}:
      {==}
    case Hex.Hd{}:
      {==}
    case Hex.He{}:
      {==}
    case Hex.Hf{}:
      {==}

# The value of the byte of two digits is the number that their characters
# denote in hexadecimal, the first digit high. WordsProof.word_value reads
# the byte's eight digits, six zeros and then these two, as the byte's value,
# and digit_bits gives back the two digits from their bits. bytes_values
# uses it for each byte.
law byte_value:
  for +high: Hex.Digit
  for +low: Hex.Digit
  {U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})) ==
    Laws.hex_numeral(SCon{Hex.Digit.to_char(high), SCon{Hex.Digit.to_char(low), SNil{}}}, 0n) : Nat}

def byte_value(high, low):
  %digit_bits(high) : {U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})) ==
    Laws.hex_numeral(SCon{Hex.Digit.to_char(_), SCon{Hex.Digit.to_char(low), SNil{}}}, 0n) : Nat}
  %digit_bits(low) : {U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})) ==
    Laws.hex_numeral(SCon{Hex.Digit.to_char(Hex.Digit.from_bits(Hex.Digit.is_odd(high), Hex.Digit.has_bit1(high),
      Hex.Digit.has_bit2(high), Hex.Digit.has_bit3(high))), SCon{Hex.Digit.to_char(_), SNil{}}}, 0n) : Nat}
  Equal.sym(Nat, Laws.hex_numeral(Digits.Digits.to_string(8n, Digits.Digits.of_u32(Digits.Digits.to_byte(
    Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}))), 0n),
    U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})),
    WordsProof.word_value(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})))

# The values of the n bytes of 2n digits are the values of the pairs of their
# characters, in order. Induction on n: byte_value rewrites the first byte's
# value, recursion the rest. trace_bytes and span_bytes use it.
law bytes_values:
  for n: Nat
  for digits: Digits.Digits(Nat.double(n))
  {Laws.cell_values(Digits.Digits.to_bytes(n, digits)) ==
    Laws.hex_pairs(Digits.Digits.to_string(Nat.double(n), digits)) : List<&2, Nat>}

def bytes_values(n, digits):
  match n:
    case 0n:
      match digits:
        case Digits.DNil{}:
          {==}
    case 1n+p:
      match digits:
        case Digits.DCon{+high, Digits.DCon{+low, rest}}:
          %byte_value(high, low) : {Con{U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high,
            Digits.DCon{low, Digits.DNil{}}})), Laws.cell_values(Digits.Digits.to_bytes(p, rest))} ==
            Con{_, Laws.hex_pairs(Digits.Digits.to_string(Nat.double(p), rest))} : List<&2, Nat>}
          %bytes_values(p, rest) : {Con{U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high,
            Digits.DCon{low, Digits.DNil{}}})), Laws.cell_values(Digits.Digits.to_bytes(p, rest))} ==
            Con{U32.to_nat(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})), _} :
            List<&2, Nat>}
          {==}

# The bytes of a trace ID are the values of the pairs of its digits.
# PROOF.bend's Laws.trace_bytes calls it.
law trace_bytes:
  for id: TC.TraceId
  {Laws.cell_values(TC.TraceId.to_bytes(id)) == Laws.hex_pairs(TC.TraceId.to_string(id)) : List<&2, Nat>}

def trace_bytes(id):
  match id:
    case TC.TraceId{Digits.NonZero{digits, evidence}, random}:
      bytes_values(16n, digits)

# The same for a span ID. PROOF.bend's Laws.span_bytes calls it.
law span_bytes:
  for id: TC.SpanId
  {Laws.cell_values(TC.SpanId.to_bytes(id)) == Laws.hex_pairs(TC.SpanId.to_string(id)) : List<&2, Nat>}

def span_bytes(id):
  match id:
    case TC.SpanId{Digits.NonZero{digits, evidence}}:
      bytes_values(8n, digits)

# A word whose bits 8 to 31 are zero is at most 255, whatever its bits 0 to 7:
# Base compares words from their most significant bit, so the first of bits 7
# to 0 that is not set in the word, and is in 255, makes it smaller, and a
# word with all eight set is 255 itself. By cases on bit 7, then on bit 6 and
# so on while they are set; the bits are given from bit 7 down, since a match
# may only follow those on earlier parameters. Used by byte_roundtrip for the
# bits of a byte.
law byte_below:
  for x7: Bool
  for x6: Bool
  for x5: Bool
  for x4: Bool
  for x3: Bool
  for x2: Bool
  for x1: Bool
  for x0: Bool
  {U32.is_gt(U32{WCon{x0, WCon{x1, WCon{x2, WCon{x3, WCon{x4, WCon{x5, WCon{x6, WCon{x7, Word.zero(24n)}}}}}}}}},
    255) == False{} : Bool}

def byte_below(x7, x6, x5, x4, x3, x2, x1, x0):
  match x7:
    case False{}:
      {==}
    case True{}:
      match x6:
        case False{}:
          {==}
        case True{}:
          match x5:
            case False{}:
              {==}
            case True{}:
              match x4:
                case False{}:
                  {==}
                case True{}:
                  match x3:
                    case False{}:
                      {==}
                    case True{}:
                      match x2:
                        case False{}:
                          {==}
                        case True{}:
                          match x1:
                            case False{}:
                              {==}
                            case True{}:
                              match x0:
                                case False{}:
                                  {==}
                                case True{}:
                                  {==}

# The two digits of a byte made of two digits are those digits:
# Digits.of_byte reads back the bits that Digits.to_byte wrote, and
# digit_bits turns the bits of each digit back into it. Used by
# byte_roundtrip.
law of_to_byte:
  for +high: Hex.Digit
  for +low: Hex.Digit
  {Digits.Digits.of_byte(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})) ==
    Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}} : Digits.Digits(2n)}

def of_to_byte(high, low):
  %digit_bits(high) : {Digits.DCon{Hex.Digit.from_bits(Hex.Digit.is_odd(high), Hex.Digit.has_bit1(high),
    Hex.Digit.has_bit2(high), Hex.Digit.has_bit3(high)), Digits.DCon{Hex.Digit.from_bits(Hex.Digit.is_odd(low),
    Hex.Digit.has_bit1(low), Hex.Digit.has_bit2(low), Hex.Digit.has_bit3(low)), Digits.DNil{}}} ==
    Digits.DCon{_, Digits.DCon{low, Digits.DNil{}}} : Digits.Digits(2n)}
  %digit_bits(low) : {Digits.DCon{Hex.Digit.from_bits(Hex.Digit.is_odd(high), Hex.Digit.has_bit1(high),
    Hex.Digit.has_bit2(high), Hex.Digit.has_bit3(high)), Digits.DCon{Hex.Digit.from_bits(Hex.Digit.is_odd(low),
    Hex.Digit.has_bit1(low), Hex.Digit.has_bit2(low), Hex.Digit.has_bit3(low)), Digits.DNil{}}} ==
    Digits.DCon{Hex.Digit.from_bits(Hex.Digit.is_odd(high), Hex.Digit.has_bit1(high), Hex.Digit.has_bit2(high),
      Hex.Digit.has_bit3(high)), Digits.DCon{_, Digits.DNil{}}} : Digits.Digits(2n)}
  {==}

# Reading the byte of any two digits, at any offset, gives back those digits:
# the byte is at most 255 (byte_below), so it passes the check, and its
# digits are read back (of_to_byte). bytes_roundtrip uses it for each byte.
law byte_roundtrip:
  for +high: Hex.Digit
  for +low: Hex.Digit
  for +offset: Nat
  {TC.Parse.byte(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}), offset) ==
    Done{Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}} : Result<&2, &2, TC.Error, Digits.Digits(2n)>}

def byte_roundtrip(high, low, offset):
  %Equal.sym(Bool, U32.is_gt(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}), 255), False{},
    byte_below(Hex.Digit.has_bit3(high), Hex.Digit.has_bit2(high), Hex.Digit.has_bit1(high), Hex.Digit.is_odd(high),
      Hex.Digit.has_bit3(low), Hex.Digit.has_bit2(low), Hex.Digit.has_bit1(low), Hex.Digit.is_odd(low))) :
    {TC.Parse.byte.checked(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}), _, offset) ==
      Done{Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}} : Result<&2, &2, TC.Error, Digits.Digits(2n)>}
  Equal.cong(Digits.Digits(2n), Result<&2, &2, TC.Error, Digits.Digits(2n)>, digits => Done{digits},
    Digits.Digits.of_byte(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}})),
    Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, of_to_byte(high, low))

# The end of one step of Parse.bytes once its first byte is read: put its
# two digits in front of a successful read of the other bytes. This def and
# bytes_step name the continuations of Parse.bytes, as prepend_result and
# step_result of proofs/parser.bend do for Parse.digits, so that the rewrite
# motives below can refer to the read that each step replaces.
def bytes_prepend(-n: Nat, digits: Digits.Digits(2n), result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>) ->
  Result<&2, &2, TC.Error, TC.ParsedBytes<1n+n>>:
  do Result<&2, &2, TC.Error, TC.ParsedBytes<1n+n>>:
    parsed : TC.ParsedBytes<n> <- result
    return TC.ParsedBytes.prepend(n, digits, parsed)

# One step of Parse.bytes as a function of its two reads: `byte`, the read
# of the first cell, and `rest`, the read of the other cells:
# Parse.bytes(1n+n, Con{cell, tail}, offset) computes to
# bytes_step(n, Parse.byte(cell, offset), Parse.bytes(n, tail, 1n+offset)).
def bytes_step(-n: Nat, byte: Result<&2, &2, TC.Error, Digits.Digits(2n)>,
  rest: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>) -> Result<&2, &2, TC.Error, TC.ParsedBytes<1n+n>>:
  do Result<&2, &2, TC.Error, TC.ParsedBytes<1n+n>>:
    digits : Digits.Digits(2n) <- byte
    bytes_prepend(n, digits, rest)

# Reading the n bytes of 2n known digits, followed by any cells, gives back
# exactly those digits and leaves the cells after them unread, whatever the
# offset. Induction on n: byte_roundtrip rewrites the read of the first byte,
# recursion the rest. id_bytes_roundtrip uses it with no cells after the
# bytes.
law bytes_roundtrip:
  for n: Nat
  for digits: Digits.Digits(Nat.double(n))
  for suffix: List<&2, U32>
  for +offset: Nat
  {TC.Parse.bytes(n, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), suffix), offset) ==
    Done{TC.ParsedBytes{digits, suffix}} : Result<&2, &2, TC.Error, TC.ParsedBytes<n>>}

def bytes_roundtrip(n, digits, suffix, offset):
  match n:
    case 0n:
      match digits:
        case Digits.DNil{}:
          {==}
    case 1n+p:
      match digits:
        case Digits.DCon{+high, Digits.DCon{+low, rest}}:
          %Equal.sym(Result<&2, &2, TC.Error, Digits.Digits(2n)>,
            TC.Parse.byte(Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}), offset),
            Done{Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}, byte_roundtrip(high, low, offset)) : {
              bytes_step(p, _, TC.Parse.bytes(p, List.append(&2, U32, Digits.Digits.to_bytes(p, rest), suffix),
                1n+offset)) ==
              Done{TC.ParsedBytes{Digits.DCon{high, Digits.DCon{low, rest}}, suffix}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<p>>,
            TC.Parse.bytes(p, List.append(&2, U32, Digits.Digits.to_bytes(p, rest), suffix), 1n+offset),
            Done{TC.ParsedBytes{rest, suffix}}, bytes_roundtrip(p, rest, suffix, 1n+offset)) : {
              bytes_prepend(p, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, _) ==
              Done{TC.ParsedBytes{Digits.DCon{high, Digits.DCon{low, rest}}, suffix}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          {==}

# Parse.id_bytes as a function of the read of its n bytes:
# Parse.id_bytes.finish on its success. id_bytes_roundtrip,
# id_bytes_digits_step and the refusals below are stated with it.
def id_bytes_result(n: Nat, field: TC.Field, result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>) ->
  Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>:
    parsed : TC.ParsedBytes<n> <- result
    TC.Parse.id_bytes.finish(n, parsed, field)

# The bytes of every nonzero value of 2n digits are read back as that value,
# evidence included, whatever field is named: the n bytes are the whole list,
# and DigitsProof.new_valid returns the value's own evidence, as
# IdsProof.id_roundtrip does for the text. The span and trace round trips use
# it.
law id_bytes_roundtrip:
  for +n: Nat
  for value: Digits.NonZero<Nat.double(n)>
  for +field: TC.Field
  {TC.Parse.id_bytes(n, Digits.Digits.to_bytes(n, Digits.NonZero.digits(Nat.double(n), value)), field) == Done{value} :
    Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}

# Adds the empty rest for bytes_roundtrip; new_valid returns the value's own
# evidence.
def id_bytes_roundtrip(n, value, field):
  match value:
    case Digits.NonZero{+digits, +evidence}:
      %ListsProof.append_nil(U32, Digits.Digits.to_bytes(n, digits)) :
        {id_bytes_result(n, field, TC.Parse.bytes(n, _, 0n)) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}
      %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<n>>,
        TC.Parse.bytes(n, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), Nil{}), 0n),
        Done{TC.ParsedBytes{digits, Nil{}}}, bytes_roundtrip(n, digits, Nil{}, 0n)) :
        {id_bytes_result(n, field, _) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}
      %Equal.sym(Maybe<&2, Digits.NonZero<Nat.double(n)>>, Digits.NonZero.new(Nat.double(n), digits),
        Some{Digits.NonZero{digits, evidence}}, DigitsProof.new_valid(Nat.double(n), digits, evidence)) :
        {TC.Parse.nonzero_result(Nat.double(n), _, field) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}
      {==}

# TraceId.from_bytes as a function of the result of Parse.id_bytes: a success
# becomes a TraceId with no randomness assertion. The trace ID lemmas below
# are stated with it.
def trace_bytes_result(result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>) -> Result<&2, &2, TC.Error, TC.TraceId>:
  do Result<&2, &2, TC.Error, TC.TraceId>:
    value : Digits.NonZero<32n> <- result
    return TC.TraceId{value, False{}}

# Reading back the bytes of any trace ID gives its digits, with their
# evidence, and no randomness assertion: the bytes are those of the digits
# alone. PROOF.bend's Laws.trace_bytes_roundtrip calls it.
law trace_bytes_roundtrip:
  for value: Digits.NonZero<32n>
  for random: Bool
  {TC.TraceId.from_bytes(TC.TraceId.to_bytes(TC.TraceId{value, random})) == Done{TC.TraceId{value, False{}}} :
    Result<&2, &2, TC.Error, TC.TraceId>}

def trace_bytes_roundtrip(value, random):
  %Equal.sym(Result<&2, &2, TC.Error, Digits.NonZero<32n>>,
    TC.Parse.id_bytes(16n, Digits.Digits.to_bytes(16n, Digits.NonZero.digits(32n, value)), TC.TraceIdField{}),
    Done{value}, id_bytes_roundtrip(16n, value, TC.TraceIdField{})) :
    {trace_bytes_result(_) == Done{TC.TraceId{value, False{}}} : Result<&2, &2, TC.Error, TC.TraceId>}
  {==}

# SpanId.from_bytes as a function of the result of Parse.id_bytes: a success
# becomes a SpanId. The span ID lemmas below are stated with it.
def span_bytes_result(result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>) -> Result<&2, &2, TC.Error, TC.SpanId>:
  do Result<&2, &2, TC.Error, TC.SpanId>:
    value : Digits.NonZero<16n> <- result
    return TC.SpanId{value}

# Reading back the bytes of any span ID gives that span ID: a span ID carries
# nothing besides its digits. PROOF.bend's Laws.span_bytes_roundtrip calls
# it.
law span_bytes_roundtrip:
  for id: TC.SpanId
  {TC.SpanId.from_bytes(TC.SpanId.to_bytes(id)) == Done{id} : Result<&2, &2, TC.Error, TC.SpanId>}

def span_bytes_roundtrip(id):
  match id:
    case TC.SpanId{value}:
      %Equal.sym(Result<&2, &2, TC.Error, Digits.NonZero<16n>>,
        TC.Parse.id_bytes(8n, Digits.Digits.to_bytes(8n, Digits.NonZero.digits(16n, value)), TC.SpanIdField{}),
        Done{value}, id_bytes_roundtrip(8n, value, TC.SpanIdField{})) :
        {span_bytes_result(_) == Done{TC.SpanId{value}} : Result<&2, &2, TC.Error, TC.SpanId>}
      {==}

# The comparison of a word with the zero word, as a view: Empty for LT, which
# never happens, for EQ the equation saying that the word is the zero word,
# and Unit for GT.
def ZeroView(n: Nat, word: Word(n), order: Cmp) -> Type:
  match order:
    case LT{}:
      Empty
    case EQ{}:
      {word == Word.zero(n) : Word(n)}
    case GT{}:
      Unit

# One bit more: when `view` is the view of `order`, the comparison of `tail`
# with the zero word, the comparison of WCon{bit, tail} with the zero word,
# which Word.cmp.fin makes from the bit and `order`, satisfies the view too.
# zero_cmp uses it for each bit.
law zero_step:
  for -p: Nat
  for -tail: Word(p)
  for order: Cmp
  for view: ZeroView(p, tail, order)
  for bit: Bool
  ZeroView(1n+p, WCon{bit, tail}, Word.cmp.fin(bit, False{}, order))

def zero_step(p, tail, order, view, bit):
  match order:
    case LT{}:
      view
    case EQ{}:
      match bit:
        case False{}:
          Equal.cong(Word(p), Word(1n+p), rest => WCon{False{}, rest}, tail, Word.zero(p), view)
        case True{}:
          Unit{}
    case GT{}:
      Unit{}

# Every word's comparison with the zero word satisfies ZeroView: it is EQ
# only for the zero word itself. Induction on n with zero_step. byte_of_cell
# uses it for bits 8 to 31 of a cell.
law zero_cmp:
  for +n: Nat
  for word: Word(n)
  ZeroView(n, word, Word.cmp(n, word, Word.zero(n)))

def zero_cmp(n, word):
  match n:
    case 0n:
      match word:
        case WNil{}:
          {==}
    case 1n+p:
      match word:
        case WCon{bit, +tail}:
          zero_step(p, tail, Word.cmp(p, tail, Word.zero(p)), zero_cmp(p, tail), bit)

# A cell whose bits 8 to 31 compare with zero as `order` (`view`) and which
# is not above 255 (`below`, where Base compares bits 0 to 7 with those of
# 255 after them) is the byte of its two digits. `order` cannot be LT, and GT
# would make the cell above 255, so it is EQ: the bits are zero, and block
# (proofs/words.bend) turns the bits of each digit back into the cell's.
law below_step:
  for +b0: Bool
  for +b1: Bool
  for +b2: Bool
  for +b3: Bool
  for +b4: Bool
  for +b5: Bool
  for +b6: Bool
  for +b7: Bool
  for +high: Word(24n)
  for order: Cmp
  for view: ZeroView(24n, high, order)
  for below: {Cmp.is_gt(Word.cmp.fin(b0, True{}, Word.cmp.fin(b1, True{}, Word.cmp.fin(b2, True{},
    Word.cmp.fin(b3, True{}, Word.cmp.fin(b4, True{}, Word.cmp.fin(b5, True{}, Word.cmp.fin(b6, True{},
    Word.cmp.fin(b7, True{}, order))))))))) == False{} : Bool}
  {Digits.Digits.to_byte(Digits.Digits.of_byte(U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6,
    WCon{b7, high}}}}}}}}})) ==
    U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, high}}}}}}}}} : U32}

def below_step(b0, b1, b2, b3, b4, b5, b6, b7, high, order, view, below):
  match order:
    case LT{}:
      Empty.absurd({Digits.Digits.to_byte(Digits.Digits.of_byte(U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4,
        WCon{b5, WCon{b6, WCon{b7, high}}}}}}}}})) == U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5,
        WCon{b6, WCon{b7, high}}}}}}}}} : U32}, view)
    case EQ{}:
      %Equal.sym(Word(24n), high, Word.zero(24n), view) : {Digits.Digits.to_byte(Digits.Digits.of_byte(U32{WCon{b0,
        WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, high}}}}}}}}})) == U32{WCon{b0, WCon{b1,
        WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, _}}}}}}}}} : U32}
      %Equal.sym(Word(28n),
        WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b4, b5, b6, b7)), WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b4, b5,
          b6, b7)), WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b4, b5, b6, b7)),
          WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b4, b5, b6, b7)), Word.zero(24n)}}}},
        WCon{b4, WCon{b5, WCon{b6, WCon{b7, Word.zero(24n)}}}},
        WordsProof.block(b4, b5, b6, b7, 24n, Word.zero(24n))) :
        {U32{WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b0,
          b1, b2, b3)), WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b0, b1, b2, b3)),
          WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b0, b1, b2, b3)), _}}}}} ==
          U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, Word.zero(24n)}}}}}}}}} : U32}
      Equal.cong(Word(32n), U32, bits => U32{bits},
        WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b0, b1,
          b2, b3)), WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b0, b1, b2, b3)),
          WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{b4, WCon{b5, WCon{b6, WCon{b7,
          Word.zero(24n)}}}}}}}},
        WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, Word.zero(24n)}}}}}}}},
        WordsProof.block(b0, b1, b2, b3, 28n, WCon{b4, WCon{b5, WCon{b6, WCon{b7, Word.zero(24n)}}}}))
    case GT{}:
      Empty.absurd({Digits.Digits.to_byte(Digits.Digits.of_byte(U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4,
        WCon{b5, WCon{b6, WCon{b7, high}}}}}}}}})) == U32{WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5,
        WCon{b6, WCon{b7, high}}}}}}}}} : U32}, BoolsProof.true_ne_false(below))

# A cell that is not above 255 is the byte of its two digits: Digits.of_byte
# reads bits 0 to 7, and bits 8 to 31, which it does not read, are zero.
# byte_step uses it.
law byte_of_cell:
  for cell: U32
  for below: {U32.is_gt(cell, 255) == False{} : Bool}
  {Digits.Digits.to_byte(Digits.Digits.of_byte(cell)) == cell : U32}

def byte_of_cell(cell, below):
  match cell:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, +high}}}}}}}}}:
      below_step(b0, b1, b2, b3, b4, b5, b6, b7, high, Word.cmp(24n, high, Word.zero(24n)), zero_cmp(24n, high), below)

# The view of Parse.byte for a cell: Unit for a failure and, for a success,
# the equation saying that the cell is the byte of the two digits returned.
def ByteView(cell: U32, result: Result<&2, &2, TC.Error, Digits.Digits(2n)>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{digits}:
      {Digits.Digits.to_byte(digits) == cell : U32}

# Whatever the check `above` found, the result that Parse.byte.checked
# builds satisfies ByteView: `checked` says what the check is, and a cell
# found not above 255 is the byte of its digits (byte_of_cell). byte_view
# passes in the computed check and `{==}`.
law byte_step:
  for +cell: U32
  for above: Bool
  for checked: {U32.is_gt(cell, 255) == above : Bool}
  for offset: Nat
  ByteView(cell, TC.Parse.byte.checked(cell, above, offset))

def byte_step(cell, above, checked, offset):
  match above:
    case True{}:
      Unit{}
    case False{}:
      byte_of_cell(cell, checked)

# Every cell that Parse.byte accepts, at any offset, is the byte of the
# digits it returns. bytes_view uses it for each cell it reads.
law byte_view:
  for +cell: U32
  for offset: Nat
  ByteView(cell, TC.Parse.byte(cell, offset))

def byte_view(cell, offset):
  byte_step(cell, U32.is_gt(cell, 255), {==}, offset)

# The view of Parse.bytes for a list of cells: Unit for a failure and, for a
# success ParsedBytes{digits, rest}, the equation saying that the bytes of the
# digits, followed by the unread rest, are the list.
def BytesView(n: Nat, bytes: List<&2, U32>, result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{TC.ParsedBytes{digits, rest}}:
      {List.append(&2, U32, Digits.Digits.to_bytes(n, digits), rest) == bytes : List<&2, U32>}

# When the first cell is the byte of `digits` (`byte_eq`) and the read of p
# bytes from `tail` satisfies BytesView, putting the two digits in front of
# that read (bytes_prepend) satisfies BytesView for 1 + p bytes read from
# Con{cell, tail}. A success rewrites the list with both equations.
law bytes_rest_step:
  for -p: Nat
  for -cell: U32
  for -tail: List<&2, U32>
  for digits: Digits.Digits(2n)
  for byte_eq: {Digits.Digits.to_byte(digits) == cell : U32}
  for rest_result: Result<&2, &2, TC.Error, TC.ParsedBytes<p>>
  for rest_view: BytesView(p, tail, rest_result)
  BytesView(1n+p, Con{cell, tail}, bytes_prepend(p, digits, rest_result))

def bytes_rest_step(p, cell, tail, digits, byte_eq, rest_result, rest_view):
  match digits:
    case Digits.DCon{+high, Digits.DCon{+low, Digits.DNil{}}}:
      match rest_result:
        case Fail{error}:
          Unit{}
        case Done{TC.ParsedBytes{+found, +rest}}:
          %rest_view : {Con{Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}),
            List.append(&2, U32, Digits.Digits.to_bytes(p, found), rest)} == Con{cell, _} : List<&2, U32>}
          %byte_eq : {Con{Digits.Digits.to_byte(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}),
            List.append(&2, U32, Digits.Digits.to_bytes(p, found), rest)} ==
            Con{_, List.append(&2, U32, Digits.Digits.to_bytes(p, found), rest)} : List<&2, U32>}
          {==}

# When the read of the first cell satisfies ByteView and the read of the
# other cells satisfies BytesView, one step of Parse.bytes (bytes_step)
# satisfies BytesView for the whole list. bytes_view passes both reads in,
# with their views, because it cannot match on them.
law bytes_byte_step:
  for -p: Nat
  for -cell: U32
  for -tail: List<&2, U32>
  for byte_result: Result<&2, &2, TC.Error, Digits.Digits(2n)>
  for byte_view: ByteView(cell, byte_result)
  for rest_result: Result<&2, &2, TC.Error, TC.ParsedBytes<p>>
  for rest_view: BytesView(p, tail, rest_result)
  BytesView(1n+p, Con{cell, tail}, bytes_step(p, byte_result, rest_result))

def bytes_byte_step(p, cell, tail, byte_result, byte_view, rest_result, rest_view):
  match byte_result:
    case Fail{error}:
      Unit{}
    case Done{digits}:
      bytes_rest_step(p, cell, tail, digits, byte_view, rest_result, rest_view)

# Whatever the list and offset, a successful read of n bytes returns digits
# whose bytes, followed by the unread rest, are the list. By induction on n.
# id_bytes_view uses it.
law bytes_view:
  for +n: Nat
  for bytes: List<&2, U32>
  for +offset: Nat
  BytesView(n, bytes, TC.Parse.bytes(n, bytes, offset))

def bytes_view(n, bytes, offset):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match bytes:
        case Nil{}:
          Unit{}
        case Con{+cell, +tail}:
          bytes_byte_step(p, cell, tail, TC.Parse.byte(cell, offset), byte_view(cell, offset),
            TC.Parse.bytes(p, tail, 1n+offset), bytes_view(p, tail, 1n+offset))

# The view of Parse.bytes_end: Unit for a failure and, for a success, the
# equation saying that the list is empty.
def BytesEndView(bytes: List<&2, U32>, result: Result<&2, &2, TC.Error, Unit>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{end}:
      {Nil{} == bytes : List<&2, U32>}

# Parse.bytes_end succeeds only on the empty list. id_bytes_digits_step uses
# it after the bytes of an ID.
law bytes_end_view:
  for bytes: List<&2, U32>
  BytesEndView(bytes, TC.Parse.bytes_end(bytes))

def bytes_end_view(bytes):
  match bytes:
    case Nil{}:
      {==}
    case Con{cell, rest}:
      Unit{}

# The view of Parse.nonzero for `digits`, as digits: Unit for a failure and,
# for a success, the equation saying that the value returned holds exactly
# those digits.
def NonZeroDigitsView(n: Nat, digits: Digits.Digits(n), result: Result<&2, &2, TC.Error, Digits.NonZero<n>>) ->
  Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.NonZero.digits(n, value) == digits : Digits.Digits(n)}

# Whatever the outcome `status` of the zero check, the result that
# Parse.nonzero_result builds from Digits.NonZero.new.checked satisfies
# NonZeroDigitsView, as ParserProof.nonzero_step shows for the text.
law nonzero_digits_step:
  for -n: Nat
  for -digits: Digits.Digits(n)
  for status: Bool
  for -evidence: {Digits.Digits.is_zero(n, digits) == status : Bool}
  for field: TC.Field
  NonZeroDigitsView(n, digits, TC.Parse.nonzero_result(n,
    Digits.NonZero.new.checked(n, digits, status, evidence), field))

def nonzero_digits_step(n, digits, status, evidence, field):
  match status:
    case True{}:
      Unit{}
    case False{}:
      {==}

# A successful nonzero check returns the digits it checked, whatever field
# it names. id_bytes_end_step uses it.
law nonzero_digits_view:
  for +n: Nat
  for +digits: Digits.Digits(n)
  for field: TC.Field
  NonZeroDigitsView(n, digits, TC.Parse.nonzero(n, digits, field))

def nonzero_digits_view(n, digits, field):
  nonzero_digits_step(n, digits, Digits.Digits.is_zero(n, digits), {==}, field)

# The view of Parse.id_bytes for a list: Unit for a failure and, for a
# success, the equation saying that the bytes of the value's digits are the
# list.
def IdBytesView(n: Nat, bytes: List<&2, U32>, result: Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>) ->
  Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.Digits.to_bytes(n, Digits.NonZero.digits(Nat.double(n), value)) == bytes : List<&2, U32>}

# The rest of Parse.id_bytes.finish, as a function of the end check's
# `result`: the nonzero check of the digits.
def id_bytes_end_result(n: Nat, digits: Digits.Digits(Nat.double(n)), field: TC.Field,
  result: Result<&2, &2, TC.Error, Unit>) -> Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>:
    end : Unit <- result
    TC.Parse.nonzero(Nat.double(n), digits, field)

# When the nonzero check of `digits` satisfies NonZeroDigitsView, its result
# satisfies IdBytesView for the bytes of `digits`. id_bytes_end_step uses it.
law id_bytes_nonzero_step:
  for -n: Nat
  for -digits: Digits.Digits(Nat.double(n))
  for result: Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>
  for view: NonZeroDigitsView(Nat.double(n), digits, result)
  IdBytesView(n, Digits.Digits.to_bytes(n, digits), result)

def id_bytes_nonzero_step(n, digits, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      Equal.cong(Digits.Digits(Nat.double(n)), List<&2, U32>, found => Digits.Digits.to_bytes(n, found),
        Digits.NonZero.digits(Nat.double(n), value), digits, view)

# When the end check of the cells after the bytes satisfies BytesEndView (a
# success means that there are none), the rest of Parse.id_bytes satisfies
# IdBytesView for the bytes of the digits followed by those cells.
# id_bytes_digits_step uses it.
law id_bytes_end_step:
  for +n: Nat
  for +digits: Digits.Digits(Nat.double(n))
  for -rest: List<&2, U32>
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, Unit>
  for view: BytesEndView(rest, result)
  IdBytesView(n, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), rest), id_bytes_end_result(n, digits, field,
    result))

# After rest becomes Nil{}, ListsProof.append_nil removes it.
def id_bytes_end_step(n, digits, rest, field, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{end}:
      %view : IdBytesView(n, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), _),
        TC.Parse.nonzero(Nat.double(n), digits, field))
      %Equal.sym(List<&2, U32>, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), Nil{}),
        Digits.Digits.to_bytes(n, digits), ListsProof.append_nil(U32, Digits.Digits.to_bytes(n, digits))) :
        IdBytesView(n, _, TC.Parse.nonzero(Nat.double(n), digits, field))
      id_bytes_nonzero_step(n, digits, TC.Parse.nonzero(Nat.double(n), digits, field),
        nonzero_digits_view(Nat.double(n), digits, field))

# When the read of n bytes satisfies BytesView, the rest of Parse.id_bytes
# (id_bytes_result) satisfies IdBytesView for the list. id_bytes_view uses
# it.
law id_bytes_digits_step:
  for +n: Nat
  for -bytes: List<&2, U32>
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>
  for view: BytesView(n, bytes, result)
  IdBytesView(n, bytes, id_bytes_result(n, field, result))

def id_bytes_digits_step(n, bytes, field, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.ParsedBytes{+digits, +rest}}:
      %view : IdBytesView(n, _, TC.Parse.id_bytes.finish(n, TC.ParsedBytes{digits, rest}, field))
      id_bytes_end_step(n, digits, rest, field, TC.Parse.bytes_end(rest), bytes_end_view(rest))

# For every list, length and field, a successful Parse.id_bytes returns
# digits whose bytes are that list. Quantified over every list, including
# every refused one. The inverse views below use it.
law id_bytes_view:
  for +n: Nat
  for +bytes: List<&2, U32>
  for +field: TC.Field
  IdBytesView(n, bytes, TC.Parse.id_bytes(n, bytes, field))

def id_bytes_view(n, bytes, field):
  id_bytes_digits_step(n, bytes, field, TC.Parse.bytes(n, bytes, 0n), bytes_view(n, bytes, 0n))

# The view of TraceId.from_bytes for a list: Unit for a failure and, for a
# success, the claim of law trace_bytes_inverse: the trace ID's bytes are the
# list. PROOF.bend's Laws.trace_bytes_inverse rewrites its hypothesis into
# it.
def TraceInverseView(bytes: List<&2, U32>, result: Result<&2, &2, TC.Error, TC.TraceId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.TraceId.to_bytes(id) == bytes : List<&2, U32>}

# When the result of Parse.id_bytes satisfies IdBytesView, the trace ID built
# from it satisfies TraceInverseView: the two equations are the same.
law trace_inverse_step:
  for -bytes: List<&2, U32>
  for result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>
  for view: IdBytesView(16n, bytes, result)
  TraceInverseView(bytes, trace_bytes_result(result))

def trace_inverse_step(bytes, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      view

# For every list, a trace ID that TraceId.from_bytes accepts has that list as
# its bytes.
law trace_inverse_view:
  for +bytes: List<&2, U32>
  TraceInverseView(bytes, TC.TraceId.from_bytes(bytes))

def trace_inverse_view(bytes):
  trace_inverse_step(bytes, TC.Parse.id_bytes(16n, bytes, TC.TraceIdField{}),
    id_bytes_view(16n, bytes, TC.TraceIdField{}))

# The same view for SpanId.from_bytes: PROOF.bend's Laws.span_bytes_inverse
# rewrites its hypothesis into it.
def SpanInverseView(bytes: List<&2, U32>, result: Result<&2, &2, TC.Error, TC.SpanId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.SpanId.to_bytes(id) == bytes : List<&2, U32>}

law span_inverse_step:
  for -bytes: List<&2, U32>
  for result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>
  for view: IdBytesView(8n, bytes, result)
  SpanInverseView(bytes, span_bytes_result(result))

def span_inverse_step(bytes, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      view

law span_inverse_view:
  for +bytes: List<&2, U32>
  SpanInverseView(bytes, TC.SpanId.from_bytes(bytes))

def span_inverse_view(bytes):
  span_inverse_step(bytes, TC.Parse.id_bytes(8n, bytes, TC.SpanIdField{}), id_bytes_view(8n, bytes, TC.SpanIdField{}))

# The text of the trace ID of a successful read, or `fallback` for a failure.
# trace_bytes_injective applies it with Equal.cong to an equation between two
# reads, to obtain an equation between their texts.
def trace_text_or(result: Result<&2, &2, TC.Error, TC.TraceId>, fallback: String) -> String:
  match result:
    case Fail{error}:
      fallback
    case Done{id}:
      TC.TraceId.to_string(id)

# Two trace IDs with the same bytes have the same text: reading the common
# bytes gives each ID's digits (trace_bytes_roundtrip), so the two reads are
# equal. PROOF.bend's Laws.trace_bytes_injective calls it.
law trace_bytes_injective:
  for left: TC.TraceId
  for right: TC.TraceId
  for same: {TC.TraceId.to_bytes(left) == TC.TraceId.to_bytes(right) : List<&2, U32>}
  {TC.TraceId.to_string(left) == TC.TraceId.to_string(right) : String}

def trace_bytes_injective(left, right, same):
  match left:
    case TC.TraceId{+left_value, +left_random}:
      match right:
        case TC.TraceId{+right_value, +right_random}:
          Equal.cong(Result<&2, &2, TC.Error, TC.TraceId>, String, result => trace_text_or(result, ""),
            Done{TC.TraceId{left_value, False{}}}, Done{TC.TraceId{right_value, False{}}},
            Equal.trans(Result<&2, &2, TC.Error, TC.TraceId>, Done{TC.TraceId{left_value, False{}}},
              TC.TraceId.from_bytes(TC.TraceId.to_bytes(TC.TraceId{right_value, right_random})),
              Done{TC.TraceId{right_value, False{}}},
              Equal.trans(Result<&2, &2, TC.Error, TC.TraceId>, Done{TC.TraceId{left_value, False{}}},
                TC.TraceId.from_bytes(TC.TraceId.to_bytes(TC.TraceId{left_value, left_random})),
                TC.TraceId.from_bytes(TC.TraceId.to_bytes(TC.TraceId{right_value, right_random})),
                Equal.sym(Result<&2, &2, TC.Error, TC.TraceId>,
                  TC.TraceId.from_bytes(TC.TraceId.to_bytes(TC.TraceId{left_value, left_random})),
                  Done{TC.TraceId{left_value, False{}}}, trace_bytes_roundtrip(left_value, left_random)),
                Equal.cong(List<&2, U32>, Result<&2, &2, TC.Error, TC.TraceId>, bytes => TC.TraceId.from_bytes(bytes),
                  TC.TraceId.to_bytes(TC.TraceId{left_value, left_random}),
                  TC.TraceId.to_bytes(TC.TraceId{right_value, right_random}), same)),
              trace_bytes_roundtrip(right_value, right_random)))

# The span ID of a successful read, or `fallback` for a failure, for the
# same use in span_bytes_injective.
def span_or(result: Result<&2, &2, TC.Error, TC.SpanId>, fallback: TC.SpanId) -> TC.SpanId:
  match result:
    case Fail{error}:
      fallback
    case Done{id}:
      id

# Two span IDs with the same bytes are the same span ID: reading the common
# bytes gives each of them back (span_bytes_roundtrip). PROOF.bend's
# Laws.span_bytes_injective calls it.
law span_bytes_injective:
  for +left: TC.SpanId
  for +right: TC.SpanId
  for same: {TC.SpanId.to_bytes(left) == TC.SpanId.to_bytes(right) : List<&2, U32>}
  {left == right : TC.SpanId}

def span_bytes_injective(left, right, same):
  Equal.cong(Result<&2, &2, TC.Error, TC.SpanId>, TC.SpanId, result => span_or(result, left), Done{left}, Done{right},
    Equal.trans(Result<&2, &2, TC.Error, TC.SpanId>, Done{left}, TC.SpanId.from_bytes(TC.SpanId.to_bytes(right)),
      Done{right},
      Equal.trans(Result<&2, &2, TC.Error, TC.SpanId>, Done{left}, TC.SpanId.from_bytes(TC.SpanId.to_bytes(left)),
        TC.SpanId.from_bytes(TC.SpanId.to_bytes(right)),
        Equal.sym(Result<&2, &2, TC.Error, TC.SpanId>, TC.SpanId.from_bytes(TC.SpanId.to_bytes(left)), Done{left},
          span_bytes_roundtrip(left)),
        Equal.cong(List<&2, U32>, Result<&2, &2, TC.Error, TC.SpanId>, bytes => TC.SpanId.from_bytes(bytes),
          TC.SpanId.to_bytes(left), TC.SpanId.to_bytes(right), same)),
      span_bytes_roundtrip(right)))

# The view of a trace ID read from bytes without a randomness assertion:
# Unit for a failure and, for a success, the claim of law bytes_unasserted.
def UnassertedView(result: Result<&2, &2, TC.Error, TC.TraceId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.TraceId.is_random(id) == False{} : Bool}

# Every trace ID that TraceId.from_bytes builds makes no randomness
# assertion, whatever its digits: it sets the random field to False.
# PROOF.bend's Laws.bytes_unasserted rewrites its hypothesis into this view.
law unasserted_view:
  for result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>
  UnassertedView(trace_bytes_result(result))

def unasserted_view(result):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      {==}

# A comparison that is not above is not greater: Cmp.is_le and Cmp.is_gt are
# opposites. By cases on the comparison. byte_accepts uses it to read
# Laws.all_bytes, which says "at most 255", as the reader's check, which asks
# "above 255".
law le_gt:
  for order: Cmp
  for le: {Cmp.is_le(order) == True{} : Bool}
  {Cmp.is_gt(order) == False{} : Bool}

def le_gt(order, le):
  match order:
    case LT{}:
      {==}
    case EQ{}:
      {==}
    case GT{}:
      BoolsProof.absurd({Cmp.is_gt(GT{}) == False{} : Bool}, le)

# A cell at most 255 is read, at any offset, as its two digits. bytes_short,
# bytes_above and bytes_suffix use it for the cells before the one they
# follow.
law byte_accepts:
  for +cell: U32
  for +offset: Nat
  for le: {U32.is_le(cell, 255) == True{} : Bool}
  {TC.Parse.byte(cell, offset) == Done{Digits.Digits.of_byte(cell)} : Result<&2, &2, TC.Error, Digits.Digits(2n)>}

def byte_accepts(cell, offset, le):
  %Equal.sym(Bool, U32.is_gt(cell, 255), False{}, le_gt(U32.cmp(cell, 255), le)) :
    {TC.Parse.byte.checked(cell, _, offset) == Done{Digits.Digits.of_byte(cell)} :
      Result<&2, &2, TC.Error, Digits.Digits(2n)>}
  {==}

# A cell above 255 is refused with InvalidByte at its offset. bytes_above
# uses it for the refused cell.
law byte_refuses:
  for +cell: U32
  for +offset: Nat
  for above: {U32.is_gt(cell, 255) == True{} : Bool}
  {TC.Parse.byte(cell, offset) == Fail{TC.InvalidByte{offset}} : Result<&2, &2, TC.Error, Digits.Digits(2n)>}

def byte_refuses(cell, offset, above):
  %Equal.sym(Bool, U32.is_gt(cell, 255), True{}, above) :
    {TC.Parse.byte.checked(cell, _, offset) == Fail{TC.InvalidByte{offset}} :
      Result<&2, &2, TC.Error, Digits.Digits(2n)>}
  {==}

# Reading n bytes from fewer than n cells, each a byte, fails with
# UnexpectedEnd at the offset after the last cell. Induction on n and the
# cells: byte_accepts reads each cell, and NatsProof.add_succ moves the
# offset's step out of the sum. The short laws use it.
law bytes_short:
  for +n: Nat
  for bytes: List<&2, U32>
  for +offset: Nat
  for +cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, bytes), n) == True{} : Bool}
  {TC.Parse.bytes(n, bytes, offset) == Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, bytes), offset)}} :
    Result<&2, &2, TC.Error, TC.ParsedBytes<n>>}

def bytes_short(n, bytes, offset, cells, short):
  match n:
    case 0n:
      match bytes:
        case Nil{}:
          BoolsProof.absurd({TC.Parse.bytes(0n, Nil{}, offset) == Fail{TC.UnexpectedEnd{offset}} :
            Result<&2, &2, TC.Error, TC.ParsedBytes<0n>>}, short)
        case Con{cell, tail}:
          BoolsProof.absurd({TC.Parse.bytes(0n, Con{cell, tail}, offset) ==
            Fail{TC.UnexpectedEnd{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
            Result<&2, &2, TC.Error, TC.ParsedBytes<0n>>}, short)
    case 1n+p:
      match bytes:
        case Nil{}:
          {==}
        case Con{+cell, +tail}:
          %Equal.sym(Result<&2, &2, TC.Error, Digits.Digits(2n)>, TC.Parse.byte(cell, offset),
            Done{Digits.Digits.of_byte(cell)}, byte_accepts(cell, offset,
              BoolsProof.and_left(U32.is_le(cell, 255), Laws.all_bytes(tail), cells))) :
            {bytes_step(p, _, TC.Parse.bytes(p, tail, 1n+offset)) ==
              Fail{TC.UnexpectedEnd{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<p>>, TC.Parse.bytes(p, tail, 1n+offset),
            Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, tail), 1n+offset)}},
            bytes_short(p, tail, 1n+offset, BoolsProof.and_right(U32.is_le(cell, 255), Laws.all_bytes(tail), cells),
              short)) :
            {bytes_prepend(p, Digits.Digits.of_byte(cell), _) ==
              Fail{TC.UnexpectedEnd{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          %NatsProof.add_succ(List.length(&2, U32, tail), offset) :
            {Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, tail), 1n+offset)}} == Fail{TC.UnexpectedEnd{_}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          {==}

# Reading n bytes from cells whose first ones, fewer than n, are bytes and
# are followed by a cell above 255 fails with InvalidByte at that cell's
# offset. Induction on n and the cells before it, as bytes_short. The above
# laws use it.
law bytes_above:
  for +n: Nat
  for before: List<&2, U32>
  for +cell: U32
  for +after: List<&2, U32>
  for +offset: Nat
  for +cells: {Laws.all_bytes(before) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, before), n) == True{} : Bool}
  for +above: {U32.is_gt(cell, 255) == True{} : Bool}
  {TC.Parse.bytes(n, List.append(&2, U32, before, Con{cell, after}), offset) ==
    Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, before), offset)}} : Result<&2, &2, TC.Error, TC.ParsedBytes<n>>}

def bytes_above(n, before, cell, after, offset, cells, short, above):
  match n:
    case 0n:
      match before:
        case Nil{}:
          BoolsProof.absurd({TC.Parse.bytes(0n, Con{cell, after}, offset) == Fail{TC.InvalidByte{offset}} :
            Result<&2, &2, TC.Error, TC.ParsedBytes<0n>>}, short)
        case Con{first, tail}:
          BoolsProof.absurd({TC.Parse.bytes(0n, Con{first, List.append(&2, U32, tail, Con{cell, after})}, offset) ==
            Fail{TC.InvalidByte{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
            Result<&2, &2, TC.Error, TC.ParsedBytes<0n>>}, short)
    case 1n+p:
      match before:
        case Nil{}:
          %Equal.sym(Result<&2, &2, TC.Error, Digits.Digits(2n)>, TC.Parse.byte(cell, offset),
            Fail{TC.InvalidByte{offset}}, byte_refuses(cell, offset, above)) :
            {bytes_step(p, _, TC.Parse.bytes(p, after, 1n+offset)) == Fail{TC.InvalidByte{offset}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          {==}
        case Con{+first, +tail}:
          %Equal.sym(Result<&2, &2, TC.Error, Digits.Digits(2n)>, TC.Parse.byte(first, offset),
            Done{Digits.Digits.of_byte(first)}, byte_accepts(first, offset,
              BoolsProof.and_left(U32.is_le(first, 255), Laws.all_bytes(tail), cells))) :
            {bytes_step(p, _, TC.Parse.bytes(p, List.append(&2, U32, tail, Con{cell, after}), 1n+offset)) ==
              Fail{TC.InvalidByte{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<p>>,
            TC.Parse.bytes(p, List.append(&2, U32, tail, Con{cell, after}), 1n+offset),
            Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, tail), 1n+offset)}},
            bytes_above(p, tail, cell, after, 1n+offset,
              BoolsProof.and_right(U32.is_le(first, 255), Laws.all_bytes(tail), cells), short, above)) :
            {bytes_prepend(p, Digits.Digits.of_byte(first), _) ==
              Fail{TC.InvalidByte{1n+Nat.add(List.length(&2, U32, tail), offset)}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          %NatsProof.add_succ(List.length(&2, U32, tail), offset) :
            {Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, tail), 1n+offset)}} == Fail{TC.InvalidByte{_}} :
              Result<&2, &2, TC.Error, TC.ParsedBytes<1n+p>>}
          {==}

# The view of a read of n bytes that must succeed and leave `suffix`: Empty
# for a failure, which cannot happen, and for a success the equation saying
# that the unread rest is `suffix`. It is Data, so that accepts_step may use
# a view more than once.
def SuffixView(n: Nat, suffix: List<&2, U32>, result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>) -> Data:
  match result:
    case Fail{error}:
      Empty
    case Done{TC.ParsedBytes{digits, rest}}:
      {rest == suffix : List<&2, U32>}

# Putting two digits in front of a read that satisfies SuffixView
# (bytes_prepend) keeps the view: the unread rest does not change.
law suffix_step:
  for -p: Nat
  for -suffix: List<&2, U32>
  for digits: Digits.Digits(2n)
  for result: Result<&2, &2, TC.Error, TC.ParsedBytes<p>>
  for view: SuffixView(p, suffix, result)
  SuffixView(1n+p, suffix, bytes_prepend(p, digits, result))

def suffix_step(p, suffix, digits, result, view):
  match digits:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      match result:
        case Fail{error}:
          view
        case Done{TC.ParsedBytes{found, rest}}:
          view

# Reading n bytes from n cells that are bytes, followed by any cells,
# succeeds and leaves those cells unread. Induction on n and the cells, with
# byte_accepts for each; a count that does not match the cells contradicts
# `count`. The long laws use it.
law bytes_suffix:
  for +n: Nat
  for bytes: List<&2, U32>
  for +suffix: List<&2, U32>
  for +offset: Nat
  for +cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for count: {List.length(&2, U32, bytes) == n : Nat}
  SuffixView(n, suffix, TC.Parse.bytes(n, List.append(&2, U32, bytes, suffix), offset))

def bytes_suffix(n, bytes, suffix, offset, cells, count):
  match n:
    case 0n:
      match bytes:
        case Nil{}:
          {==}
        case Con{cell, tail}:
          Empty.absurd(SuffixView(0n, suffix, TC.Parse.bytes(0n, Con{cell, List.append(&2, U32, tail, suffix)},
            offset)), BoolsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, Equal.cong(Nat, Bool,
              x => Nat.is_eq(x, 0n), 1n+List.length(&2, U32, tail), 0n, count))))
    case 1n+p:
      match bytes:
        case Nil{}:
          Empty.absurd(SuffixView(1n+p, suffix, TC.Parse.bytes(1n+p, suffix, offset)),
            BoolsProof.true_ne_false(Equal.cong(Nat, Bool, x => Nat.is_eq(x, 0n), 0n, 1n+p, count)))
        case Con{+cell, +tail}:
          %Equal.sym(Result<&2, &2, TC.Error, Digits.Digits(2n)>, TC.Parse.byte(cell, offset),
            Done{Digits.Digits.of_byte(cell)}, byte_accepts(cell, offset,
              BoolsProof.and_left(U32.is_le(cell, 255), Laws.all_bytes(tail), cells))) :
            SuffixView(1n+p, suffix, bytes_step(p, _, TC.Parse.bytes(p, List.append(&2, U32, tail, suffix), 1n+offset)))
          suffix_step(p, suffix, Digits.Digits.of_byte(cell),
            TC.Parse.bytes(p, List.append(&2, U32, tail, suffix), 1n+offset),
            bytes_suffix(p, tail, suffix, 1n+offset,
              BoolsProof.and_right(U32.is_le(cell, 255), Laws.all_bytes(tail), cells),
              Equal.cong(Nat, Nat, x => NatsProof.pred(x), 1n+List.length(&2, U32, tail), 1n+p, count)))

# When the read of an ID's n bytes leaves a first cell `extra` unread
# (SuffixView), the rest of Parse.id_bytes fails with TrailingInput. The long
# laws use it.
law long_step:
  for +n: Nat
  for -extra: U32
  for -more: List<&2, U32>
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>
  for view: SuffixView(n, Con{extra, more}, result)
  {id_bytes_result(n, field, result) == Fail{TC.TrailingInput{}} :
    Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}

def long_step(n, extra, more, field, result, view):
  match result:
    case Fail{error}:
      Empty.absurd({id_bytes_result(n, field, Fail{error}) == Fail{TC.TrailingInput{}} :
        Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}, view)
    case Done{TC.ParsedBytes{digits, rest}}:
      %Equal.sym(List<&2, U32>, rest, Con{extra, more}, view) :
        {id_bytes_result(n, field, Done{TC.ParsedBytes{digits, _}}) == Fail{TC.TrailingInput{}} :
          Result<&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>>}
      {==}

# Fewer than 16 bytes are refused with UnexpectedEnd at their length.
# PROOF.bend's Laws.trace_bytes_short calls it.
law trace_bytes_short:
  for +bytes: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, bytes), 16n) == True{} : Bool}
  {TC.TraceId.from_bytes(bytes) == Fail{TC.UnexpectedEnd{List.length(&2, U32, bytes)}} :
    Result<&2, &2, TC.Error, TC.TraceId>}

def trace_bytes_short(bytes, cells, short):
  %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<16n>>, TC.Parse.bytes(16n, bytes, 0n),
    Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, bytes), 0n)}}, bytes_short(16n, bytes, 0n, cells, short)) :
    {trace_bytes_result(id_bytes_result(16n, TC.TraceIdField{}, _)) ==
      Fail{TC.UnexpectedEnd{List.length(&2, U32, bytes)}} : Result<&2, &2, TC.Error, TC.TraceId>}
  %NatsProof.add_zero(List.length(&2, U32, bytes)) :
    {Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, bytes), 0n)}} == Fail{TC.UnexpectedEnd{_}} :
      Result<&2, &2, TC.Error, TC.TraceId>}
  {==}

# As trace_bytes_short, for fewer than 8 bytes. PROOF.bend's
# Laws.span_bytes_short calls it.
law span_bytes_short:
  for +bytes: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, bytes), 8n) == True{} : Bool}
  {TC.SpanId.from_bytes(bytes) == Fail{TC.UnexpectedEnd{List.length(&2, U32, bytes)}} :
    Result<&2, &2, TC.Error, TC.SpanId>}

def span_bytes_short(bytes, cells, short):
  %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<8n>>, TC.Parse.bytes(8n, bytes, 0n),
    Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, bytes), 0n)}}, bytes_short(8n, bytes, 0n, cells, short)) :
    {span_bytes_result(id_bytes_result(8n, TC.SpanIdField{}, _)) ==
      Fail{TC.UnexpectedEnd{List.length(&2, U32, bytes)}} : Result<&2, &2, TC.Error, TC.SpanId>}
  %NatsProof.add_zero(List.length(&2, U32, bytes)) :
    {Fail{TC.UnexpectedEnd{Nat.add(List.length(&2, U32, bytes), 0n)}} == Fail{TC.UnexpectedEnd{_}} :
      Result<&2, &2, TC.Error, TC.SpanId>}
  {==}

# 16 bytes followed by any cell are refused with TrailingInput. PROOF.bend's
# Laws.trace_bytes_long calls it.
law trace_bytes_long:
  for +bytes: List<&2, U32>
  for +extra: U32
  for +more: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for sixteen: {List.length(&2, U32, bytes) == 16n : Nat}
  {TC.TraceId.from_bytes(List.append(&2, U32, bytes, Con{extra, more})) == Fail{TC.TrailingInput{}} :
    Result<&2, &2, TC.Error, TC.TraceId>}

def trace_bytes_long(bytes, extra, more, cells, sixteen):
  Equal.cong(Result<&2, &2, TC.Error, Digits.NonZero<32n>>, Result<&2, &2, TC.Error, TC.TraceId>,
    result => trace_bytes_result(result),
    id_bytes_result(16n, TC.TraceIdField{}, TC.Parse.bytes(16n, List.append(&2, U32, bytes, Con{extra, more}), 0n)),
    Fail{TC.TrailingInput{}},
    long_step(16n, extra, more, TC.TraceIdField{},
      TC.Parse.bytes(16n, List.append(&2, U32, bytes, Con{extra, more}), 0n),
      bytes_suffix(16n, bytes, Con{extra, more}, 0n, cells, sixteen)))

# As trace_bytes_long, for 8 bytes. PROOF.bend's Laws.span_bytes_long calls
# it.
law span_bytes_long:
  for +bytes: List<&2, U32>
  for +extra: U32
  for +more: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for eight: {List.length(&2, U32, bytes) == 8n : Nat}
  {TC.SpanId.from_bytes(List.append(&2, U32, bytes, Con{extra, more})) == Fail{TC.TrailingInput{}} :
    Result<&2, &2, TC.Error, TC.SpanId>}

def span_bytes_long(bytes, extra, more, cells, eight):
  Equal.cong(Result<&2, &2, TC.Error, Digits.NonZero<16n>>, Result<&2, &2, TC.Error, TC.SpanId>,
    result => span_bytes_result(result),
    id_bytes_result(8n, TC.SpanIdField{}, TC.Parse.bytes(8n, List.append(&2, U32, bytes, Con{extra, more}), 0n)),
    Fail{TC.TrailingInput{}},
    long_step(8n, extra, more, TC.SpanIdField{},
      TC.Parse.bytes(8n, List.append(&2, U32, bytes, Con{extra, more}), 0n),
      bytes_suffix(8n, bytes, Con{extra, more}, 0n, cells, eight)))

# A cell above 255 among the first 16 is refused at its offset. PROOF.bend's
# Laws.trace_bytes_above calls it.
law trace_bytes_above:
  for +before: List<&2, U32>
  for +cell: U32
  for +after: List<&2, U32>
  for cells: {Laws.all_bytes(before) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, before), 16n) == True{} : Bool}
  for above: {U32.is_gt(cell, 255) == True{} : Bool}
  {TC.TraceId.from_bytes(List.append(&2, U32, before, Con{cell, after})) ==
    Fail{TC.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, TC.Error, TC.TraceId>}

def trace_bytes_above(before, cell, after, cells, short, above):
  %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<16n>>,
    TC.Parse.bytes(16n, List.append(&2, U32, before, Con{cell, after}), 0n),
    Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, before), 0n)}},
    bytes_above(16n, before, cell, after, 0n, cells, short, above)) :
    {trace_bytes_result(id_bytes_result(16n, TC.TraceIdField{}, _)) ==
      Fail{TC.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, TC.Error, TC.TraceId>}
  %NatsProof.add_zero(List.length(&2, U32, before)) :
    {Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, before), 0n)}} == Fail{TC.InvalidByte{_}} :
      Result<&2, &2, TC.Error, TC.TraceId>}
  {==}

# As trace_bytes_above, among the first 8 cells. PROOF.bend's
# Laws.span_bytes_above calls it.
law span_bytes_above:
  for +before: List<&2, U32>
  for +cell: U32
  for +after: List<&2, U32>
  for cells: {Laws.all_bytes(before) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, before), 8n) == True{} : Bool}
  for above: {U32.is_gt(cell, 255) == True{} : Bool}
  {TC.SpanId.from_bytes(List.append(&2, U32, before, Con{cell, after})) ==
    Fail{TC.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, TC.Error, TC.SpanId>}

def span_bytes_above(before, cell, after, cells, short, above):
  %Equal.sym(Result<&2, &2, TC.Error, TC.ParsedBytes<8n>>,
    TC.Parse.bytes(8n, List.append(&2, U32, before, Con{cell, after}), 0n),
    Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, before), 0n)}},
    bytes_above(8n, before, cell, after, 0n, cells, short, above)) :
    {span_bytes_result(id_bytes_result(8n, TC.SpanIdField{}, _)) ==
      Fail{TC.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, TC.Error, TC.SpanId>}
  %NatsProof.add_zero(List.length(&2, U32, before)) :
    {Fail{TC.InvalidByte{Nat.add(List.length(&2, U32, before), 0n)}} == Fail{TC.InvalidByte{_}} :
      Result<&2, &2, TC.Error, TC.SpanId>}
  {==}

# A digit that Hex.Digit.is_zero calls zero is H0. Sixteen cases; for the
# other fifteen, the hypothesis computes to a clash. zero_cells uses it for
# the two digits of each byte.
law digit_zero:
  for digit: Hex.Digit
  for zero: {Hex.Digit.is_zero(digit) == True{} : Bool}
  {digit == Hex.H0{} : Hex.Digit}

def digit_zero(digit, zero):
  match digit:
    case Hex.H0{}:
      {==}
    case Hex.H1{}:
      BoolsProof.absurd({Hex.H1{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H2{}:
      BoolsProof.absurd({Hex.H2{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H3{}:
      BoolsProof.absurd({Hex.H3{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H4{}:
      BoolsProof.absurd({Hex.H4{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H5{}:
      BoolsProof.absurd({Hex.H5{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H6{}:
      BoolsProof.absurd({Hex.H6{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H7{}:
      BoolsProof.absurd({Hex.H7{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H8{}:
      BoolsProof.absurd({Hex.H8{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.H9{}:
      BoolsProof.absurd({Hex.H9{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.Ha{}:
      BoolsProof.absurd({Hex.Ha{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.Hb{}:
      BoolsProof.absurd({Hex.Hb{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.Hc{}:
      BoolsProof.absurd({Hex.Hc{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.Hd{}:
      BoolsProof.absurd({Hex.Hd{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.He{}:
      BoolsProof.absurd({Hex.He{} == Hex.H0{} : Hex.Digit}, zero)
    case Hex.Hf{}:
      BoolsProof.absurd({Hex.Hf{} == Hex.H0{} : Hex.Digit}, zero)

# The bytes of 2n digits that are all zero are all zero. Induction on n:
# each byte's two digits are H0 (digit_zero), so the byte is 0.
# nonzero_accepts uses it.
law zero_cells:
  for +n: Nat
  for digits: Digits.Digits(Nat.double(n))
  for +zero: {Digits.Digits.is_zero(Nat.double(n), digits) == True{} : Bool}
  {Laws.all_zero(Digits.Digits.to_bytes(n, digits)) == True{} : Bool}

def zero_cells(n, digits, zero):
  match n:
    case 0n:
      match digits:
        case Digits.DNil{}:
          {==}
    case 1n+p:
      match digits:
        case Digits.DCon{+high, Digits.DCon{+low, +rest}}:
          +others = BoolsProof.and_right(Hex.Digit.is_zero(high),
            Digits.Digits.is_zero(1n+Nat.double(p), Digits.DCon{low, rest}), zero)
          %Equal.sym(Hex.Digit, high, Hex.H0{}, digit_zero(high, BoolsProof.and_left(Hex.Digit.is_zero(high),
            Digits.Digits.is_zero(1n+Nat.double(p), Digits.DCon{low, rest}), zero))) :
            {Bool.and(U32.is_zero(Digits.Digits.to_byte(Digits.DCon{_, Digits.DCon{low, Digits.DNil{}}})),
              Laws.all_zero(Digits.Digits.to_bytes(p, rest))) == True{} : Bool}
          %Equal.sym(Hex.Digit, low, Hex.H0{}, digit_zero(low, BoolsProof.and_left(Hex.Digit.is_zero(low),
            Digits.Digits.is_zero(Nat.double(p), rest), others))) :
            {Bool.and(U32.is_zero(Digits.Digits.to_byte(Digits.DCon{Hex.H0{}, Digits.DCon{_, Digits.DNil{}}})),
              Laws.all_zero(Digits.Digits.to_bytes(p, rest))) == True{} : Bool}
          zero_cells(p, rest, BoolsProof.and_right(Hex.Digit.is_zero(low), Digits.Digits.is_zero(Nat.double(p), rest),
            others))

# Whatever the zero check `status` of the digits found, the nonzero check
# accepts them when their bytes are not all zero (`nonzero`): a True
# `status` would make the bytes all zero (zero_cells). accepts_step uses it.
law nonzero_accepts:
  for +n: Nat
  for +digits: Digits.Digits(Nat.double(n))
  for field: TC.Field
  for status: Bool
  for evidence: {Digits.Digits.is_zero(Nat.double(n), digits) == status : Bool}
  for nonzero: {Laws.all_zero(Digits.Digits.to_bytes(n, digits)) == False{} : Bool}
  {Result.is_done(&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>, TC.Parse.nonzero_result(Nat.double(n),
    Digits.NonZero.new.checked(Nat.double(n), digits, status, evidence), field)) == True{} : Bool}

def nonzero_accepts(n, digits, field, status, evidence, nonzero):
  match status:
    case False{}:
      {==}
    case True{}:
      Empty.absurd({False{} == True{} : Bool}, BoolsProof.true_ne_false(Equal.trans(Bool, True{},
        Laws.all_zero(Digits.Digits.to_bytes(n, digits)), False{},
        Equal.sym(Bool, Laws.all_zero(Digits.Digits.to_bytes(n, digits)), True{}, zero_cells(n, digits, evidence)),
        nonzero)))

# When the read of n bytes succeeds with no cell left (SuffixView), and its
# bytes are the list (BytesView), which is not all zero, the rest of
# Parse.id_bytes accepts it. The acceptance laws use it.
law accepts_step:
  for +n: Nat
  for -bytes: List<&2, U32>
  for field: TC.Field
  for result: Result<&2, &2, TC.Error, TC.ParsedBytes<n>>
  for +suffix: SuffixView(n, Nil{}, result)
  for view: BytesView(n, bytes, result)
  for nonzero: {Laws.all_zero(bytes) == False{} : Bool}
  {Result.is_done(&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>, id_bytes_result(n, field, result)) == True{} :
    Bool}

def accepts_step(n, bytes, field, result, suffix, view, nonzero):
  match result:
    case Fail{error}:
      Empty.absurd({Result.is_done(&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>,
        id_bytes_result(n, field, Fail{error})) == True{} : Bool}, suffix)
    case Done{TC.ParsedBytes{+digits, +rest}}:
      %Equal.sym(List<&2, U32>, rest, Nil{}, suffix) :
        {Result.is_done(&2, &2, TC.Error, Digits.NonZero<Nat.double(n)>, id_bytes_result(n, field,
          Done{TC.ParsedBytes{digits, _}})) == True{} : Bool}
      nonzero_accepts(n, digits, field, Digits.Digits.is_zero(Nat.double(n), digits), {==},
        Equal.trans(Bool, Laws.all_zero(Digits.Digits.to_bytes(n, digits)), Laws.all_zero(bytes), False{},
          Equal.cong(List<&2, U32>, Bool, cells => Laws.all_zero(cells), Digits.Digits.to_bytes(n, digits), bytes,
            Equal.trans(List<&2, U32>, Digits.Digits.to_bytes(n, digits),
              List.append(&2, U32, Digits.Digits.to_bytes(n, digits), rest), bytes,
              Equal.trans(List<&2, U32>, Digits.Digits.to_bytes(n, digits),
                List.append(&2, U32, Digits.Digits.to_bytes(n, digits), Nil{}),
                List.append(&2, U32, Digits.Digits.to_bytes(n, digits), rest),
                Equal.sym(List<&2, U32>, List.append(&2, U32, Digits.Digits.to_bytes(n, digits), Nil{}),
                  Digits.Digits.to_bytes(n, digits), ListsProof.append_nil(U32, Digits.Digits.to_bytes(n, digits))),
                Equal.cong(List<&2, U32>, List<&2, U32>,
                  tail => List.append(&2, U32, Digits.Digits.to_bytes(n, digits), tail), Nil{}, rest,
                  Equal.sym(List<&2, U32>, rest, Nil{}, suffix))),
              view)),
          nonzero))

# A successful result of Parse.id_bytes stays a success once it is made a
# trace ID. trace_bytes_accepts uses it.
law trace_done:
  for result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>
  for done: {Result.is_done(&2, &2, TC.Error, Digits.NonZero<32n>, result) == True{} : Bool}
  {Result.is_done(&2, &2, TC.Error, TC.TraceId, trace_bytes_result(result)) == True{} : Bool}

def trace_done(result, done):
  match result:
    case Fail{error}:
      done
    case Done{value}:
      {==}

# The same for a span ID. span_bytes_accepts uses it.
law span_done:
  for result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>
  for done: {Result.is_done(&2, &2, TC.Error, Digits.NonZero<16n>, result) == True{} : Bool}
  {Result.is_done(&2, &2, TC.Error, TC.SpanId, span_bytes_result(result)) == True{} : Bool}

def span_done(result, done):
  match result:
    case Fail{error}:
      done
    case Done{value}:
      {==}

# Every list of 16 bytes, not all zero, is accepted: the bytes are read with
# no cell left (bytes_suffix), their digits are those of the list
# (bytes_view), and the list is not all zero. PROOF.bend's
# Laws.trace_bytes_accepts calls it.
law trace_bytes_accepts:
  for +bytes: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for sixteen: {List.length(&2, U32, bytes) == 16n : Nat}
  for nonzero: {Laws.all_zero(bytes) == False{} : Bool}
  {Result.is_done(&2, &2, TC.Error, TC.TraceId, TC.TraceId.from_bytes(bytes)) == True{} : Bool}

def trace_bytes_accepts(bytes, cells, sixteen, nonzero):
  %ListsProof.append_nil(U32, bytes) :
    {Result.is_done(&2, &2, TC.Error, TC.TraceId, trace_bytes_result(id_bytes_result(16n, TC.TraceIdField{},
      TC.Parse.bytes(16n, _, 0n)))) == True{} : Bool}
  trace_done(id_bytes_result(16n, TC.TraceIdField{}, TC.Parse.bytes(16n, List.append(&2, U32, bytes, Nil{}), 0n)),
    accepts_step(16n, List.append(&2, U32, bytes, Nil{}), TC.TraceIdField{},
      TC.Parse.bytes(16n, List.append(&2, U32, bytes, Nil{}), 0n), bytes_suffix(16n, bytes, Nil{}, 0n, cells, sixteen),
      bytes_view(16n, List.append(&2, U32, bytes, Nil{}), 0n),
      Equal.trans(Bool, Laws.all_zero(List.append(&2, U32, bytes, Nil{})), Laws.all_zero(bytes), False{},
        Equal.cong(List<&2, U32>, Bool, list => Laws.all_zero(list), List.append(&2, U32, bytes, Nil{}), bytes,
          ListsProof.append_nil(U32, bytes)),
        nonzero)))

# As trace_bytes_accepts, for 8 bytes. PROOF.bend's Laws.span_bytes_accepts
# calls it.
law span_bytes_accepts:
  for +bytes: List<&2, U32>
  for cells: {Laws.all_bytes(bytes) == True{} : Bool}
  for eight: {List.length(&2, U32, bytes) == 8n : Nat}
  for nonzero: {Laws.all_zero(bytes) == False{} : Bool}
  {Result.is_done(&2, &2, TC.Error, TC.SpanId, TC.SpanId.from_bytes(bytes)) == True{} : Bool}

def span_bytes_accepts(bytes, cells, eight, nonzero):
  %ListsProof.append_nil(U32, bytes) :
    {Result.is_done(&2, &2, TC.Error, TC.SpanId, span_bytes_result(id_bytes_result(8n, TC.SpanIdField{},
      TC.Parse.bytes(8n, _, 0n)))) == True{} : Bool}
  span_done(id_bytes_result(8n, TC.SpanIdField{}, TC.Parse.bytes(8n, List.append(&2, U32, bytes, Nil{}), 0n)),
    accepts_step(8n, List.append(&2, U32, bytes, Nil{}), TC.SpanIdField{},
      TC.Parse.bytes(8n, List.append(&2, U32, bytes, Nil{}), 0n), bytes_suffix(8n, bytes, Nil{}, 0n, cells, eight),
      bytes_view(8n, List.append(&2, U32, bytes, Nil{}), 0n),
      Equal.trans(Bool, Laws.all_zero(List.append(&2, U32, bytes, Nil{})), Laws.all_zero(bytes), False{},
        Equal.cong(List<&2, U32>, Bool, list => Laws.all_zero(list), List.append(&2, U32, bytes, Nil{}), bytes,
          ListsProof.append_nil(U32, bytes)),
        nonzero)))
