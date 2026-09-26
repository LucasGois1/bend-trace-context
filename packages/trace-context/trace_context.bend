# bend-trace-context: the pure Trace Context core
# ===============================================
#
# This file is the package's public entry for everything that performs no host
# effect: the strict traceparent v00 codec, validated trace and span IDs, local
# and remote contexts, the machine that turns source words into IDs, validated
# limits, the Level 2 tracestate parser, tracestate updates and emission, and
# outgoing contexts. generation.bend adds the host's cryptographic source on
# top of it. The claims this code must satisfy are stated in LAWS.bend and
# proved in PROOF.bend, beside this file. The tests in tests/*.bend here and
# the repository's consumer in tests/consumer exercise it through the same
# public names.
#
# The normative reference is W3C Trace Context Level 2, Candidate
# Recommendation Draft of 2024-03-28 ("W3C" below, with section numbers). The
# approved specification is issue #1 of the repository ("spec #1").
#
# Contents
#
#   Types                            every data type of the codec, contexts and
#                                    generation, declared first
#   Strict v00 codec                 Parse.*, TraceParentV00.*
#   Identifiers and contexts         TraceId, SpanId, contexts, children,
#                                    restarts
#   Identifiers from source words    U32.to_hex, TraceId.from_words, ...
#   Generation machine               Draw.*, Step.*, Context.*_with,
#                                    Source.tape
#   Error messages                   Error.show, ContextError.show, ...
#   Limits                           Limits.new, Limits.default, accessors
#   Tracestate                       keys and values, states and lookups,
#                                    budgets, and the reading machine behind
#                                    TraceState.parse
#   Tracestate updates and emission  TraceState.set, remove, size and
#                                    truncate
#   Outgoing contexts                OutgoingContext, a local context with the
#                                    state it sends, and its Emission
#
# The public names are documented in packages/trace-context/README.md. Names in
# the Parse, Draw, Step, Tape, Scan, Member, Value, Budget, Utf8, Entries and
# StateChar namespaces are internal: Bend lets any module import them, but they
# are not a compatibility contract.
#
# Notes for readers new to Bend
# -----------------------------
#
# - `type T is Data:` declares a type whose values may be copied. Each indented
#   line is a constructor with its fields, such as `Some{value}`.
# - A field whose type is an equation, such as
#   `evidence: {StateKey.is_valid(text) == True{} : Bool}`, stores a proof. A
#   value can only be built together with that proof, so the rule holds for
#   every value a program handles, and code that receives one never checks it
#   again. The checker verifies the proof when the program is compiled. The
#   `.checked` helpers turn the result of a run-time check into such a proof:
#   they receive the Bool and an equation stating what it is, and matching on
#   the Bool refines that equation to `... == True{}` in the accepting case.
# - `Result<&2, &2, E, T>` is Done{value} or Fail{error}, and `Maybe<&2, T>` is
#   Some{value} or None{}. The `&2` arguments say that the values may be copied.
# - A parameter may be used at most once unless it is marked `+x` (reusable).
#   `-x` is erased: only the checker sees it. `~f` is a template: its argument
#   is substituted at compile time, so it names top-level definitions only.
# - `match` may only inspect a parameter or a variable bound by a pattern, never
#   a computed value, and definitions may not call each other in a cycle. Many
#   helpers therefore receive a Bool computed by their caller and match on it:
#   `Scan.read(comma, ...)` receives `Char.is_eq(char, ',')`, for example.
# - In every recursive call, the first argument that changes must be
#   structurally smaller, so every function terminates. A recursion whose depth
#   could grow with received text is written as a tail call, which compiles to
#   a loop: the JavaScript backend overflows its stack after a few thousand
#   nested calls, and a received value may be 32 KiB long. The other
#   recursions are bounded: at most 32 digits, 256 characters of a key or
#   value, or 32 entries.
# - `do Result<...>:` sequences steps that may fail: `x : T <- step` stops at
#   the first Fail, and the block ends with `return v` or with a last step.

import Base
import ./src/hex.bend as Hex
import ./src/digits.bend as Digits

# Types
# =====
#
# The types of the codec, of the identifiers and contexts, and of the
# generation machine. The limits and tracestate types are declared in their
# own sections below.

# The field that a ZeroId error names: the trace ID or parent ID of a
# traceparent value, or a supplied span ID.
type Field is Data:
  TraceIdField{}
  ParentIdField{}
  SpanIdField{}

# Why the strict codec, TraceId.parse or SpanId.parse refused a text. Offsets
# count Bend characters (Unicode code points) from zero at the start of the
# text, and the first problem in reading order is reported.
#   UnexpectedEnd{offset}        the text ends where a character is required
#   InvalidHex{offset}           this character is not a lowercase hex digit
#   ExpectedSeparator{offset}    this character should be "-"
#   TrailingInput{}              characters follow a complete value
#   ForbiddenVersion{}           the version is ff, forbidden by W3C 3.2.2.1
#   UnsupportedVersion{version}  a version other than 00, which the strict
#                                codec does not read (header extraction, #9,
#                                will read later versions by their known
#                                prefix)
#   ZeroId{field}                the named ID is all zero, forbidden by W3C
#                                3.2.2.3 and 3.2.2.4
type Error is Data:
  UnexpectedEnd{offset: Nat}
  InvalidHex{offset: Nat}
  ExpectedSeparator{offset: Nat}
  TrailingInput{}
  ForbiddenVersion{}
  UnsupportedVersion{version: String}
  ZeroId{field: Field}

# Why creating a context from supplied IDs was refused: a child reused its
# parent's span ID, or a restart reused the received trace ID.
type ContextError is Data:
  ReusedSpanId{}
  ReusedTraceId{}

# A sequence of n digits read from the front of a text, with the text that
# remains after it. The length n is part of the type, so a reader of 32 digits
# can only produce 32.
type Parsed<-n: Nat> is Data:
  Parsed{digits: Digits.Digits(n), rest: String}

# A strict traceparent v00 value (W3C 3.2.2): a trace ID of 32 digits and a
# parent ID of 16 digits, each with a proof that it is not all zero, and a flag
# byte of two digits. Length and alphabet are structural: a value with a wrong
# length or a non-hexadecimal digit cannot be built. All eight flag bits are
# kept, including the reserved ones, so the codec is exact.
type TraceParentV00 is Data:
  TraceParentV00{
    trace_id: Digits.NonZero<32n>,
    parent_id: Digits.NonZero<16n>,
    flags: Digits.Digits(2n)
  }

# A validated trace ID: 32 lowercase hexadecimal digits, not all zero (W3C
# 3.2.2.3). `random` records whether the random-trace-id flag (W3C 3.2.2.5.2)
# may be emitted for it. A parsed ID makes no such assertion: only its origin
# can justify one. Generation sets it, and a caller who knows the ID is random
# sets it with TraceId.assert_random.
type TraceId is Data:
  TraceId{value: Digits.NonZero<32n>, random: Bool}

# A validated span ID: 16 lowercase hexadecimal digits, not all zero, the
# identifier of one operation. It is sent as the parent ID of traceparent (W3C
# 3.2.2.4).
type SpanId is Data:
  SpanId{value: Digits.NonZero<16n>}

# How a child operation obtains its sampled indication (W3C 3.2.2.5.1):
# InheritSampled{} keeps the parent's and SetSampled{sampled} sets it. The
# indication communicates a decision; it does not record anything.
type Sampling is Data:
  InheritSampled{}
  SetSampled{sampled: Bool}

# A context received from another participant. It identifies the sender's
# operation and keeps only the known flags: sampled and random-trace-id. It is
# built from a received value (RemoteContext.from_traceparent) and has its own
# type, so it cannot be sent as if it were this participant's operation.
type RemoteContext is Data:
  RemoteContext{trace_id: TraceId, span_id: SpanId, sampled: Bool}

# A context that identifies an operation of this participant: the one it sends
# in its own headers. The Context.* operations build it.
type LocalContext is Data:
  LocalContext{trace_id: TraceId, span_id: SpanId, sampled: Bool}

# The context whose trace a child operation continues: a received context or
# one of this participant's own operations.
type Parent is Data:
  RemoteParent{context: RemoteContext}
  LocalParent{context: LocalContext}

# Why generating identifiers failed. A source failure carries the source's own
# code and message; exhaustion names the identifier whose eight candidates were
# all rejected.
type GenerationError is Data:
  SourceFailure{code: U32, message: String}
  ExhaustedTraceId{}
  ExhaustedSpanId{}

# The words read so far for the current trace ID candidate, in arrival order.
# Four words complete a candidate.
type TraceWords is Data:
  NoTraceWord{}
  OneTraceWord{first: U32}
  TwoTraceWords{first: U32, second: U32}
  ThreeTraceWords{first: U32, second: U32, third: U32}

# The words read so far for the current span ID candidate. Two words complete
# a candidate.
type SpanWords is Data:
  NoSpanWord{}
  OneSpanWord{first: U32}

# The generation machine below is shared by the IO operations and stated in
# the laws. Its types and `Draw` functions are internal: callers use the
# `Context.*_with` operations or generation.bend.
#
# What a new local context needs besides its span ID: the trace ID it belongs
# to, its sampled indication, and for a child the parent's span ID, which the
# new span ID must not repeat.
type SpanPlan is Data:
  SpanPlan{trace_id: TraceId, sampled: Bool, parent: Maybe<&2, SpanId>}

# A generation in progress: drawing the trace ID or the span ID. `remaining`
# counts the further candidates allowed after the current one, so each
# identifier gets eight candidates in all. `previous` is the received trace ID
# that a restart must not reuse.
type Draw is Data:
  DrawTrace{remaining: Nat, words: TraceWords, previous: Maybe<&2, TraceId>}
  DrawSpan{remaining: Nat, words: SpanWords, plan: SpanPlan}

# The state of a generation after each source word: it needs another word, it
# created a context, or it failed.
type Step is Data:
  NeedWord{draw: Draw}
  Created{context: LocalContext}
  Failed{error: GenerationError}

