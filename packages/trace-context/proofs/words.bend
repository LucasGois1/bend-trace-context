# Proofs: words and their hexadecimal digits
# ==========================================
#
# Digits.of_u32 (src/digits.bend) turns a 32-bit word into eight
# hexadecimal digits, most significant first, and U32.to_hex formats them.
# This module proves the two facts about that conversion that section 5 of
# LAWS.bend needs. No information is lost: Digits.to_u32 gives the word back
# (u32_roundtrip), which ConversionProof.hex_injective
# (proofs/conversion.bend) uses for law hex_injective. And the digits, read
# as a base-16 numeral, are the word's value (word_value), which is law
# word_hex: Laws.word_hex in PROOF.bend calls it. That law measures the
# package with an independent reading of hexadecimal text defined in
# LAWS.bend: hex_digit_value, times16 and hex_numeral.
#
# Strategy: one four-bit block at a time. Base keeps a word's bits least
# significant first, and each digit holds four of them. block and
# nibble_value are case analyses of one block over its sixteen values;
# renibble and nibbles_value restate the conversion for a word of 4k bits,
# so that renibble_id and nibbles_to_nat can be proved by induction on k.
# The two main lemmas name the 32 bits of the word, so that both sides of
# the goal compute, and apply these inductions with k = 8.

import Base
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ../LAWS.bend as Laws

# Four bits survive the trip through their hexadecimal digit: making the
# digit with Hex.Digit.from_bits and reading back its bits (is_odd,
# has_bit1, has_bit2, has_bit3) gives the same four bits, in front of any
# rest of a word. Sixteen cases, each by computation. Used by renibble_id.
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

# Rebuilds a word of 4k bits block by block: each group of four bits, from
# the least significant end, becomes its digit and then bits again. With the
# 32 bits of a word named, U32{renibble(8n, bits)} is what
# Digits.to_u32(Digits.of_u32(U32{bits})) computes, so u32_roundtrip
# reduces to renibble_id.
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

# Rebuilding every block leaves a word of 4k bits unchanged. Induction on k:
# the recursive call rewrites the rebuilt rest back to `rest`, and block
# settles the first four bits. Used by u32_roundtrip with k = 8.
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

# No information is lost: every word is recovered from its eight digits, as
# Digits.to_u32 inverts Digits.of_u32. ConversionProof.hex_injective
# (proofs/conversion.bend) uses it for law hex_injective.
law u32_roundtrip:
  for word: U32
  {Digits.Digits.to_u32(Digits.Digits.of_u32(word)) == word : U32}

# Names the 32 bits so the goal computes; Equal.cong lifts renibble_id to U32.
def u32_roundtrip(word):
  match word:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, WCon{+b8, WCon{+b9, WCon{+b10, WCon{+b11, WCon{+b12, WCon{+b13, WCon{+b14, WCon{+b15, WCon{+b16, WCon{+b17, WCon{+b18, WCon{+b19, WCon{+b20, WCon{+b21, WCon{+b22, WCon{+b23, WCon{+b24, WCon{+b25, WCon{+b26, WCon{+b27, WCon{+b28, WCon{+b29, WCon{+b30, WCon{+b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      Equal.cong(Word(32n), U32, bits => U32{bits},
        renibble(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}},
        renibble_id(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))

# The value of a word that starts with four bits is their digit's value plus
# 16 times the value of the rest: Base values a word with its first bit as
# the least significant (Word.to_nat). The digit's value is read from its
# character with Laws.hex_digit_value, so the package's digits are measured
# by the laws' own reader. Sixteen cases, each by computation. Used by
# nibbles_to_nat.
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

# The value of a word of 4k bits computed one digit at a time, the lowest
# digit first: the value of the first block's digit (Laws.hex_digit_value)
# plus 16 times the value of the other blocks (Laws.times16). For k = 8 it
# computes the same number as Laws.hex_numeral reading the word's eight
# digits most significant first, which word_value relies on.
def nibbles_value(k: Nat, word: Word(Nat.mul(k, 4n))) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+p:
      match word:
        case WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, rest}}}}:
          Nat.add(Laws.hex_digit_value("0123456789abcdef", Hex.Digit.to_char(Hex.Digit.from_bits(b0, b1, b2, b3)), 0n),
            Laws.times16(nibbles_value(p, rest)))

# Base's value of a word of 4k bits is its digit-by-digit value,
# nibbles_value. Induction on k: the recursive call rewrites the value of
# the rest, and nibble_value handles the first four bits. Used by
# word_value with k = 8.
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

# Reading a word's eight digits as a base-16 numeral, most significant
# first, gives the word's value. This is law word_hex, since U32.to_hex is
# Digits.to_string of Digits.of_u32: Laws.word_hex (PROOF.bend) calls it.
law word_value:
  for word: U32
  {Laws.hex_numeral(Digits.Digits.to_string(8n, Digits.Digits.of_u32(word)), 0n) == U32.to_nat(word) : Nat}

# Names the 32 bits: then Equal.sym of nibbles_to_nat(8n, bits) is the goal.
def word_value(word):
  match word:
    case U32{WCon{+b0, WCon{+b1, WCon{+b2, WCon{+b3, WCon{+b4, WCon{+b5, WCon{+b6, WCon{+b7, WCon{+b8, WCon{+b9, WCon{+b10, WCon{+b11, WCon{+b12, WCon{+b13, WCon{+b14, WCon{+b15, WCon{+b16, WCon{+b17, WCon{+b18, WCon{+b19, WCon{+b20, WCon{+b21, WCon{+b22, WCon{+b23, WCon{+b24, WCon{+b25, WCon{+b26, WCon{+b27, WCon{+b28, WCon{+b29, WCon{+b30, WCon{+b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      Equal.sym(Nat, Word.to_nat(32n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        nibbles_value(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}),
        nibbles_to_nat(8n, WCon{b0, WCon{b1, WCon{b2, WCon{b3, WCon{b4, WCon{b5, WCon{b6, WCon{b7, WCon{b8, WCon{b9, WCon{b10, WCon{b11, WCon{b12, WCon{b13, WCon{b14, WCon{b15, WCon{b16, WCon{b17, WCon{b18, WCon{b19, WCon{b20, WCon{b21, WCon{b22, WCon{b23, WCon{b24, WCon{b25, WCon{b26, WCon{b27, WCon{b28, WCon{b29, WCon{b30, WCon{b31, WNil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}))
