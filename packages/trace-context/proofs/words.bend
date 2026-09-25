import Base
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ../LAWS.bend as Laws

# Four bits survive the trip through their hexadecimal digit.
law block:
  for +b0: Bool
  for +b1: Bool
  for +b2: Bool
  for +b3: Bool
  for -q: Nat
  for -rest: Word(q)
  {WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b0, b1, b2, b3)), rest}}}} ==
    WCon{b0, WCon{b1, WCon{b2, WCon{b3, rest}}}} : Word(4n+q)}

def block(b0, b1, b2, b3, q, rest):
  match b0 b1 b2 b3:
    case False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{}:
      {==}

# Rebuild every four-bit block of a word from its digit.
def renibble(k: Nat, word: Word(Nat.mul(k, 4n))) -> Word(Nat.mul(k, 4n)):
  match k:
    case 0n:
      word
    case 1n+p:
      match word:
        case WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, rest}}}}:
          WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b0, b1, b2, b3)),
            WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b0, b1, b2, b3)),
            WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b0, b1, b2, b3)),
            WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b0, b1, b2, b3)), renibble(p, rest)}}}}

law renibble_id:
  for +k: Nat
  for word: Word(Nat.mul(k, 4n))
  {renibble(k, word) == word : Word(Nat.mul(k, 4n))}

def renibble_id(k, word):
  match k:
    case 0n:
      match word:
        case WNil{}:
          {==}
    case 1n+p:
      match word:
        case WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, +rest}}}}:
          %Equal.sym(Word(Nat.mul(p, 4n)), renibble(p, rest), rest, renibble_id(p, rest)) :
            {WCon{Hex.Digit.is_odd(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit1(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit2(Hex.Digit.from_bits(b0, b1, b2, b3)), WCon{Hex.Digit.has_bit3(Hex.Digit.from_bits(b0, b1, b2, b3)), _}}}} ==
              WCon{b0, WCon{b1, WCon{b2, WCon{b3, rest}}}} : Word(4n+Nat.mul(p, 4n))}
          block(b0, b1, b2, b3, Nat.mul(p, 4n), rest)

# No information is lost: every word is recovered from its eight digits.
law u32_roundtrip:
  for word: U32
  {Digits.Digits.to_u32(Digits.Digits.of_u32(word)) == word : U32}

def u32_roundtrip(word):
  match word:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, WCon{+b8, WCon{+b9, WCon{+b10, WCon{+b11, WCon{+b12, WCon{+b13, WCon{+b14, WCon{+b15, WCon{+b16, WCon{+b17, WCon{+b18, WCon{+b19, WCon{+b20, WCon{+b21, WCon{+b22, WCon{+b23, WCon{+b24, WCon{+b25, WCon{+b26, WCon{+b27, WCon{+b28, WCon{+b29, WCon{+b30, WCon{+b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      Equal.cong(Word(32n), U32, bits => U32{bits},
        renibble(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}},
        renibble_id(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))

# Four bits add their digit's value below sixteen times the rest of the word,
# as Base values a word: its first bit is the least significant.
law nibble_value:
  for +b0: Bool
  for +b1: Bool
  for +b2: Bool
  for +b3: Bool
  for -q: Nat
  for -rest: Word(q)
  {Word.to_nat(4n+q, WCon{b0, WCon{b1, WCon{b2, WCon{b3, rest}}}}) ==
    Nat.add(Laws.hex_digit_value("0123456789abcdef", Hex.Digit.to_char(Hex.Digit.from_bits(b0, b1, b2, b3)), 0n),
      Laws.times16(Word.to_nat(q, rest))) : Nat}

def nibble_value(b0, b1, b2, b3, q, rest):
  match b0 b1 b2 b3:
    case False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{}:
      {==}
    case True{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} True{}:
      {==}
    case False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} True{}:
      {==}

# A word of 4k bits valued one digit at a time, the lowest digit first.
def nibbles_value(k: Nat, word: Word(Nat.mul(k, 4n))) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+p:
      match word:
        case WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, rest}}}}:
          Nat.add(Laws.hex_digit_value("0123456789abcdef", Hex.Digit.to_char(Hex.Digit.from_bits(b0, b1, b2, b3)), 0n),
            Laws.times16(nibbles_value(p, rest)))

law nibbles_to_nat:
  for +k: Nat
  for word: Word(Nat.mul(k, 4n))
  {Word.to_nat(Nat.mul(k, 4n), word) == nibbles_value(k, word) : Nat}

def nibbles_to_nat(k, word):
  match k:
    case 0n:
      match word:
        case WNil{}:
          {==}
    case 1n+p:
      match word:
        case WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, +rest}}}}:
          %nibbles_to_nat(p, rest) :
            {Word.to_nat(4n+Nat.mul(p, 4n), WCon{b0, WCon{b1, WCon{b2, WCon{b3, rest}}}}) ==
              Nat.add(Laws.hex_digit_value("0123456789abcdef", Hex.Digit.to_char(Hex.Digit.from_bits(b0, b1, b2, b3)), 0n),
                Laws.times16(_)) : Nat}
          nibble_value(b0, b1, b2, b3, Nat.mul(p, 4n), rest)

# Reading a word's eight digits as a base-16 numeral, most significant first,
# gives the word's value.
law word_value:
  for word: U32
  {Laws.hex_numeral(Digits.Digits.to_string(8n, Digits.Digits.of_u32(word)), 0n) == U32.to_nat(word) : Nat}

def word_value(word):
  match word:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, WCon{+b8, WCon{+b9, WCon{+b10, WCon{+b11, WCon{+b12, WCon{+b13, WCon{+b14, WCon{+b15, WCon{+b16, WCon{+b17, WCon{+b18, WCon{+b19, WCon{+b20, WCon{+b21, WCon{+b22, WCon{+b23, WCon{+b24, WCon{+b25, WCon{+b26, WCon{+b27, WCon{+b28, WCon{+b29, WCon{+b30, WCon{+b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      Equal.sym(Nat, Word.to_nat(32n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        nibbles_value(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        nibbles_to_nat(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))