# Strict v00 codec
# ================
#
# TraceParentV00.parse reads exactly "00-", 32 lowercase hexadecimal digits,
# "-", 16 digits, "-" and two digits (W3C 3.2.2). The helpers below read one
# field at a time and report the first problem with the offset of the
# offending character.

# Put one more digit in front of a parsed sequence: n digits become 1 + n.
def Parsed.prepend(-n: Nat, digit: Hex.Digit, parsed: Parsed<n>) -> Parsed<1n+n>:
  match parsed:
    case Parsed{digits, rest}:
      Parsed{Digits.DCon{digit, digits}, rest}

# A decoded character, or InvalidHex at its offset when it is not a lowercase
# hexadecimal digit.
def Parse.digit_result(value: Maybe<&2, Hex.Digit>, offset: Nat) ->
  Result<&2, &2, Error, Hex.Digit>:
  match value:
    case None{}:
      Fail{InvalidHex{offset}}
    case Some{digit}:
      Done{digit}

# Decode one character as a lowercase hexadecimal digit.
def Parse.digit(char: Char, offset: Nat) -> Result<&2, &2, Error, Hex.Digit>:
  Parse.digit_result(Hex.Digit.from_char(char), offset)

# Consume exactly n characters as digits, keeping the unconsumed rest of the
# text. The recursion decreases n, so no length check or unchecked conversion
# is needed: the result's type already has length n.
def Parse.digits(n: Nat, text: String, offset: Nat) ->
  Result<&2, &2, Error, Parsed<n>>:
  match n:
    case 0n:
      Done{Parsed{Digits.DNil{}, text}}
    case 1n+p:
      match text:
        case SNil{}:
          Fail{UnexpectedEnd{offset}}
        case SCon{char, tail}:
          +at = offset
          do Result<&2, &2, Error, Parsed<1n+p>>:
            digit : Hex.Digit <- Parse.digit(char, at)
            parsed : Parsed<p> <- Parse.digits(p, tail, 1n+at)
            return Parsed.prepend(p, digit, parsed)

# The rest of the text after a "-", or ExpectedSeparator at its offset.
def Parse.separator_result(tail: String, ok: Bool, offset: Nat) ->
  Result<&2, &2, Error, String>:
  match ok:
    case False{}:
      Fail{ExpectedSeparator{offset}}
    case True{}:
      Done{tail}

# Read the "-" expected at `offset`.
def Parse.separator(text: String, offset: Nat) -> Result<&2, &2, Error, String>:
  match text:
    case SNil{}:
      Fail{UnexpectedEnd{offset}}
    case SCon{char, tail}:
      Parse.separator_result(tail, Char.is_eq(char, '-'), offset)

# The value must end here. Only the first character after it is inspected, so
# an arbitrarily long suffix is refused without being read.
def Parse.end(text: String) -> Result<&2, &2, Error, Unit>:
  match text:
    case SNil{}:
      Done{Unit{}}
    case SCon{char, tail}:
      Fail{TrailingInput{}}

# The version digits: 00 is the only version the strict codec reads, ff is
# forbidden (W3C 3.2.2.1), and any other version is reported with its text.
def Parse.version(digits: Digits.Digits(2n)) -> Result<&2, &2, Error, Unit>:
  match digits:
    case Digits.DCon{Hex.H0{}, Digits.DCon{Hex.H0{}, Digits.DNil{}}}:
      Done{Unit{}}
    case Digits.DCon{Hex.Hf{}, Digits.DCon{Hex.Hf{}, Digits.DNil{}}}:
      Fail{ForbiddenVersion{}}
    case other:
      Fail{UnsupportedVersion{Digits.Digits.to_string(2n, other)}}

# Attach the proof that digits are not all zero, or fail with ZeroId naming
# the field.
def Parse.nonzero_result(-n: Nat, result: Maybe<&2, Digits.NonZero<n>>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  match result:
    case None{}:
      Fail{ZeroId{field}}
    case Some{id}:
      Done{id}

# Check that digits are not all zero (W3C 3.2.2.3, 3.2.2.4).
def Parse.nonzero(n: Nat, digits: Digits.Digits(n), field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  Parse.nonzero_result(n, Digits.NonZero.new(n, digits), field)

# The last field: the two flag digits, then the end of the text.
def Parse.flags(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  parsed: Parsed<2n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{flags, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        end : Unit <- Parse.end(rest)
        return TraceParentV00{trace_id, parent_id, flags}

# After the trace ID: the parent ID, which must not be all zero, its "-" at
# offset 52 and the flag digits at offset 53.
def Parse.parent(trace_id: Digits.NonZero<32n>, parsed: Parsed<16n>) ->
  Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{parent_digits, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        parent_id : Digits.NonZero<16n> <- Parse.nonzero(16n, parent_digits, ParentIdField{})
        after : String <- Parse.separator(rest, 52n)
        flags : Parsed<2n> <- Parse.digits(2n, after, 53n)
        Parse.flags(trace_id, parent_id, flags)

# After the version: the trace ID, which must not be all zero, its "-" at
# offset 35 and the parent ID from offset 36.
def Parse.trace(parsed: Parsed<32n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{trace_digits, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        trace_id : Digits.NonZero<32n> <- Parse.nonzero(32n, trace_digits, TraceIdField{})
        after : String <- Parse.separator(rest, 35n)
        parent : Parsed<16n> <- Parse.digits(16n, after, 36n)
        Parse.parent(trace_id, parent)

# After the two version digits: the version check, the "-" at offset 2 and the
# trace ID from offset 3.
def Parse.start(parsed: Parsed<2n>) -> Result<&2, &2, Error, TraceParentV00>:
  match parsed:
    case Parsed{version, rest}:
      do Result<&2, &2, Error, TraceParentV00>:
        version_ok : Unit <- Parse.version(version)
        after : String <- Parse.separator(rest, 2n)
        trace : Parsed<32n> <- Parse.digits(32n, after, 3n)
        Parse.trace(trace)

# Parse a strict traceparent v00 value: exactly "00-", 32 lowercase
# hexadecimal digits, "-", 16 digits, "-" and two digits; the IDs must not be
# all zero. No whitespace, case folding or suffix is accepted, and every flag
# byte is kept as received.
# This is the strict wire codec, not a complete W3C propagator: extracting a
# context from headers (#9) will apply the processing rules of W3C 4.1.2, such
# as reading later versions by their known prefix.
# Laws: roundtrip, inverse and formatted_length.
def TraceParentV00.parse(text: String) -> Result<&2, &2, Error, TraceParentV00>:
  do Result<&2, &2, Error, TraceParentV00>:
    version : Parsed<2n> <- Parse.digits(2n, text, 0n)
    Parse.start(version)

# The text of a strict v00 value: always 55 characters. It is total, because
# validity is carried by the argument's type, and it preserves every flag bit:
# it is the exact inverse of parse, not an outgoing-header policy (see
# LocalContext.to_traceparent for what a participant emits).
def TraceParentV00.format(context: TraceParentV00) -> String:
  match context:
    case TraceParentV00{trace_id, parent_id, flags}:
      "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++
        Digits.NonZero.to_string(16n, parent_id) ++ "-" ++
        Digits.Digits.to_string(2n, flags)

# Whether the sampled flag, bit 0 of the flag byte, is set (W3C 3.2.2.5.1).
def TraceParentV00.is_sampled(context: TraceParentV00) -> Bool:
  match context:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      Hex.Digit.is_odd(low)

# Whether the random-trace-id flag, bit 1, is set (W3C 3.2.2.5.2). It records
# the sender's assertion; it does not prove how the trace ID was generated.
def TraceParentV00.is_random(context: TraceParentV00) -> Bool:
  match context:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}:
      Hex.Digit.has_bit1(low)

# Identifiers and contexts
# ========================
#
# Supplied IDs are parsed with the same digit reader as the codec. Contexts are
# created from validated IDs: a root, a child continuing a parent, a restart
# replacing a received trace, or the explicit construction of an operation the
# caller owns.

# The digits of a supplied ID must be the whole text, and not all zero.
def Parse.id.finish(n: Nat, parsed: Parsed<n>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  match parsed:
    case Parsed{digits, rest}:
      do Result<&2, &2, Error, Digits.NonZero<n>>:
        end : Unit <- Parse.end(rest)
        Parse.nonzero(n, digits, field)

# A supplied ID is exactly n lowercase hexadecimal digits, not all zero.
def Parse.id(+n: Nat, text: String, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<n>>:
  do Result<&2, &2, Error, Digits.NonZero<n>>:
    parsed : Parsed<n> <- Parse.digits(n, text, 0n)
    Parse.id.finish(n, parsed, field)

# Parse a supplied trace ID: exactly 32 lowercase hexadecimal digits, not all
# zero. Error offsets count from the start of the ID. The result makes no
# randomness assertion (laws trace_id_parse and trace_id_accepts).
def TraceId.parse(text: String) -> Result<&2, &2, Error, TraceId>:
  do Result<&2, &2, Error, TraceId>:
    value : Digits.NonZero<32n> <- Parse.id(32n, text, TraceIdField{})
    return TraceId{value, False{}}

# Record the caller's assertion that these digits were generated randomly, so
# that the random-trace-id flag is emitted with them. The caller is responsible
# for the assertion; validation cannot establish it (law assert_random).
def TraceId.assert_random(id: TraceId) -> TraceId:
  match id:
    case TraceId{value, random}:
      TraceId{value, True{}}

# Whether the trace ID asserts that it was generated randomly.
def TraceId.is_random(id: TraceId) -> Bool:
  match id:
    case TraceId{value, random}:
      random

# The 32 lowercase hexadecimal digits of the trace ID.
def TraceId.to_string(id: TraceId) -> String:
  match id:
    case TraceId{value, random}:
      Digits.NonZero.to_string(32n, value)

# Whether two trace IDs name the same trace. The randomness assertion is not
# part of the identifier, so it is ignored.
def TraceId.is_eq(a: TraceId, b: TraceId) -> Bool:
  String.eq(TraceId.to_string(a), TraceId.to_string(b))

# Parse a supplied span ID: exactly 16 lowercase hexadecimal digits, not all
# zero (laws span_id_parse and span_id_roundtrip).
def SpanId.parse(text: String) -> Result<&2, &2, Error, SpanId>:
  do Result<&2, &2, Error, SpanId>:
    value : Digits.NonZero<16n> <- Parse.id(16n, text, SpanIdField{})
    return SpanId{value}

# The 16 lowercase hexadecimal digits of the span ID.
def SpanId.to_string(id: SpanId) -> String:
  match id:
    case SpanId{value}:
      Digits.NonZero.to_string(16n, value)

# Whether two span IDs name the same operation.
def SpanId.is_eq(a: SpanId, b: SpanId) -> Bool:
  String.eq(SpanId.to_string(a), SpanId.to_string(b))

# The sampled indication a child receives: the inherited one, unless the
# caller set another (law sampling).
def Sampling.resolve(sampling: Sampling, inherited: Bool) -> Bool:
  match sampling:
    case InheritSampled{}:
      inherited
    case SetSampled{sampled}:
      sampled

# Interpret a received strict-v00 value as the sender's context. Bit 0 is
# sampled and bit 1 is random-trace-id; the reserved bits are not interpreted
# and do not travel with the context (law received_flags).
def RemoteContext.from_traceparent(value: TraceParentV00) -> RemoteContext:
  match value:
    case TraceParentV00{trace_id, parent_id,
      Digits.DCon{high, Digits.DCon{+low, Digits.DNil{}}}}:
      RemoteContext{TraceId{trace_id, Hex.Digit.has_bit1(low)}, SpanId{parent_id},
        Hex.Digit.is_odd(low)}

# The trace the received context belongs to.
def RemoteContext.trace_id(context: RemoteContext) -> TraceId:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      trace_id

# The sender's operation: the parent ID of the received value.
def RemoteContext.span_id(context: RemoteContext) -> SpanId:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      span_id

# The sender's sampled indication.
def RemoteContext.is_sampled(context: RemoteContext) -> Bool:
  match context:
    case RemoteContext{trace_id, span_id, sampled}:
      sampled

# The trace this participant's operation belongs to.
def LocalContext.trace_id(context: LocalContext) -> TraceId:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      trace_id

# This participant's operation.
def LocalContext.span_id(context: LocalContext) -> SpanId:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      span_id

# The sampled indication this participant sends.
def LocalContext.is_sampled(context: LocalContext) -> Bool:
  match context:
    case LocalContext{trace_id, span_id, sampled}:
      sampled

# The participating representation of a local context: version 00, and flags
# limited to sampled (bit 0) and random-trace-id (bit 1), with every reserved
# bit zero (W3C 3.2.2.5.3; laws emitted_traceparent and emitted_projection).
def LocalContext.to_traceparent(context: LocalContext) -> TraceParentV00:
  match context:
    case LocalContext{TraceId{trace_id, random}, SpanId{span_id}, sampled}:
      TraceParentV00{trace_id, span_id,
        Digits.DCon{Hex.H0{}, Digits.DCon{Hex.Digit.from_bits(sampled, random, False{}, False{}), Digits.DNil{}}}}

# The trace a child continues.
def Parent.trace_id(parent: Parent) -> TraceId:
  match parent:
    case RemoteParent{context}:
      RemoteContext.trace_id(context)
    case LocalParent{context}:
      LocalContext.trace_id(context)

# The parent's operation, which a child must not reuse.
def Parent.span_id(parent: Parent) -> SpanId:
  match parent:
    case RemoteParent{context}:
      RemoteContext.span_id(context)
    case LocalParent{context}:
      LocalContext.span_id(context)

# The sampled indication a child inherits by default.
def Parent.is_sampled(parent: Parent) -> Bool:
  match parent:
    case RemoteParent{context}:
      RemoteContext.is_sampled(context)
    case LocalParent{context}:
      LocalContext.is_sampled(context)

# Represent an operation the caller owns, with supplied IDs and an explicit
# sampled indication. The IDs must belong to that operation: validating their
# format cannot establish where they came from (law from_ids).
def Context.from_ids(trace_id: TraceId, span_id: SpanId, sampled: Bool) -> LocalContext:
  LocalContext{trace_id, span_id, sampled}

# Start a trace with supplied IDs. A new root is not sampled (spec #1: "New
# roots default to sampled `0`"; law root). generation.bend provides
# Context.root, Context.child and Context.restart for generated IDs.
def Context.root_from_ids(trace_id: TraceId, span_id: SpanId) -> LocalContext:
  Context.from_ids(trace_id, span_id, False{})

# The child, unless the span ID was found equal to the parent's.
def Context.child_from_id.checked(trace_id: TraceId, span_id: SpanId, sampled: Bool, reused: Bool) ->
  Result<&2, &2, ContextError, LocalContext>:
  match reused:
    case True{}:
      Fail{ReusedSpanId{}}
    case False{}:
      Done{Context.from_ids(trace_id, span_id, sampled)}

# Continue the parent's trace with a new operation identified by a supplied
# span ID. The child keeps the trace ID and its randomness assertion, and its
# span ID must differ from the parent's (ReusedSpanId otherwise). Sampling is
# inherited unless set. Laws: child, child_reuse and child_accepts.
def Context.child_from_id(+parent: Parent, +span_id: SpanId, sampling: Sampling) ->
  Result<&2, &2, ContextError, LocalContext>:
  Context.child_from_id.checked(Parent.trace_id(parent), span_id,
    Sampling.resolve(sampling, Parent.is_sampled(parent)),
    SpanId.is_eq(span_id, Parent.span_id(parent)))

# The restarted root, unless the trace ID was found equal to the received one.
def Context.restart_from_ids.checked(trace_id: TraceId, span_id: SpanId, reused: Bool) ->
  Result<&2, &2, ContextError, LocalContext>:
  match reused:
    case True{}:
      Fail{ReusedTraceId{}}
    case False{}:
      Done{Context.root_from_ids(trace_id, span_id)}

# Start a new trace with supplied IDs instead of continuing a received context.
# The new trace ID must differ from the received one (ReusedTraceId otherwise),
# and the root defaults apply, sampled 0 included. Laws: restart,
# restart_reuse and restart_accepts.
def Context.restart_from_ids(previous: RemoteContext, +trace_id: TraceId, span_id: SpanId) ->
  Result<&2, &2, ContextError, LocalContext>:
  Context.restart_from_ids.checked(trace_id, span_id,
    TraceId.is_eq(trace_id, RemoteContext.trace_id(previous)))

# Identifiers from source words
# =============================
#
# Generated IDs are built from 32-bit words: four words for a trace ID and two
# for a span ID, most significant first (spec #1). These conversions make no
# randomness assertion; generation adds it.

# The eight lowercase hexadecimal digits of a word, most significant first
# (laws hex_injective and word_hex).
def U32.to_hex(word: U32) -> String:
  Digits.Digits.to_string(8n, Digits.Digits.of_u32(word))

# A trace ID from nonzero digits, with no randomness assertion.
def TraceId.from_digits(value: Maybe<&2, Digits.NonZero<32n>>) -> Maybe<&2, TraceId>:
  match value:
    case None{}:
      None{}
    case Some{digits}:
      Some{TraceId{digits, False{}}}

# A trace ID from four words, read most significant first: the first word
# gives the first eight digits. Like a parsed ID it makes no randomness
# assertion; add one with TraceId.assert_random when the words are random. An
# all-zero candidate is None (laws trace_words and words_unasserted).
def TraceId.from_words(first: U32, second: U32, third: U32, fourth: U32) -> Maybe<&2, TraceId>:
  TraceId.from_digits(Digits.NonZero.new(32n,
    Digits.Digits.append(8n, 24n, Digits.Digits.of_u32(first),
      Digits.Digits.append(8n, 16n, Digits.Digits.of_u32(second),
        Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(third), Digits.Digits.of_u32(fourth))))))

# A span ID from nonzero digits.
def SpanId.from_digits(value: Maybe<&2, Digits.NonZero<16n>>) -> Maybe<&2, SpanId>:
  match value:
    case None{}:
      None{}
    case Some{digits}:
      Some{SpanId{digits}}

# A span ID from two words, most significant first. An all-zero candidate is
# None (law span_words).
def SpanId.from_words(first: U32, second: U32) -> Maybe<&2, SpanId>:
  SpanId.from_digits(Digits.NonZero.new(16n,
    Digits.Digits.append(8n, 8n, Digits.Digits.of_u32(first), Digits.Digits.of_u32(second))))

# Generation machine
# ==================
#
# A generation is a small state machine fed one source word at a time. It
# draws the trace ID first (for a root or a restart), then the span ID, gives
# each identifier eight candidates, rejects zero and reused IDs, and stops at
# the first source error. The same machine runs over a replayed tape in the
# laws and over the host's cryptographic source in generation.bend.

# A root draws its trace ID, then its span ID, and starts unsampled. Seven
# further candidates follow the first, eight in all.
def Draw.root() -> Step:
  NeedWord{DrawTrace{7n, NoTraceWord{}, None{}}}

# A restart draws like a root but must not reuse the received trace ID.
def Draw.restart(previous: RemoteContext) -> Step:
  NeedWord{DrawTrace{7n, NoTraceWord{}, Some{RemoteContext.trace_id(previous)}}}

# A child keeps the parent's trace ID and draws a span ID other than the
# parent's.
def Draw.child(+parent: Parent, sampling: Sampling) -> Step:
  NeedWord{DrawSpan{7n, NoSpanWord{},
    SpanPlan{Parent.trace_id(parent), Sampling.resolve(sampling, Parent.is_sampled(parent)),
      Some{Parent.span_id(parent)}}}}

# Try another trace ID candidate, or fail once the eight are used.
def Draw.retry_trace(remaining: Nat, previous: Maybe<&2, TraceId>) -> Step:
  match remaining:
    case 0n:
      Failed{ExhaustedTraceId{}}
    case 1n+p:
      NeedWord{DrawTrace{p, NoTraceWord{}, previous}}

# An accepted trace ID is followed by the span ID, with the root default
# sampled indication.
def Draw.accept_trace(trace_id: TraceId) -> Step:
  NeedWord{DrawSpan{7n, NoSpanWord{}, SpanPlan{trace_id, False{}, None{}}}}

# A trace ID candidate equal to the received one is retried.
def Draw.reuse_trace(reused: Bool, id: TraceId, previous: TraceId, remaining: Nat) -> Step:
  match reused:
    case True{}:
      Draw.retry_trace(remaining, Some{previous})
    case False{}:
      Draw.accept_trace(id)

# Check a complete trace ID candidate: zero and, for a restart, the received
# trace ID are retried; anything else is accepted.
def Draw.check_trace(candidate: Maybe<&2, TraceId>, previous: Maybe<&2, TraceId>, remaining: Nat) -> Step:
  match candidate:
    case None{}:
      Draw.retry_trace(remaining, previous)
    case Some{+id}:
      match previous:
        case None{}:
          Draw.accept_trace(id)
        case Some{+old}:
          Draw.reuse_trace(TraceId.is_eq(id, old), id, old, remaining)

# Try another span ID candidate, or fail once the eight are used.
def Draw.retry_span(remaining: Nat, plan: SpanPlan) -> Step:
  match remaining:
    case 0n:
      Failed{ExhaustedSpanId{}}
    case 1n+p:
      NeedWord{DrawSpan{p, NoSpanWord{}, plan}}

# An accepted span ID completes the new local context.
def Draw.accept_span(id: SpanId, plan: SpanPlan) -> Step:
  match plan:
    case SpanPlan{trace_id, sampled, parent}:
      Created{Context.from_ids(trace_id, id, sampled)}

# A span ID candidate equal to the parent's is retried.
def Draw.reuse_span(reused: Bool, id: SpanId, plan: SpanPlan, remaining: Nat) -> Step:
  match reused:
    case True{}:
      Draw.retry_span(remaining, plan)
    case False{}:
      Draw.accept_span(id, plan)

# Check a complete span ID candidate: zero and, for a child, the parent's span
# ID are retried; anything else is accepted.
def Draw.check_span(candidate: Maybe<&2, SpanId>, plan: SpanPlan, remaining: Nat) -> Step:
  match candidate:
    case None{}:
      Draw.retry_span(remaining, plan)
    case Some{+id}:
      match plan:
        case SpanPlan{+trace_id, +sampled, None{}}:
          Draw.accept_span(id, SpanPlan{trace_id, sampled, None{}})
        case SpanPlan{+trace_id, +sampled, Some{+old}}:
          Draw.reuse_span(SpanId.is_eq(id, old), id, SpanPlan{trace_id, sampled, Some{old}}, remaining)

# Generation reads its words from a source trusted to be random, so each
# trace ID candidate asserts random-trace-id.
def Draw.asserted(candidate: Maybe<&2, TraceId>) -> Maybe<&2, TraceId>:
  match candidate:
    case None{}:
      None{}
    case Some{id}:
      Some{TraceId.assert_random(id)}

# Feed the next source word to the machine. A source error ends the
# generation at once with SourceFailure (law feed_failure); a word completes
# or extends the current candidate.
def Draw.feed(word: Result<&1, &1, U32 & String, U32>, draw: Draw) -> Step:
  match word:
    case Fail{(code, message)}:
      Failed{SourceFailure{code, message}}
    case Done{next}:
      match draw:
        case DrawTrace{remaining, NoTraceWord{}, previous}:
          NeedWord{DrawTrace{remaining, OneTraceWord{next}, previous}}
        case DrawTrace{remaining, OneTraceWord{first}, previous}:
          NeedWord{DrawTrace{remaining, TwoTraceWords{first, next}, previous}}
        case DrawTrace{remaining, TwoTraceWords{first, second}, previous}:
          NeedWord{DrawTrace{remaining, ThreeTraceWords{first, second, next}, previous}}
        case DrawTrace{remaining, ThreeTraceWords{first, second, third}, previous}:
          Draw.check_trace(Draw.asserted(TraceId.from_words(first, second, third, next)), previous, remaining)
        case DrawSpan{remaining, NoSpanWord{}, plan}:
          NeedWord{DrawSpan{remaining, OneSpanWord{next}, plan}}
        case DrawSpan{remaining, OneSpanWord{first}, plan}:
          Draw.check_span(SpanId.from_words(first, next), plan, remaining)

# The result of a finished generation. A generation that has not finished
# would report the identifier it was drawing; the root_ends, child_ends and
# restart_ends laws show that the word budgets of the operations below make
# those cases unreachable.
def Step.result(step: Step) -> Result<&2, &2, GenerationError, LocalContext>:
  match step:
    case Created{context}:
      Done{context}
    case Failed{error}:
      Fail{error}
    case NeedWord{DrawTrace{remaining, words, previous}}:
      Fail{ExhaustedTraceId{}}
    case NeedWord{DrawSpan{remaining, words, plan}}:
      Fail{ExhaustedSpanId{}}

# Whether a generation has ended, with or without a context.
def Step.is_finished(step: Step) -> Bool:
  match step:
    case NeedWord{draw}:
      False{}
    case Created{context}:
      True{}
    case Failed{error}:
      True{}

# A deterministic word source for tests and replay: each read takes the next
# result, and an empty tape fails with code 1, tape-exhausted.
def Tape.next(tape: List<&1, Result<&1, &1, U32 & String, U32>>) ->
  List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>:
  match tape:
    case Nil{}:
      (Nil{}, Fail{(1, "tape-exhausted")})
    case Con{word, rest}:
      (rest, word)

# Feed a word that a source returned, keeping the source's next state.
def Draw.fed_by(-S: Type, got: S & Result<&1, &1, U32 & String, U32>, draw: Draw) -> S & Step:
  (state, word) = got
  (state, Draw.feed(word, draw))

# Whether the generation in a driver's result has ended.
def Draw.ended(result: List<&1, Result<&1, &1, U32 & String, U32>> & Step) -> Bool:
  (tape, step) = result
  Step.is_finished(step)

# Drive a generation from a tape, reading one word at a time and stopping as
# soon as it ends; unread words stay on the tape. `fuel` bounds the steps,
# which Bend requires for termination; the laws show the budgets suffice.
def Draw.run(fuel: Nat, current: List<&1, Result<&1, &1, U32 & String, U32>> & Step) ->
  List<&1, Result<&1, &1, U32 & String, U32>> & Step:
  match fuel current:
    case _ Tuple{tape, Created{context}}:
      (tape, Created{context})
    case _ Tuple{tape, Failed{error}}:
      (tape, Failed{error})
    case 0n Tuple{tape, NeedWord{draw}}:
      (tape, NeedWord{draw})
    case 1n+p Tuple{tape, NeedWord{draw}}:
      Draw.run(p, Draw.fed_by(List<&1, Result<&1, &1, U32 & String, U32>>, Tape.next(tape), draw))

# Drive a generation from any source. `read` returns the source's next state
# with each word, one word at a time, and the driver stops as soon as the
# generation ends; the final source state is handed back, so a caller can see
# what was read. `fuel` bounds the words read, as in Draw.run. Templates keep
# this driver free of any host effect: the effect, if any, lives in the
# source.
def Draw.read(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), fuel: Nat,
  current: S & Step) -> IO(S & Step):
  match fuel current:
    case _ Tuple{state, Created{context}}:
      IO.pure(S & Step, (state, Created{context}))
    case _ Tuple{state, Failed{error}}:
      IO.pure(S & Step, (state, Failed{error}))
    case 0n Tuple{state, NeedWord{draw}}:
      IO.pure(S & Step, (state, NeedWord{draw}))
    case 1n+p Tuple{state, NeedWord{draw}}:
      IO.bind(S & Result<&1, &1, U32 & String, U32>, S & Step, read(state),
        got => Draw.read(~S, ~read, p, Draw.fed_by(S, got, draw)))

# The source's final state with the generation's result.
def Draw.outcome(-S: Type, done: S & Step) -> S & Result<&2, &2, GenerationError, LocalContext>:
  (state, step) = done
  (state, Step.result(step))

# Turn the driver's final step into the generation's result.
def Draw.finished(~S: Type, action: IO(S & Step)) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  IO.bind(S & Step, S & Result<&2, &2, GenerationError, LocalContext>, action,
    done => IO.pure(S & Result<&2, &2, GenerationError, LocalContext>, Draw.outcome(S, done)))

# Generated contexts from a caller's source. `read` returns the source's next
# state with each word result. The source is trusted to be random: a generated
# trace ID asserts random-trace-id. A root or restart reads at most 48 words:
# eight trace ID candidates of four words and eight span ID candidates of two.
# A child reads at most 16.
# Laws: root_tape, root_ends, root_exhaustion and generated_root.
def Context.root_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S) ->
  IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 48n, (source, Draw.root())))

# A generated child of `parent` from a caller's source: at most 16 words.
# Laws: child_tape, child_ends, child_exhaustion and generated_child.
def Context.child_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  parent: Parent, sampling: Sampling) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 16n, (source, Draw.child(parent, sampling))))

# A generated restart replacing `previous` from a caller's source: at most 48
# words. Laws: restart_tape, restart_ends and generated_restart.
def Context.restart_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  previous: RemoteContext) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Draw.finished(~S, Draw.read(~S, ~read, 48n, (source, Draw.restart(previous))))

# A deterministic source that replays a tape of word results.
def Source.tape(tape: List<&1, Result<&1, &1, U32 & String, U32>>) ->
  IO(List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>):
  IO.pure(List<&1, Result<&1, &1, U32 & String, U32>> & Result<&1, &1, U32 & String, U32>, Tape.next(tape))

# Error messages
# ==============
#
# Readable names for the error constructors, for logs and test output. They
# include no text received from another participant, except the two
# hexadecimal digits of an unsupported version.

# The name of a codec or ID error, with its offset or, for an unsupported
# version, its two digits. ZeroId names the field: ZeroTraceId, ZeroParentId or
# ZeroSpanId.
def Error.show(error: Error) -> String:
  match error:
    case UnexpectedEnd{offset}:
      "UnexpectedEnd at " ++ Nat.show(offset)
    case InvalidHex{offset}:
      "InvalidHex at " ++ Nat.show(offset)
    case ExpectedSeparator{offset}:
      "ExpectedSeparator at " ++ Nat.show(offset)
    case TrailingInput{}:
      "TrailingInput"
    case ForbiddenVersion{}:
      "ForbiddenVersion"
    case UnsupportedVersion{version}:
      "UnsupportedVersion " ++ version
    case ZeroId{TraceIdField{}}:
      "ZeroTraceId"
    case ZeroId{ParentIdField{}}:
      "ZeroParentId"
    case ZeroId{SpanIdField{}}:
      "ZeroSpanId"

# The name of a context creation error.
def ContextError.show(error: ContextError) -> String:
  match error:
    case ReusedSpanId{}:
      "ReusedSpanId"
    case ReusedTraceId{}:
      "ReusedTraceId"

# The name of a generation error; a source failure adds the source's code and
# message.
def GenerationError.show(error: GenerationError) -> String:
  match error:
    case SourceFailure{code, message}:
      "SourceFailure " ++ U32.show(code) ++ " " ++ message
    case ExhaustedTraceId{}:
      "ExhaustedTraceId"
    case ExhaustedSpanId{}:
      "ExhaustedSpanId"

# Limits
# ======
#
# Budgets, in UTF-8 octets, for the traceparent and tracestate values the
# package reads and the tracestate it emits (spec #1, "Tracestate policy and
# resource bounds").

# Why a limit configuration was refused. The first failing rule is reported:
#   TraceParentInputTooSmall{}   the traceparent input budget is below 55
#   TraceStateOutputTooSmall{}   the tracestate output budget is below 512
#   TraceStateInputTooSmall{}    the tracestate input budget is below the output
#                                budget
type LimitsError is Data:
  TraceParentInputTooSmall{}
  TraceStateOutputTooSmall{}
  TraceStateInputTooSmall{}

# The rules of a configuration, which must accept its own emitted
# representation: a traceparent input budget of at least 55 octets, the length
# of a v00 value, and a tracestate input budget no smaller than an output
# budget of at least 512 octets (spec #1, "Tracestate policy and resource
# bounds"; the 512-octet minimum comes from #8; law limits_bounds).
def Limits.is_valid(traceparent_input: Nat, tracestate_input: Nat, +tracestate_output: Nat) -> Bool:
  Bool.and(Nat.is_ge(traceparent_input, 55n),
    Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output)))

# Budgets in UTF-8 octets. The input budgets bound a received traceparent value
# and a combined tracestate value; the output budget is the most an emitted
# tracestate may take. `evidence` is the proof of Limits.is_valid, so every
# Limits value follows the rules.
type Limits is Data:
  Limits{
    traceparent_input: Nat,
    tracestate_input: Nat,
    tracestate_output: Nat,
    evidence: {Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == True{} : Bool}
  }

# The first rule a refused configuration breaks.
def Limits.error(traceparent_input: Nat, tracestate_output: Nat) -> LimitsError:
  Bool.pick(LimitsError, Nat.is_lt(traceparent_input, 55n), TraceParentInputTooSmall{},
    Bool.pick(LimitsError, Nat.is_lt(tracestate_output, 512n), TraceStateOutputTooSmall{},
      TraceStateInputTooSmall{}))

# The configuration, when the check found it valid.
def Limits.new.checked(traceparent_input: Nat, tracestate_input: Nat, tracestate_output: Nat, valid: Bool,
  evidence: {Limits.is_valid(traceparent_input, tracestate_input, tracestate_output) == valid : Bool}) ->
  Result<&2, &2, LimitsError, Limits>:
  match valid:
    case True{}:
      Done{Limits{traceparent_input, tracestate_input, tracestate_output, evidence}}
    case False{}:
      Fail{Limits.error(traceparent_input, tracestate_output)}

# Validate a configuration; budgets count UTF-8 octets (laws limits_new and
# limits_fields).
def Limits.new(+traceparent_input: Nat, +tracestate_input: Nat, +tracestate_output: Nat) ->
  Result<&2, &2, LimitsError, Limits>:
  Limits.new.checked(traceparent_input, tracestate_input, tracestate_output,
    Limits.is_valid(traceparent_input, tracestate_input, tracestate_output), {==})

# 32 KiB for each received value and 512 octets for an emitted tracestate
# (law default_limits). The 512-octet output budget is this package's capacity
# policy, not a W3C maximum.
def Limits.default() -> Limits:
  Limits{32768n, 32768n, 512n, {==}}

# The most octets a received traceparent value may take.
def Limits.traceparent_input(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      traceparent_input

# The most octets a combined tracestate value may take, including the commas
# that join repeated fields.
def Limits.tracestate_input(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      tracestate_input

# The most octets an emitted tracestate may take.
def Limits.tracestate_output(limits: Limits) -> Nat:
  match limits:
    case Limits{traceparent_input, tracestate_input, tracestate_output, evidence}:
      tracestate_output

# The name of a limits error.
def LimitsError.show(error: LimitsError) -> String:
  match error:
    case TraceParentInputTooSmall{}:
      "TraceParentInputTooSmall"
    case TraceStateOutputTooSmall{}:
      "TraceStateOutputTooSmall"
    case TraceStateInputTooSmall{}:
      "TraceStateInputTooSmall"

# Tracestate: characters, keys and values
# =======================================
#
# The Level 2 grammar of W3C 3.3.2.2. The character classes are written with
# the code point ranges of the standard's ABNF.

# Why a tracestate key, value or received member was refused:
#   MissingEquals{}   a nonempty member has no "="
#   InvalidKey{}      the text before the first "=" is not a key
#   InvalidValue{}    the text after it, without trailing optional whitespace,
#                     is not a value
type EntryError is Data:
  MissingEquals{}
  InvalidKey{}
  InvalidValue{}

# Whether a code point lies between two others, both included.
def StateChar.in_range(+code: U32, low: U32, high: U32) -> Bool:
  Bool.and(U32.is_ge(code, low), U32.is_le(code, high))

# lcalpha / DIGIT: a lowercase ASCII letter (%x61-7A) or a digit (%x30-39),
# the first character of a key.
def StateChar.is_key_start(char: Char) -> Bool:
  match char:
    case Chr{+code}:
      Bool.or(StateChar.in_range(code, 97, 122), StateChar.in_range(code, 48, 57))

# keychar: lcalpha / DIGIT / "_" / "-" / "*" / "/" / "@".
def StateChar.is_key(+char: Char) -> Bool:
  Bool.or(StateChar.is_key_start(char), Bool.or(Char.is_eq(char, '_'), Bool.or(Char.is_eq(char, '-'),
    Bool.or(Char.is_eq(char, '*'), Bool.or(Char.is_eq(char, '/'), Char.is_eq(char, '@'))))))

# nblk-chr: %x21-2B / %x2D-3C / %x3E-7E, printable ASCII other than space,
# "," and "=". A value ends with one of these.
def StateChar.is_value_end(char: Char) -> Bool:
  match char:
    case Chr{+code}:
      Bool.or(StateChar.in_range(code, 33, 43), Bool.or(StateChar.in_range(code, 45, 60),
        StateChar.in_range(code, 62, 126)))

# chr: %x20 / nblk-chr, a character of a value: nblk-chr or a space.
def StateChar.is_value(+char: Char) -> Bool:
  Bool.or(Char.is_eq(char, ' '), StateChar.is_value_end(char))

# OWS: a space or a horizontal tab (RFC 9110, section 5.6.3).
def StateChar.is_ows(+char: Char) -> Bool:
  Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t'))

# Every remaining character is a key character, and at most `room` remain.
# The recursion stops once the room is used up, so a huge invalid key is not
# read to its end.
def StateKey.valid.rest(text: String, room: Nat) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{char, tail}:
      match room:
        case 0n:
          False{}
        case 1n+left:
          Bool.and(StateChar.is_key(char), StateKey.valid.rest(tail, left))

# key = ( lcalpha / DIGIT ) 0*255( keychar ): 1 to 256 characters (W3C
# 3.3.2.2.1). Level 1's tenant@system restriction does not apply.
def StateKey.is_valid(text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{char, tail}:
      Bool.and(StateChar.is_key_start(char), StateKey.valid.rest(tail, 255n))

# `char` is a value character followed by `tail`, of which at most `room`
# characters are allowed; the last character is not a space.
def StateValue.valid.go(tail: String, char: Char, room: Nat) -> Bool:
  match tail:
    case SNil{}:
      StateChar.is_value_end(char)
    case SCon{next, rest}:
      match room:
        case 0n:
          False{}
        case 1n+left:
          Bool.and(StateChar.is_value(char), StateValue.valid.go(rest, next, left))

# value = 0*255( chr ) nblk-chr: 1 to 256 printable ASCII characters other
# than "," and "=", the last of which is not a space (W3C 3.3.2.2.2).
def StateValue.is_valid(text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{char, tail}:
      StateValue.valid.go(tail, char, 255n)

# A tracestate key, naming the vendor that owns an entry. `evidence` proves the
# Level 2 key grammar for `text`, so a StateKey is always valid: build one with
# StateKey.parse (the negative fixture tests/reject/invalid_state_key.bend
# shows that direct construction with a wrong text does not compile).
type StateKey is Data:
  StateKey{text: String, evidence: {StateKey.is_valid(text) == True{} : Bool}}

# A tracestate value, opaque to every other vendor. `evidence` proves the
# Level 2 value grammar for `text`. Leading spaces are part of the value.
type StateValue is Data:
  StateValue{text: String, evidence: {StateValue.is_valid(text) == True{} : Bool}}

# The key, when the check found the text valid.
def StateKey.parse.checked(text: String, valid: Bool, evidence: {StateKey.is_valid(text) == valid : Bool}) ->
  Result<&2, &2, EntryError, StateKey>:
  match valid:
    case True{}:
      Done{StateKey{text, evidence}}
    case False{}:
      Fail{InvalidKey{}}

# Accept exactly a Level 2 key, or fail with InvalidKey. Nothing is trimmed
# or folded (laws key_parse, key_roundtrip and key_separators).
def StateKey.parse(+text: String) -> Result<&2, &2, EntryError, StateKey>:
  StateKey.parse.checked(text, StateKey.is_valid(text), {==})

# The key's text.
def StateKey.to_string(key: StateKey) -> String:
  match key:
    case StateKey{text, evidence}:
      text

# The value, when the check found the text valid.
def StateValue.parse.checked(text: String, valid: Bool, evidence: {StateValue.is_valid(text) == valid : Bool}) ->
  Result<&2, &2, EntryError, StateValue>:
  match valid:
    case True{}:
      Done{StateValue{text, evidence}}
    case False{}:
      Fail{InvalidValue{}}

# Accept exactly a Level 2 value, leading spaces included, or fail with
# InvalidValue. No whitespace is trimmed here, so a trailing space is refused
# (laws value_parse, value_roundtrip and value_separators).
def StateValue.parse(+text: String) -> Result<&2, &2, EntryError, StateValue>:
  StateValue.parse.checked(text, StateValue.is_valid(text), {==})

# The value's text.
def StateValue.to_string(value: StateValue) -> String:
  match value:
    case StateValue{text, evidence}:
      text

# The name of an entry error.
def EntryError.show(error: EntryError) -> String:
  match error:
    case MissingEquals{}:
      "MissingEquals"
    case InvalidKey{}:
      "InvalidKey"
    case InvalidValue{}:
      "InvalidValue"

# Tracestate: entries, states and lookups
# =======================================
#
# A state is the ordered list of vendor entries of a tracestate, leftmost first
# (W3C 3.3.3), with distinct keys and at most 32 entries.

# Why a received tracestate value was discarded:
#   StateTooLarge{}               the combined value exceeds its input budget
#   TooManyMembers{}              a 33rd nonempty member was reached
#   InvalidEntry{member, error}   a member is invalid; `member` numbers the
#                                 comma-separated members of the combined value
#                                 from zero, empty members included
# Discarding the state never invalidates a valid traceparent (spec #1).
type StateError is Data:
  StateTooLarge{}
  TooManyMembers{}
  InvalidEntry{member: Nat, error: EntryError}

# One vendor's entry: a key and its value.
type StateEntry is Data:
  StateEntry{key: StateKey, value: StateValue}

# The entry's key.
def StateEntry.key(entry: StateEntry) -> StateKey:
  match entry:
    case StateEntry{key, value}:
      key

# The entry's value.
def StateEntry.value(entry: StateEntry) -> StateValue:
  match entry:
    case StateEntry{key, value}:
      value

# The text of the entry's key.
def StateEntry.key_text(entry: StateEntry) -> String:
  StateKey.to_string(StateEntry.key(entry))

# `key=value`, as the entry is sent.
def StateEntry.format(entry: StateEntry) -> String:
  match entry:
    case StateEntry{key, value}:
      StateKey.to_string(key) ++ "=" ++ StateValue.to_string(value)

# Whether one of the entries has this key.
def Entries.has_key(entries: List<&2, StateEntry>, +key: String) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(String.eq(StateEntry.key_text(entry), key), Entries.has_key(rest, key))

# No entry repeats the key of an entry before it; `seen` holds the entries
# already passed. This is the order in which the reading machine checks keys.
def Entries.unique(entries: List<&2, StateEntry>, +seen: List<&2, StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{+entry, rest}:
      Bool.and(Bool.not(Entries.has_key(seen, StateEntry.key_text(entry))),
        Entries.unique(rest, List.append(&2, StateEntry, seen, Con{entry, Nil{}})))

# Distinct keys and at most 32 entries (W3C 3.3.2 and 3.3.3).
def TraceState.is_valid(+entries: List<&2, StateEntry>) -> Bool:
  Bool.and(Entries.unique(entries, Nil{}), Nat.is_le(List.length(&2, StateEntry, entries), 32n))

# Ordered vendor state: at most 32 entries with distinct keys, leftmost first.
# `evidence` proves both properties, so every TraceState has them (law
# state_valid).
type TraceState is Data:
  TraceState{entries: List<&2, StateEntry>, evidence: {TraceState.is_valid(entries) == True{} : Bool}}

# The state with no entries. It formats as "".
def TraceState.empty() -> TraceState:
  TraceState{Nil{}, {==}}

# The entries in order, leftmost first.
def TraceState.entries(state: TraceState) -> List<&2, StateEntry>:
  match state:
    case TraceState{entries, evidence}:
      entries

# Whether the state has no entries.
def TraceState.is_empty(state: TraceState) -> Bool:
  List.is_empty(&2, StateEntry, TraceState.entries(state))

# The value of `entry` when its key matched, or the result for the rest.
def Entries.get.put(entry: StateEntry, rest: Maybe<&2, StateValue>, hit: Bool) -> Maybe<&2, StateValue>:
  match hit:
    case True{}:
      Some{StateEntry.value(entry)}
    case False{}:
      rest

# The value of the first entry with this key.
def Entries.get(entries: List<&2, StateEntry>, +key: String) -> Maybe<&2, StateValue>:
  match entries:
    case Nil{}:
      None{}
    case Con{+entry, rest}:
      Entries.get.put(entry, Entries.get(rest, key), String.eq(StateEntry.key_text(entry), key))

# The value of the entry with this key, if there is one (laws get_entry and
# get_absent). The key is validated, so a lookup never needs to check it.
def TraceState.get(state: TraceState, key: StateKey) -> Maybe<&2, StateValue>:
  Entries.get(TraceState.entries(state), StateKey.to_string(key))

# Each entry after the first, preceded by its comma.
def Entries.format.rest(entries: List<&2, StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      "," ++ StateEntry.format(entry) ++ Entries.format.rest(rest)

# The entries as `key=value`, joined by commas.
def Entries.format(entries: List<&2, StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      StateEntry.format(entry) ++ Entries.format.rest(rest)

# The normalized value: the entries in order, joined by commas, with no
# optional whitespace. The empty state formats as "" (laws state_roundtrip and
# first_wins).
def TraceState.format(state: TraceState) -> String:
  Entries.format(TraceState.entries(state))

# Tracestate: budgets
# ===================
#
# A received value is measured in UTF-8 octets before it is read. Measuring
# stops at the first character past the budget, so an oversized value is never
# read to its end.

# The UTF-8 octets of a character. Bend characters are Unicode code points, so
# this is the size of the character's UTF-8 encoding: 1 to 4.
def Utf8.width(char: Char) -> Nat:
  match char:
    case Chr{+code}:
      Bool.pick(Nat, U32.is_lt(code, 128), 1n,
        Bool.pick(Nat, U32.is_lt(code, 2048), 2n,
          Bool.pick(Nat, U32.is_lt(code, 65536), 3n, 4n)))

# The UTF-8 octets of a text, in which the laws state every budget. Emission
# measures keys and values with it, at most 256 characters each; parsing
# measures received text with Utf8.left instead, which stops counting past
# the budget.
def Utf8.length(text: String) -> Nat:
  match text:
    case SNil{}:
      0n
    case SCon{char, tail}:
      Nat.add(Utf8.width(char), Utf8.length(tail))

# What is left of a budget after taking `need` octets, or None when less
# remains.
def Budget.take(need: Nat, budget: Nat) -> Maybe<&2, Nat>:
  match need budget:
    case 0n _:
      Some{budget}
    case 1n+more 0n:
      None{}
    case 1n+more 1n+left:
      Budget.take(more, left)

# What is left of a budget after a text, or None once the text exceeds it.
# Measuring stops at the first character beyond the budget, and a None budget
# stays None.
def Utf8.left(text: String, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text budget:
    case _ None{}:
      None{}
    case SNil{} Some{left}:
      Some{left}
    case SCon{char, tail} Some{left}:
      Utf8.left(tail, Budget.take(Utf8.width(char), left))

# Fields after the first are measured with the comma that joins them. Once the
# budget is exceeded, no further field is visited.
def Utf8.left_more(fields: List<&2, String>, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match fields budget:
    case Nil{} _:
      budget
    case Con{field, rest} None{}:
      None{}
    case Con{field, rest} Some{left}:
      Utf8.left_more(rest, Utf8.left(field, Utf8.left(",", Some{left})))

# What is left of a budget after repeated fields and the commas that join
# them.
def Utf8.left_fields(fields: List<&2, String>, budget: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match fields:
    case Nil{}:
      budget
    case Con{field, rest}:
      Utf8.left_more(rest, Utf8.left(field, budget))

# Tracestate: the reading machine
# ===============================
#
# TraceState.parse measures the combined value against its budget, then reads
# it once from left to right, one character at a time. A comma ends the
# current member; the machine validates each nonempty member when it ends,
# counts it toward the 32 allowed, and keeps it only when its key is new.
# Reading stops at the first problem.

# Where reading the current member stands: before its key, with only optional
# whitespace so far; inside its key; or inside its value. Characters read are
# kept most recent first, so each one costs a single step.
type Member is Data:
  Blank{}
  InKey{text: String}
  InValue{key: String, text: String}

# A tracestate being read: the members ended so far, empty ones included; how
# many more nonempty members are allowed; the current member; and the first
# entry of each key, in reading order. Stopped holds the first problem found.
# The scan and its helpers are internal.
type Scan is Data:
  Scanning{member: Nat, room: Nat, current: Member, entries: List<&2, StateEntry>}
  Stopped{error: StateError}

# A value's characters arrive most recent first. Restoring them skips optional
# whitespace until the first other character, then keeps every character, so
# the value comes back in reading order without its trailing whitespace.
def Value.restore.step(kept: Bool, ows: Bool, char: Char, value: String) -> Bool & String:
  match kept:
    case True{}:
      (True{}, SCon{char, value})
    case False{}:
      match ows:
        case True{}:
          (False{}, value)
        case False{}:
          (True{}, SCon{char, value})

# The restoring loop: one character at a time, with the state (whether a
# character was kept yet, the value so far).
def Value.restore.go(text: String, state: Bool & String) -> String:
  match text:
    case SNil{}:
      (kept, value) = state
      value
    case SCon{+char, tail}:
      (kept, value) = state
      Value.restore.go(tail, Value.restore.step(kept, StateChar.is_ows(char), char, value))

# The value in reading order without its trailing optional whitespace.
def Value.restore(text: String) -> String:
  Value.restore.go(text, (False{}, ""))

# A character of a member that has no key yet: optional whitespace is
# skipped, an "=" gives the member an empty key, which validation refuses, and
# anything else starts the key.
def Member.start(ows: Bool, equals: Bool, char: Char) -> Member:
  match ows:
    case True{}:
      Blank{}
    case False{}:
      match equals:
        case True{}:
          InValue{"", ""}
        case False{}:
          InKey{SCon{char, SNil{}}}

# A character inside a key: the first "=" ends the key, anything else extends
# it. Key characters are validated when the member ends.
def Member.key(equals: Bool, char: Char, text: String) -> Member:
  match equals:
    case True{}:
      InValue{String.reverse(text), ""}
    case False{}:
      InKey{SCon{char, text}}

# A character other than a comma extends the current member. Inside a value
# every character is kept; validation refuses those the grammar excludes.
def Member.push(+char: Char, current: Member) -> Member:
  match current:
    case Blank{}:
      Member.start(StateChar.is_ows(char), Char.is_eq(char, '='), char)
    case InKey{text}:
      Member.key(Char.is_eq(char, '='), char, text)
    case InValue{key, text}:
      InValue{key, SCon{char, text}}

# Validate the key and value texts of a member that ended. An invalid key is
# reported before an invalid value.
def Scan.validate(key: String, value: String) -> Result<&2, &2, EntryError, StateEntry>:
  do Result<&2, &2, EntryError, StateEntry>:
    parsed_key : StateKey <- StateKey.parse(key)
    parsed_value : StateValue <- StateValue.parse(value)
    return StateEntry{parsed_key, parsed_value}

# Keep the entries unchanged when the key was present; otherwise add the
# entry at the end.
def Entries.add.if(entries: List<&2, StateEntry>, entry: StateEntry, present: Bool) -> List<&2, StateEntry>:
  match present:
    case True{}:
      entries
    case False{}:
      List.append(&2, StateEntry, entries, Con{entry, Nil{}})

# Keep only the first entry of each key (spec #1, "Preserve the first
# occurrence of a duplicate key").
def Entries.add(+entries: List<&2, StateEntry>, +entry: StateEntry) -> List<&2, StateEntry>:
  Entries.add.if(entries, entry, Entries.has_key(entries, StateEntry.key_text(entry)))

# A valid member counts toward the 32 allowed before duplicates are dropped
# (spec #1); with no room left, the state is discarded with TooManyMembers.
def Scan.keep(room: Nat, member: Nat, entry: StateEntry, entries: List<&2, StateEntry>) -> Scan:
  match room:
    case 0n:
      Stopped{TooManyMembers{}}
    case 1n+left:
      Scanning{1n+member, left, Blank{}, Entries.add(entries, entry)}

# A member that ended: an invalid one stops reading with its number and
# reason; a valid one is counted and kept.
def Scan.entry(parsed: Result<&2, &2, EntryError, StateEntry>, member: Nat, room: Nat,
  entries: List<&2, StateEntry>) -> Scan:
  match parsed:
    case Fail{error}:
      Stopped{InvalidEntry{member, error}}
    case Done{entry}:
      Scan.keep(room, member, entry, entries)

# The current member ends at a comma or with the value. An empty member, or
# one of optional whitespace only, is ignored but still numbered; a member
# without "=" is refused; otherwise its key and value are validated, trailing
# optional whitespace left out of the value.
def Scan.close(member: Nat, room: Nat, current: Member, entries: List<&2, StateEntry>) -> Scan:
  match current:
    case Blank{}:
      Scanning{1n+member, room, Blank{}, entries}
    case InKey{text}:
      Stopped{InvalidEntry{member, MissingEquals{}}}
    case InValue{key, text}:
      Scan.entry(Scan.validate(key, Value.restore(text)), member, room, entries)

# One character of a scan that is still reading: a comma ends the member, and
# anything else extends it.
def Scan.read(comma: Bool, char: Char, member: Nat, room: Nat, current: Member,
  entries: List<&2, StateEntry>) -> Scan:
  match comma:
    case True{}:
      Scan.close(member, room, current, entries)
    case False{}:
      Scanning{member, room, Member.push(char, current), entries}

# Read one character, unless the scan has stopped.
def Scan.char(+char: Char, scan: Scan) -> Scan:
  match scan:
    case Stopped{error}:
      Stopped{error}
    case Scanning{member, room, current, entries}:
      Scan.read(Char.is_eq(char, ','), char, member, room, current, entries)

# Read a text one character at a time, stopping at the first problem. This is
# a loop (a tail call), so its depth does not grow with the text.
def Scan.text(text: String, scan: Scan) -> Scan:
  match text scan:
    case _ Stopped{error}:
      Stopped{error}
    case SNil{} Scanning{member, room, current, entries}:
      Scanning{member, room, current, entries}
    case SCon{char, tail} Scanning{member, room, current, entries}:
      Scan.text(tail, Scan.char(char, Scanning{member, room, current, entries}))

# Fields after the first are read after the comma that joins them.
def Scan.more(fields: List<&2, String>, scan: Scan) -> Scan:
  match fields:
    case Nil{}:
      scan
    case Con{field, rest}:
      Scan.more(rest, Scan.text(field, Scan.char(',', scan)))

# Read repeated fields as their comma-joined combination.
def Scan.fields(fields: List<&2, String>, scan: Scan) -> Scan:
  match fields:
    case Nil{}:
      scan
    case Con{field, rest}:
      Scan.more(rest, Scan.text(field, scan))

# The scan of a new value: no member ended, 32 allowed, nothing kept.
def Scan.start() -> Scan:
  Scanning{0n, 32n, Blank{}, Nil{}}

# The scan keeps only the first entry of each key and stops at a 33rd member,
# so this check is not expected to fail: the laws prove it passes for
# normalized values, and the corpus exercises the rest. A failure would be
# reported as too many members.
def Scan.state(entries: List<&2, StateEntry>, valid: Bool,
  evidence: {TraceState.is_valid(entries) == valid : Bool}) -> Result<&2, &2, StateError, TraceState>:
  match valid:
    case True{}:
      Done{TraceState{entries, evidence}}
    case False{}:
      Fail{TooManyMembers{}}

# The state read, once the last member has ended. TraceState.is_valid is
# checked here to build the state's evidence.
def Scan.result(scan: Scan) -> Result<&2, &2, StateError, TraceState>:
  match scan:
    case Stopped{error}:
      Fail{error}
    case Scanning{member, room, current, +entries}:
      Scan.state(entries, TraceState.is_valid(entries), {==})

# The last member ends with the value.
def Scan.finish(scan: Scan) -> Result<&2, &2, StateError, TraceState>:
  match scan:
    case Stopped{error}:
      Fail{error}
    case Scanning{member, room, current, entries}:
      Scan.result(Scan.close(member, room, current, entries))

# Read the fields only when they fit the budget.
def Scan.within(fits: Maybe<&2, Nat>, fields: List<&2, String>) -> Result<&2, &2, StateError, TraceState>:
  match fits:
    case None{}:
      Fail{StateTooLarge{}}
    case Some{left}:
      Scan.finish(Scan.fields(fields, Scan.start()))

# Parse repeated tracestate field values, in arrival order, as their
# comma-joined combination (W3C 3.3.2). The combined value, joining commas
# included, must fit the tracestate input budget; a larger one is refused with
# StateTooLarge before any member is read, without measuring the rest. Then:
# empty members are ignored, and so is optional whitespace before a member and
# after its value; every nonempty member must be a valid entry (InvalidEntry)
# and counts toward the 32 allowed (TooManyMembers); the first entry of each
# key is kept. An error discards the whole state; a valid traceparent stays
# valid (spec #1). W3C 3.3: parse tracestate only for a message whose
# traceparent was parsed.
# Laws: fields_join, over_budget, within_budgets, first_wins and the others of
# section 10 of LAWS.bend.
def TraceState.parse_fields(limits: Limits, +fields: List<&2, String>) -> Result<&2, &2, StateError, TraceState>:
  Scan.within(Utf8.left_fields(fields, Some{Limits.tracestate_input(limits)}), fields)

# Parse one combined tracestate value; see TraceState.parse_fields.
def TraceState.parse(limits: Limits, text: String) -> Result<&2, &2, StateError, TraceState>:
  TraceState.parse_fields(limits, Con{text, Nil{}})

# The name of a tracestate error; InvalidEntry adds the member number and the
# reason.
def StateError.show(error: StateError) -> String:
  match error:
    case StateTooLarge{}:
      "StateTooLarge"
    case TooManyMembers{}:
      "TooManyMembers"
    case InvalidEntry{member, reason}:
      "InvalidEntry " ++ Nat.show(member) ++ " " ++ EntryError.show(reason)

# Tracestate: updates
# ===================
#
# W3C 3.5 lets a participant add, update and delete entries of the state it
# sends. A changed entry moves to the front and the other entries keep their
# order. Spec #1: updating a key of a full state evicts nothing, and adding a
# 33rd key removes the last entry.

# `item` followed by `rest`, unless `skip` is True: one step of a filter.
# Removing a key and listing the dropped keys both use it.
def Entries.unless(-A: Data, skip: Bool, item: A, rest: List<&2, A>) -> List<&2, A>:
  match skip:
    case True{}:
      rest
    case False{}:
      Con{item, rest}

# The entries without the one whose key is `key`, in order.
def Entries.without(entries: List<&2, StateEntry>, +key: String) -> List<&2, StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      Entries.unless(StateEntry, String.eq(StateEntry.key_text(entry), key), entry, Entries.without(rest, key))

# The state of these entries when the check finds them valid, `fallback`
# otherwise. Updates build their entries so that the check passes, which the
# laws prove; `fallback` keeps the function total without an unchecked
# conversion.
def TraceState.from_entries.checked(entries: List<&2, StateEntry>, fallback: TraceState, valid: Bool,
  evidence: {TraceState.is_valid(entries) == valid : Bool}) -> TraceState:
  match valid:
    case True{}:
      TraceState{entries, evidence}
    case False{}:
      fallback

# The state of `entries`, checked, or `fallback` if the check fails.
def TraceState.from_entries(+entries: List<&2, StateEntry>, fallback: TraceState) -> TraceState:
  TraceState.from_entries.checked(entries, fallback, TraceState.is_valid(entries), {==})

# Add or update the entry of `key` (W3C 3.5): it goes to the front with
# `value`, and the other entries follow in their order. At most 31 of them
# stay, so a new key in a full state removes the last entry, while updating a
# key that is present evicts nothing (laws set_entries, update_keeps_all,
# insert_entries and set_get).
def TraceState.set(+state: TraceState, +key: StateKey, value: StateValue) -> TraceState:
  TraceState.from_entries(Con{StateEntry{key, value},
    List.take(&2, StateEntry, Entries.without(TraceState.entries(state), StateKey.to_string(key)), 31n)}, state)

# Delete the entry of `key`, if there is one; the other entries keep their
# order (W3C 3.5; laws remove_entries and remove_get). W3C asks participants
# not to delete keys other vendors generated: that breaks correlation in
# their systems.
def TraceState.remove(+state: TraceState, key: StateKey) -> TraceState:
  TraceState.from_entries(Entries.without(TraceState.entries(state), StateKey.to_string(key)), state)

# Tracestate: emission
# ====================
#
# The emitted value is the normalized one of TraceState.format. Its size in
# UTF-8 octets counts each entry's key, equals sign and value and the commas
# between entries (spec #1). Keys and values are ASCII, so an octet is also a
# character, the unit of W3C 3.3.3.1.

# The octets of `key=value` (law entry_size).
def StateEntry.size(entry: StateEntry) -> Nat:
  match entry:
    case StateEntry{key, value}:
      Nat.add(Utf8.length(StateKey.to_string(key)), 1n+Utf8.length(StateValue.to_string(value)))

# The octets of each entry after the first, with its comma.
def Entries.size.rest(entries: List<&2, StateEntry>) -> Nat:
  match entries:
    case Nil{}:
      0n
    case Con{entry, rest}:
      1n+Nat.add(StateEntry.size(entry), Entries.size.rest(rest))

# The octets of the entries joined by commas, as Entries.format writes them.
def Entries.size(entries: List<&2, StateEntry>) -> Nat:
  match entries:
    case Nil{}:
      0n
    case Con{entry, rest}:
      Nat.add(StateEntry.size(entry), Entries.size.rest(rest))

# The octets of TraceState.format(state) (law state_size).
def TraceState.size(state: TraceState) -> Nat:
  Entries.size(TraceState.entries(state))

# What truncation to the output budget kept, and the keys of the entries it
# dropped, in their original order. Reporting the keys, not the values, tells
# which vendors lost their state without repeating opaque data.
type Truncation is Data:
  Truncation{kept: TraceState, dropped: List<&2, StateKey>}

# The state that fits the output budget.
def Truncation.kept(truncation: Truncation) -> TraceState:
  match truncation:
    case Truncation{kept, dropped}:
      kept

# The keys of the entries removed, in their original order; none when the
# state already fitted.
def Truncation.dropped(truncation: Truncation) -> List<&2, StateKey>:
  match truncation:
    case Truncation{kept, dropped}:
      dropped

# Whether the entry is larger than 128 octets. W3C 3.3.3.1 asks to remove
# such entries first.
def StateEntry.is_large(entry: StateEntry) -> Bool:
  Nat.is_gt(StateEntry.size(entry), 128n)

# Whether one of the entries is larger than 128 octets.
def Entries.has_large(entries: List<&2, StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(StateEntry.is_large(entry), Entries.has_large(rest))

# The entries without the rightmost one larger than 128 octets: an entry
# stays when a large entry follows it.
def Entries.drop_last_large(entries: List<&2, StateEntry>) -> List<&2, StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, +rest}:
      Bool.pick(List<&2, StateEntry>, Entries.has_large(rest), Con{entry, Entries.drop_last_large(rest)},
        Bool.pick(List<&2, StateEntry>, StateEntry.is_large(entry), rest, Con{entry, rest}))

# The entries without the rightmost one.
def Entries.drop_last(entries: List<&2, StateEntry>) -> List<&2, StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{entry, +rest}:
      Bool.pick(List<&2, StateEntry>, List.is_empty(&2, StateEntry, rest), Nil{},
        Con{entry, Entries.drop_last(rest)})

# One removal step (spec #1): the rightmost entry larger than 128 octets, or
# the rightmost entry when none is.
def Entries.shrink(+entries: List<&2, StateEntry>) -> List<&2, StateEntry>:
  Bool.pick(List<&2, StateEntry>, Entries.has_large(entries), Entries.drop_last_large(entries),
    Entries.drop_last(entries))

# Remove entries one step at a time while they take more than `budget`
# octets, and stop as soon as they fit. `fuel` bounds the steps. One per
# entry suffices: once every entry is removed, the empty list takes 0 octets,
# which fits any budget.
def Entries.truncate(fuel: Nat, +budget: Nat, +entries: List<&2, StateEntry>) -> List<&2, StateEntry>:
  match fuel:
    case 0n:
      entries
    case 1n+more:
      Bool.pick(List<&2, StateEntry>, Nat.is_le(Entries.size(entries), budget), entries,
        Entries.truncate(more, budget, Entries.shrink(entries)))

# The keys of the entries that `kept` lacks, in order.
def Entries.dropped(entries: List<&2, StateEntry>, +kept: List<&2, StateEntry>) -> List<&2, StateKey>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, rest}:
      Entries.unless(StateKey, Entries.has_key(kept, StateEntry.key_text(entry)), StateEntry.key(entry),
        Entries.dropped(rest, kept))

# Fit a state to the output budget of `limits` by removing whole entries
# (W3C 3.3.3.1, spec #1): while the value is over the budget, remove the
# rightmost entry larger than 128 octets, or the rightmost entry when none is,
# and stop as soon as it fits. The surviving entries keep their order (laws
# truncate_steps, truncate_fits, truncate_whole, truncate_order and
# truncate_dropped).
def TraceState.truncate(limits: Limits, state: TraceState) -> Truncation:
  +entries = TraceState.entries(state)
  +kept = Entries.truncate(List.length(&2, StateEntry, entries), Limits.tracestate_output(limits), entries)
  Truncation{TraceState.from_entries(kept, TraceState.empty()), Entries.dropped(entries, kept)}

# Outgoing contexts
# =================
#
# An outgoing context is a local context with the tracestate its participant
# sends with it: the state attached to a local operation (spec #1). Editing
# that state is allowed because the traceparent of a local context
# identifies an operation of this participant: a root, a child, a restart or
# an operation the caller constructed with Context.from_ids. W3C 3.4 and spec
# #1 forbid sending a received traceparent unchanged with an edited or
# truncated tracestate. The types rule out passing a RemoteContext here, but
# not a local context built with the received IDs: Context.from_ids must only
# be given the IDs of the caller's own operation. A received pair is
# forwarded as it came (#10).

# A local context and the state sent with it.
type OutgoingContext is Data:
  OutgoingContext{context: LocalContext, state: TraceState}

# The two header values an outgoing context emits, and the keys of the
# entries that truncation to the output budget dropped, in their original
# order. A context with no state emits the tracestate "", which injection
# (#10) will handle.
type Emission is Data:
  Emission{traceparent: String, tracestate: String, dropped: List<&2, StateKey>}

# An outgoing context with no state yet, as for a new root.
def OutgoingContext.new(context: LocalContext) -> OutgoingContext:
  OutgoingContext{context, TraceState.empty()}

# An outgoing context that sends `state`, such as the state received with the
# parent of a child operation. The caller associates the state with this
# operation, as with Context.from_ids.
def OutgoingContext.with_state(context: LocalContext, state: TraceState) -> OutgoingContext:
  OutgoingContext{context, state}

# The local operation.
def OutgoingContext.context(outgoing: OutgoingContext) -> LocalContext:
  match outgoing:
    case OutgoingContext{context, state}:
      context

# The state sent with the operation.
def OutgoingContext.state(outgoing: OutgoingContext) -> TraceState:
  match outgoing:
    case OutgoingContext{context, state}:
      state

# The value of the entry with this key, if there is one.
def OutgoingContext.get(outgoing: OutgoingContext, key: StateKey) -> Maybe<&2, StateValue>:
  TraceState.get(OutgoingContext.state(outgoing), key)

# Add or update an entry (see TraceState.set); the context is unchanged (law
# outgoing_set).
def OutgoingContext.set(outgoing: OutgoingContext, key: StateKey, value: StateValue) -> OutgoingContext:
  match outgoing:
    case OutgoingContext{context, state}:
      OutgoingContext{context, TraceState.set(state, key, value)}

# Delete an entry (see TraceState.remove); the context is unchanged (law
# outgoing_remove).
def OutgoingContext.remove(outgoing: OutgoingContext, key: StateKey) -> OutgoingContext:
  match outgoing:
    case OutgoingContext{context, state}:
      OutgoingContext{context, TraceState.remove(state, key)}

# The emission of a context and a truncated state.
def Emission.of(context: LocalContext, truncation: Truncation) -> Emission:
  match truncation:
    case Truncation{kept, dropped}:
      Emission{TraceParentV00.format(LocalContext.to_traceparent(context)), TraceState.format(kept), dropped}

# The traceparent and tracestate values to send: the participating
# traceparent of the context, and the normalized value of the state
# truncated to the output budget of `limits` (laws emit_traceparent,
# emit_tracestate, emit_fits and emit_accepted).
def OutgoingContext.emit(limits: Limits, outgoing: OutgoingContext) -> Emission:
  match outgoing:
    case OutgoingContext{context, state}:
      Emission.of(context, TraceState.truncate(limits, state))

# The traceparent value: always 55 characters.
def Emission.traceparent(emission: Emission) -> String:
  match emission:
    case Emission{traceparent, tracestate, dropped}:
      traceparent

# The tracestate value: at most the output budget in octets, "" for no state.
def Emission.tracestate(emission: Emission) -> String:
  match emission:
    case Emission{traceparent, tracestate, dropped}:
      tracestate

# The keys of the entries truncation dropped, in their original order.
def Emission.dropped(emission: Emission) -> List<&2, StateKey>:
  match emission:
    case Emission{traceparent, tracestate, dropped}:
      dropped
