# bend-trace-context: the pure Trace Context core
# ===============================================
#
# This file is the package's public entry for everything that performs no host
# effect: the strict traceparent v00 codec, validated trace and span IDs and
# their bytes, local and remote contexts, the machine that turns source words
# into IDs, validated limits, the Level 2 tracestate parser, tracestate
# updates and emission, outgoing contexts, the extraction of a received
# message's context, the injection and forwarding of a context into an
# outgoing message's carrier, and the operations that continue or start a
# service's operation for a received message and give each message it sends a
# child of it.
# generation.bend adds the host's cryptographic source on top of it, and
# native_http.bend the header maps of bend-kit's native HTTP package. The
# claims this code must satisfy are stated in LAWS.bend and proved in
# PROOF.bend, beside this file. The tests in tests/*.bend here and the
# repository's consumer in tests/consumer exercise it through the same public
# names.
#
# The normative reference is W3C Trace Context Level 2, Candidate
# Recommendation Draft of 2024-03-28 ("W3C" below, with section numbers). The
# approved specification is issue #1 of the repository ("spec #1"), and issue
# #41 ("spec #41") specifies the building blocks that an OpenTelemetry SDK
# composes.
#
# Contents
#
#   Types                            every data type of the codec, contexts and
#                                    generation, declared first
#   Strict v00 codec                 Parse.*, TraceParentV00.*
#   Identifiers and contexts         TraceId, SpanId, contexts, children,
#                                    restarts
#   Identifiers from source words    U32.to_hex, TraceId.from_words, ...
#   Identifiers as bytes             TraceId.to_bytes, TraceId.from_bytes,
#                                    SpanId.to_bytes, SpanId.from_bytes
#   Generation machine               Draw.*, Step.*, Generation.*,
#                                    Context.*_with, Source.tape
#   Error messages                   Error.show, ContextError.show, ...
#   Limits                           Limits.new, Limits.default, accessors
#   Tracestate                       keys and values, states and lookups,
#                                    budgets, and the reading machine behind
#                                    TraceState.parse
#   Tracestate updates and emission  TraceState.set, remove, size and
#                                    truncate
#   Outgoing contexts                OutgoingContext, a local context with the
#                                    state it sends, and its Emission
#   Extraction                       Context.extract, TraceParent.read,
#                                    incoming and base contexts, diagnostics
#   Injection                        Context.inject and the Injection it
#                                    writes, Context.clear
#   Forwarding                       Context.forward, ForwardError
#   Continuing or starting           Context.continue_or_start_with,
#                                    Reception, FailurePolicy, Service,
#                                    ServicePlan
#   Sending                          Context.send_with, Sent, SendPlan
#
# The public names are documented in packages/trace-context/README.md. Names in
# the Parse, Parsed, ParsedBytes, Draw, Step, Tape, Scan, Member, Value,
# Budget, Utf8, Entries, StateChar, Carrier, Text, Read, Extract, Forward,
# Policy, Serve and Send namespaces are internal: Bend lets any module import
# them, but they are not a compatibility contract.
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
#   value, 32 entries, or the characters of a field name sought.
# - `do Result<...>:` sequences steps that may fail: `x : T <- step` stops at
#   the first Fail, and the block ends with `return v` or with a last step.

import Base
import ./src/hex.bend as Hex
import ./src/digits.bend as Digits

# Types
# =====
#
# The types of the codec, of the identifiers and contexts, and of the
# generation machine. The limits, tracestate, outgoing, extraction, injection,
# forwarding, continue-or-start and sending types are declared in their own
# sections below.

# The field that a ZeroId error names: the trace ID or parent ID of a
# traceparent value, or a supplied span ID.
type Field is Data:
  TraceIdField{}
  ParentIdField{}
  SpanIdField{}

# Why the strict codec, TraceId.parse, SpanId.parse or TraceParent.read
# refused a text, or TraceId.from_bytes or SpanId.from_bytes a list of bytes.
# Offsets count Bend characters (Unicode code points) from zero at the start
# of the text, or cells from zero at the start of the list, and the first
# problem in reading order is reported.
#   UnexpectedEnd{offset}        the text ends where a character is required,
#                                or the list where a byte is
#   InvalidHex{offset}           this character is not a lowercase hex digit
#   InvalidByte{offset}          this cell is above 255, so it is not a byte
#   ExpectedSeparator{offset}    this character should be "-"
#   TrailingInput{}              characters follow a complete value, or cells
#                                follow the bytes of an ID
#   ForbiddenVersion{}           the version is ff, forbidden by W3C 3.2.2.1
#   UnsupportedVersion{version}  a version other than 00, which the strict
#                                codec does not read (TraceParent.read reads
#                                versions 01 to fe by their known prefix)
#   ZeroId{field}                the named ID is all zero, forbidden by W3C
#                                3.2.2.3 and 3.2.2.4
#   ControlCharacter{offset}     this character is a control character other
#                                than a horizontal tab, which no field value
#                                may hold (RFC 9110, section 5.5); only
#                                TraceParent.read reports it, in the fields
#                                of a later version that it does not read
type Error is Data:
  UnexpectedEnd{offset: Nat}
  InvalidHex{offset: Nat}
  InvalidByte{offset: Nat}
  ExpectedSeparator{offset: Nat}
  TrailingInput{}
  ForbiddenVersion{}
  UnsupportedVersion{version: String}
  ZeroId{field: Field}
  ControlCharacter{offset: Nat}

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

# The digits of n bytes read from the front of a list of cells, two digits per
# byte, with the cells that remain after them.
type ParsedBytes<-n: Nat> is Data:
  ParsedBytes{digits: Digits.Digits(Nat.double(n)), rest: List<&2, U32>}

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
# `Context.*_with` operations or generation.bend, and a host that feeds words
# itself uses Generation.
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

# A generation with its word budget, for a host that feeds it one word at a
# time instead of passing a source as a template, such as JavaScript code
# calling this module: the words it may still read (`fuel`) and the
# machine's step. Its fields are internal, like Step: Generation.root and
# its siblings build one. Context.root_with and its siblings drive the same
# values, and a host that feeds words while Generation.needs says so gets
# the pure driver's result (law generation_drive).
type Generation is Data:
  Generation{fuel: Nat, step: Step}

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
# This is the strict wire codec, not a complete W3C propagator:
# TraceParent.read and Context.extract apply the processing rules of W3C 3.2.4
# and 4.1.2, such as reading later versions by their known prefix.
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

# Identifiers as bytes
# ====================
#
# The bytes of an ID are the form of OTLP's protobuf encoding, as the text of
# TraceId.to_string and SpanId.to_string is that of its JSON encoding (spec
# #41, "Identifier forms"). TraceId.to_bytes and TraceId.from_bytes state the
# contract; the helpers below read bytes as Parse.id reads text.

# Put the two digits of one more byte in front of the bytes already read: n
# bytes become 1 + n.
def ParsedBytes.prepend(-n: Nat, digits: Digits.Digits(2n), parsed: ParsedBytes<n>) -> ParsedBytes<1n+n>:
  match digits parsed:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}} ParsedBytes{rest_digits, rest}:
      ParsedBytes{Digits.DCon{high, Digits.DCon{low, rest_digits}}, rest}

# The two digits of a cell, or InvalidByte at its offset when the check found
# the cell above 255.
def Parse.byte.checked(cell: U32, above: Bool, offset: Nat) -> Result<&2, &2, Error, Digits.Digits(2n)>:
  match above:
    case True{}:
      Fail{InvalidByte{offset}}
    case False{}:
      Done{Digits.Digits.of_byte(cell)}

# Read one cell as a byte.
def Parse.byte(+cell: U32, offset: Nat) -> Result<&2, &2, Error, Digits.Digits(2n)>:
  Parse.byte.checked(cell, U32.is_gt(cell, 255), offset)

# Consume exactly n cells as bytes, keeping the cells after them. As in
# Parse.digits, the recursion decreases n, so the result's type has the 2n
# digits of n bytes.
def Parse.bytes(n: Nat, bytes: List<&2, U32>, offset: Nat) -> Result<&2, &2, Error, ParsedBytes<n>>:
  match n:
    case 0n:
      Done{ParsedBytes{Digits.DNil{}, bytes}}
    case 1n+p:
      match bytes:
        case Nil{}:
          Fail{UnexpectedEnd{offset}}
        case Con{cell, tail}:
          +at = offset
          do Result<&2, &2, Error, ParsedBytes<1n+p>>:
            digits : Digits.Digits(2n) <- Parse.byte(cell, at)
            parsed : ParsedBytes<p> <- Parse.bytes(p, tail, 1n+at)
            return ParsedBytes.prepend(p, digits, parsed)

# The list must end after the ID's bytes: a cell after them fails with
# TrailingInput, whatever it holds.
def Parse.bytes_end(bytes: List<&2, U32>) -> Result<&2, &2, Error, Unit>:
  match bytes:
    case Nil{}:
      Done{Unit{}}
    case Con{cell, rest}:
      Fail{TrailingInput{}}

# The bytes of a supplied ID must be the whole list, and not all zero.
def Parse.id_bytes.finish(n: Nat, parsed: ParsedBytes<n>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<Nat.double(n)>>:
  match parsed:
    case ParsedBytes{digits, rest}:
      do Result<&2, &2, Error, Digits.NonZero<Nat.double(n)>>:
        end : Unit <- Parse.bytes_end(rest)
        Parse.nonzero(Nat.double(n), digits, field)

# A supplied ID is exactly n bytes, not all zero.
def Parse.id_bytes(+n: Nat, bytes: List<&2, U32>, field: Field) ->
  Result<&2, &2, Error, Digits.NonZero<Nat.double(n)>>:
  do Result<&2, &2, Error, Digits.NonZero<Nat.double(n)>>:
    parsed : ParsedBytes<n> <- Parse.bytes(n, bytes, 0n)
    Parse.id_bytes.finish(n, parsed, field)

# The 16 bytes of the trace ID, most significant first, in Base's byte
# convention, that of TCP.send_bytes and TCP.recv_bytes: one U32 cell from 0
# to 255 per byte. The first byte holds the ID's first two digits, the first
# of them high. The randomness assertion is not part of the bytes (laws
# trace_bytes, trace_bytes_roundtrip and trace_bytes_injective).
def TraceId.to_bytes(id: TraceId) -> List<&2, U32>:
  match id:
    case TraceId{value, random}:
      Digits.Digits.to_bytes(16n, Digits.NonZero.digits(32n, value))

# Read a trace ID from exactly 16 bytes, most significant first. The cells
# are read in order: a missing cell fails with UnexpectedEnd and a cell above
# 255 with InvalidByte, at its offset counted in cells; a 17th cell fails with
# TrailingInput whatever it holds, and 16 zero bytes with ZeroId. Like a
# parsed ID, the result makes no randomness assertion, since bytes do not say
# how the ID was made; only a caller whose own generator, known to be random,
# made it adds one with TraceId.assert_random. Laws: trace_bytes_inverse,
# bytes_unasserted, trace_bytes_short, trace_bytes_long, trace_bytes_above,
# zero_bytes and trace_bytes_accepts.
def TraceId.from_bytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, TraceId>:
  do Result<&2, &2, Error, TraceId>:
    value : Digits.NonZero<32n> <- Parse.id_bytes(16n, bytes, TraceIdField{})
    return TraceId{value, False{}}

# The 8 bytes of the span ID, most significant first (laws span_bytes,
# span_bytes_roundtrip and span_bytes_injective).
def SpanId.to_bytes(id: SpanId) -> List<&2, U32>:
  match id:
    case SpanId{value}:
      Digits.Digits.to_bytes(8n, Digits.NonZero.digits(16n, value))

# Read a span ID from exactly 8 bytes, most significant first, with the rules
# and errors of TraceId.from_bytes. Laws: span_bytes_inverse,
# span_bytes_short, span_bytes_long, span_bytes_above, zero_bytes and
# span_bytes_accepts.
def SpanId.from_bytes(bytes: List<&2, U32>) -> Result<&2, &2, Error, SpanId>:
  do Result<&2, &2, Error, SpanId>:
    value : Digits.NonZero<16n> <- Parse.id_bytes(8n, bytes, SpanIdField{})
    return SpanId{value}

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

# A root: at most 48 words, eight trace ID candidates of four words and eight
# span ID candidates of two.
def Generation.root() -> Generation:
  Generation{48n, Draw.root()}

# A restart replacing `previous`: at most 48 words, as a root.
def Generation.restart(previous: RemoteContext) -> Generation:
  Generation{48n, Draw.restart(previous)}

# A child of `parent`: at most 16 words, eight span ID candidates.
def Generation.child(+parent: Parent, sampling: Sampling) -> Generation:
  Generation{16n, Draw.child(parent, sampling)}

# Whether a step needs another word within `fuel` more words.
def Generation.needs.of(fuel: Nat, step: Step) -> Bool:
  match fuel step:
    case 0n _:
      False{}
    case 1n+p NeedWord{draw}:
      True{}
    case 1n+p Created{context}:
      False{}
    case 1n+p Failed{error}:
      False{}

# Whether the generation needs another word: it has not ended, and its
# budget allows one more.
def Generation.needs(generation: Generation) -> Bool:
  match generation:
    case Generation{fuel, step}:
      Generation.needs.of(fuel, step)

# The generation after `word`: the step it gives with one word less of
# budget, or, for a step that needs no word, the same step with none left.
def Generation.fed(fuel: Nat, step: Step, word: Result<&1, &1, U32 & String, U32>) -> Generation:
  match fuel step:
    case 0n other:
      Generation{0n, other}
    case 1n+p NeedWord{draw}:
      Generation{p, Draw.feed(word, draw)}
    case 1n+p Created{context}:
      Generation{0n, Created{context}}
    case 1n+p Failed{error}:
      Generation{0n, Failed{error}}

# Feed the generation the next word of its source (see Draw.feed). A
# generation that needs no word ignores it.
def Generation.feed(generation: Generation, word: Result<&1, &1, U32 & String, U32>) -> Generation:
  match generation:
    case Generation{fuel, step}:
      Generation.fed(fuel, step, word)

# The generation's result: the context it created, or why it failed. One that
# still needs a word once its budget is spent has exhausted its candidates;
# the root_ends, child_ends and restart_ends laws show that the budgets
# suffice.
def Generation.result(generation: Generation) -> Result<&2, &2, GenerationError, LocalContext>:
  match generation:
    case Generation{fuel, step}:
      Step.result(step)

# Drive a generation from a caller's source, one word at a time
# (Draw.read), and hand back the source's final state with the result.
def Generation.run_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  generation: Generation) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  match generation:
    case Generation{fuel, step}:
      Draw.finished(~S, Draw.read(~S, ~read, fuel, (source, step)))

# Generated contexts from a caller's source. `read` returns the source's next
# state with each word result. The source is trusted to be random: a generated
# trace ID asserts random-trace-id. A root or restart reads at most 48 words,
# and a child at most 16 (Generation.root and its siblings).
# Laws: root_tape, root_ends, root_exhaustion and generated_root.
def Context.root_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S) ->
  IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Generation.run_with(~S, ~read, source, Generation.root())

# A generated child of `parent` from a caller's source: at most 16 words.
# Laws: child_tape, child_ends, child_exhaustion and generated_child.
def Context.child_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  parent: Parent, sampling: Sampling) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Generation.run_with(~S, ~read, source, Generation.child(parent, sampling))

# A generated restart replacing `previous` from a caller's source: at most 48
# words. Laws: restart_tape, restart_ends and generated_restart.
def Context.restart_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  previous: RemoteContext) -> IO(S & Result<&2, &2, GenerationError, LocalContext>):
  Generation.run_with(~S, ~read, source, Generation.restart(previous))

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
    case InvalidByte{offset}:
      "InvalidByte at " ++ Nat.show(offset)
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
    case ControlCharacter{offset}:
      "ControlCharacter at " ++ Nat.show(offset)

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
# forwarded as it came, by Context.forward.

# A local context and the state sent with it.
type OutgoingContext is Data:
  OutgoingContext{context: LocalContext, state: TraceState}

# The two header values an outgoing context emits, and the keys of the
# entries that truncation to the output budget dropped, in their original
# order. A context with no state emits the tracestate "", which
# Context.inject does not write.
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

# Extraction
# ==========
#
# Context.extract reads the trace context of a received message from its
# carrier: the list of the message's fields in their order, repeated fields
# included (spec #1, "Preserve an ordered multi-value carrier"). Field names
# are compared without regard to ASCII case. A single traceparent field is
# read by TraceParent.read: version 00 exactly as the strict codec reads it,
# ff never, and versions 01 to fe by their known prefix (W3C 3.2.4 and
# 4.1.2). A message whose traceparent is accepted gives an incoming context:
# the sender's operation, the state received with it, and the original pair
# of fields, kept so that Context.forward can send the context unchanged. A
# message without a usable traceparent keeps the base context the caller
# passes, and its tracestate is not read (W3C 3.3). Extraction reads text
# only: it generates no identifier, performs no effect and never includes a
# received value in a diagnostic.

# One field of a message: its name and its value. A carrier is the list of a
# message's fields in their order; repeated fields stay separate, as the
# message carried them. A host that joins repeated fields into one value
# with commas (RFC 9110, section 5.3) gives one field with that value.
type Header is Data:
  Header{name: String, value: String}

# Why extraction refused a message's traceparent:
#   RepeatedTraceParent{}       the message has more than one traceparent field,
#                               or a value that joins several with a comma
#   TraceParentTooLarge{}       the value exceeds the traceparent input budget
#   InvalidTraceParent{error}   the value breaks the rules of its version;
#                               `error` is the first problem, as the codec
#                               reports it, with offsets counted from the
#                               first character after optional whitespace
# The received value itself is never included.
type TraceParentError is Data:
  RepeatedTraceParent{}
  TraceParentTooLarge{}
  InvalidTraceParent{error: Error}

# The original fields of an accepted message: its traceparent value, without
# the optional whitespace around it, and its tracestate field values as they
# came, in arrival order, none when it had no tracestate field. They are what
# Context.forward sends. The input budgets bound the pairs that extraction
# keeps (law received_bounds); a pair built directly with this constructor
# carries no such guarantee, so forwarding checks what it sends. A pair that
# extraction kept is refused only when it exceeds the output budget (law
# forward_extracted).
type ReceivedPair is Data:
  ReceivedPair{traceparent: String, tracestate: List<&2, String>}

# A context extracted from a message: the sender's operation, the state that
# came with it, and the received pair when the whole pair was accepted. It is
# not this participant's operation: a service continues it with a child
# (Context.child_from_id with IncomingContext.parent), or forwards the
# received pair unchanged (Context.forward).
type IncomingContext is Data:
  IncomingContext{context: RemoteContext, state: TraceState, received: Maybe<&2, ReceivedPair>}

# The context to continue from that extraction keeps when a message carries
# no usable traceparent: a context received earlier, or an operation of this
# participant with the state it sends.
type BaseContext is Data:
  IncomingBase{incoming: IncomingContext}
  OutgoingBase{outgoing: OutgoingContext}

# What extraction found in the traceparent fields of a message: an accepted
# value, no field, or a refusal with its reason.
type TraceParentOutcome is Data:
  TraceParentAccepted{}
  TraceParentAbsent{}
  TraceParentRejected{error: TraceParentError}

# What extraction did with the tracestate fields of a message:
#   StateAbsent{}            there was no tracestate field
#   StateAccepted{}          the fields were read into the incoming state,
#                            which may be empty
#   StateDiscarded{error}    the fields were refused as a whole; the incoming
#                            context has no state and the traceparent stays
#                            accepted
#   StateIgnored{}           the fields were not read, because the message has
#                            no accepted traceparent (W3C 3.3)
type StateOutcome is Data:
  StateAbsent{}
  StateAccepted{}
  StateDiscarded{error: StateError}
  StateIgnored{}

# The result of extracting a message: the context to continue from, if any,
# and what happened to each field. `context` is the incoming context of the
# message when its traceparent was accepted, and the base otherwise.
type Extraction is Data:
  Extraction{context: Maybe<&2, BaseContext>, parent: TraceParentOutcome, state: StateOutcome}

# Extraction: carriers
# ====================
#
# A message's fields are selected by name, in their order. Reading a carrier
# is a loop, so a message with many fields needs no deep stack.

# The field's name.
def Header.name(header: Header) -> String:
  match header:
    case Header{name, value}:
      name

# The field's value.
def Header.value(header: Header) -> String:
  match header:
    case Header{name, value}:
      value

# Whether `text` is `name` without regard to ASCII case (W3C 3.2.1 and
# 3.3.1): each character of `text`, with the letters A to Z lowered, is the
# character of `name` at its position. Other characters are compared as they
# are, so a name that differs by more than ASCII case names another field.
# `name` is written in lowercase, and the comparison follows it, so a long
# field name is not read past it.
def Carrier.named(name: String, text: String) -> Bool:
  match name text:
    case SNil{} SNil{}:
      True{}
    case SNil{} SCon{char, rest}:
      False{}
    case SCon{expected, more} SNil{}:
      False{}
    case SCon{expected, more} SCon{char, rest}:
      Bool.and(Char.is_eq(Char.to_lower(char), expected), Carrier.named(more, rest))

# `value` before `found` when `hit` is True: one step of Carrier.values.
def Carrier.keep(hit: Bool, value: String, found: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      Con{value, found}
    case False{}:
      found

# The values of the fields named `name`, most recent first, before `found`.
def Carrier.values.go(carrier: List<&2, Header>, +name: String, found: List<&2, String>) -> List<&2, String>:
  match carrier:
    case Nil{}:
      found
    case Con{+header, rest}:
      Carrier.values.go(rest, name, Carrier.keep(Carrier.named(name, Header.name(header)), Header.value(header), found))

# The values of the fields named `name` without regard to ASCII case, in
# their order: the loop collects them most recent first, and reversing, also
# a loop, puts them back in order.
def Carrier.values(carrier: List<&2, Header>, +name: String) -> List<&2, String>:
  List.reverse(&2, String, Carrier.values.go(carrier, name, Nil{}))

# Extraction: reading a traceparent
# =================================
#
# TraceParent.read measures a value against the traceparent input budget,
# removes the optional whitespace around it, refuses a comma and reads its
# known fields by the rules of its version. Measuring stops at the first
# character past the budget, and the loops below keep the stack flat for a
# value of any length.

# `head` followed by `tail`, without the optional whitespace at its start:
# `ows` says whether `head` is optional whitespace.
def Text.drop_ows.go(tail: String, head: Char, ows: Bool) -> String:
  match tail ows:
    case SNil{} False{}:
      SCon{head, SNil{}}
    case SCon{next, rest} False{}:
      SCon{head, SCon{next, rest}}
    case SNil{} True{}:
      SNil{}
    case SCon{+next, rest} True{}:
      Text.drop_ows.go(rest, next, StateChar.is_ows(next))

# The text without the optional whitespace, spaces and horizontal tabs, at its
# start.
def Text.drop_ows(text: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{+head, tail}:
      Text.drop_ows.go(tail, head, StateChar.is_ows(head))

# The text without the optional whitespace at its start and at its end (RFC
# 9110, section 5.5: "A field value does not include leading or trailing
# whitespace"). Reversing brings the end to the front, and reversing again
# brings it back.
def Text.trim_ows(text: String) -> String:
  String.reverse(Text.drop_ows(String.reverse(Text.drop_ows(text))))

# Whether the text contains a comma: `found` records whether one was seen
# before.
def Text.has_comma.go(text: String, found: Bool) -> Bool:
  match text found:
    case _ True{}:
      True{}
    case SNil{} False{}:
      False{}
    case SCon{char, rest} False{}:
      Text.has_comma.go(rest, Char.is_eq(char, ','))

# Whether the text contains a comma.
def Text.has_comma(text: String) -> Bool:
  Text.has_comma.go(text, False{})

# Whether a character is a control character other than a horizontal tab:
# U+0000 to U+0008, U+000A to U+001F or U+007F. No field value may hold one
# (RFC 9110, section 5.5); a carriage return or a line feed would end the
# field.
def Text.is_control(char: Char) -> Bool:
  match char:
    case Chr{+code}:
      Bool.or(Bool.and(U32.is_lt(code, 32), Bool.not(U32.is_eq(code, 9))), U32.is_eq(code, 127))

# The offset of the first control character of `text`, counted from
# `offset`, unless `found` already holds one. This is a loop.
def Text.control.go(text: String, +offset: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text found:
    case _ Some{at}:
      Some{at}
    case SNil{} None{}:
      None{}
    case SCon{char, rest} None{}:
      Text.control.go(rest, 1n+offset, Bool.pick(Maybe<&2, Nat>, Text.is_control(char), Some{offset}, None{}))

# Whether a value's version, from its two digits, is later than 00 and so
# read by its known prefix (W3C 3.2.2.1 and 3.2.4): Done{False{}} for 00,
# which the strict codec reads, Done{True{}} for 01 to fe, and a refusal for
# ff.
def Read.is_later(digits: Digits.Digits(2n)) -> Result<&2, &2, Error, Bool>:
  match digits:
    case Digits.DCon{Hex.H0{}, Digits.DCon{Hex.H0{}, Digits.DNil{}}}:
      Done{False{}}
    case Digits.DCon{Hex.Hf{}, Digits.DCon{Hex.Hf{}, Digits.DNil{}}}:
      Fail{ForbiddenVersion{}}
    case other:
      Done{True{}}

# Whether the version whose two digits were read is later than 00.
def Read.is_later.parsed(parsed: Parsed<2n>) -> Result<&2, &2, Error, Bool>:
  match parsed:
    case Parsed{digits, rest}:
      Read.is_later(digits)

# The fields a later version does not know, once searched for a control
# character: none, or the offset of the first.
def Read.clean(found: Maybe<&2, Nat>) -> Result<&2, &2, Error, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{offset}:
      Fail{ControlCharacter{offset}}

# What may follow the flags of a later version: the end of the value, or a
# dash that starts fields this version does not know. Those fields are not
# read (W3C 3.2.4: "Vendors MUST NOT parse or assume anything about unknown
# fields"), except that a control character in them is refused with
# ControlCharacter at its offset: no field value may hold one (RFC 9110,
# section 5.5), and a value forwarded unchanged must not end a message's
# field. Any other character than a dash at offset 55 is ExpectedSeparator.
def Read.extension(rest: String) -> Result<&2, &2, Error, Unit>:
  match rest:
    case SNil{}:
      Done{Unit{}}
    case SCon{char, tail}:
      do Result<&2, &2, Error, Unit>:
        unknown : String <- Parse.separator_result(tail, Char.is_eq(char, '-'), 55n)
        Read.clean(Text.control.go(unknown, 56n, None{}))

# A later version is read by its known prefix (W3C 3.2.4 and 4.1.2): its first
# 55 characters are read as version 00, which checks the trace ID, the parent
# ID, the flags and the dashes between them at their own offsets, and then the
# value must end or continue with a dash. A value that ends before its 55th
# character, with no invalid character before, fails with UnexpectedEnd.
def Read.prefix(+text: String) -> Result<&2, &2, Error, TraceParentV00>:
  do Result<&2, &2, Error, TraceParentV00>:
    known : TraceParentV00 <- TraceParentV00.parse("00" ++ String.drop(String.take(text, 55n), 2n))
    rest : Unit <- Read.extension(String.drop(text, 55n))
    return known

# Read a value by the rules of its version: `later` is False for 00.
def Read.by_version(later: Bool, text: String) -> Result<&2, &2, Error, TraceParentV00>:
  match later:
    case False{}:
      TraceParentV00.parse(text)
    case True{}:
      Read.prefix(text)

# The known fields of a value, read by the rules of its version.
def Read.known(+text: String) -> Result<&2, &2, Error, TraceParentV00>:
  do Result<&2, &2, Error, TraceParentV00>:
    version : Parsed<2n> <- Parse.digits(2n, text, 0n)
    later : Bool <- Read.is_later.parsed(version)
    Read.by_version(later, text)

# A refusal of the codec, as a refused traceparent.
def Read.invalid(result: Result<&2, &2, Error, TraceParentV00>) ->
  Result<&2, &2, TraceParentError, TraceParentV00>:
  match result:
    case Fail{error}:
      Fail{InvalidTraceParent{error}}
    case Done{value}:
      Done{value}

# A value that joins several with a comma is refused as repeated fields; any
# other value is read by the rules of its version.
def Read.single(combined: Bool, text: String) -> Result<&2, &2, TraceParentError, TraceParentV00>:
  match combined:
    case True{}:
      Fail{RepeatedTraceParent{}}
    case False{}:
      Read.invalid(Read.known(text))

# A value without the whitespace around it, refused when it joins several.
def Read.trimmed(+text: String) -> Result<&2, &2, TraceParentError, TraceParentV00>:
  Read.single(Text.has_comma(text), text)

# A value within its budget is read without the optional whitespace around
# it; a value over the budget is refused without being read further.
def Read.within(fits: Maybe<&2, Nat>, value: String) -> Result<&2, &2, TraceParentError, TraceParentV00>:
  match fits:
    case None{}:
      Fail{TraceParentTooLarge{}}
    case Some{left}:
      Read.trimmed(Text.trim_ows(value))

# Read one received traceparent value by the rules of a participant, and
# return its known fields as a v00 value, flag byte included:
#   - a value over the traceparent input budget of `limits`, counted in UTF-8
#     octets with its whitespace, is refused with TraceParentTooLarge;
#   - optional whitespace around the value is removed (RFC 9110, section 5.5);
#   - a value with a comma joins repeated fields and is refused with
#     RepeatedTraceParent, even when the comma is in fields of a later
#     version: no version defines a comma, and a host that joins repeated
#     fields separates them with one (RFC 9110, section 5.3);
#   - version 00 is read exactly by TraceParentV00.parse: 55 characters and
#     nothing after them;
#   - version ff is refused with ForbiddenVersion (W3C 3.2.2.1);
#   - versions 01 to fe are read by their known prefix: the fields of version
#     00, followed by the end of the value or by a dash and fields that are
#     not read, whatever they hold other than a comma or a control character,
#     which is refused with ControlCharacter (W3C 3.2.4 and 4.1.2; RFC 9110,
#     section 5.5).
# RemoteContext.from_traceparent then keeps the sampled and random-trace-id
# flags. Laws: read_v00, read_v00_exact, read_future, read_ff, read_comma,
# read_over_budget and read_within_budgets.
def TraceParent.read(limits: Limits, +value: String) -> Result<&2, &2, TraceParentError, TraceParentV00>:
  Read.within(Utf8.left(value, Some{Limits.traceparent_input(limits)}), value)

# Extraction: messages
# ====================
#
# Extract.parents decides from the traceparent values: none keeps the base,
# several are refused, and a single value is read. Only an accepted value lets
# the tracestate values be read.

# The state outcome when the tracestate fields are not read: absent without
# a field, ignored with one (W3C 3.3).
def Extract.ignored(states: List<&2, String>) -> StateOutcome:
  match states:
    case Nil{}:
      StateAbsent{}
    case Con{field, rest}:
      StateIgnored{}

# The extraction of a message whose context is not read: the base is kept,
# with the traceparent outcome and the presence of tracestate fields.
def Extract.kept(base: Maybe<&2, BaseContext>, parent: TraceParentOutcome, states: List<&2, String>) -> Extraction:
  Extraction{base, parent, Extract.ignored(states)}

# The incoming context of an accepted message, as the context to continue
# from.
def Extract.incoming(remote: RemoteContext, state: TraceState, received: Maybe<&2, ReceivedPair>) ->
  Maybe<&2, BaseContext>:
  Some{IncomingBase{IncomingContext{remote, state, received}}}

# An accepted message whose tracestate fields were parsed: an accepted state
# keeps the pair, which can be forwarded, and a refused one is discarded
# whole, keeping the traceparent (spec #1) but no pair, since the pair was not
# accepted whole.
def Extract.parsed(parsed: Result<&2, &2, StateError, TraceState>, remote: RemoteContext, text: String,
  states: List<&2, String>) -> Extraction:
  match parsed:
    case Fail{error}:
      Extraction{Extract.incoming(remote, TraceState.empty(), None{}), TraceParentAccepted{}, StateDiscarded{error}}
    case Done{state}:
      Extraction{Extract.incoming(remote, state, Some{ReceivedPair{text, states}}), TraceParentAccepted{},
        StateAccepted{}}

# An accepted message with its tracestate field values, read in arrival order
# as their comma-joined combination (W3C 3.3.2).
def Extract.state(+limits: Limits, +states: List<&2, String>, remote: RemoteContext, text: String) -> Extraction:
  match states:
    case Nil{}:
      Extraction{Extract.incoming(remote, TraceState.empty(), Some{ReceivedPair{text, Nil{}}}), TraceParentAccepted{},
        StateAbsent{}}
    case Con{field, rest}:
      Extract.parsed(TraceState.parse_fields(limits, Con{field, rest}), remote, text, Con{field, rest})

# The extraction of a message whose only traceparent value `value` was read.
# The value is kept without the whitespace around it only once accepted, so a
# refused value is not read further.
def Extract.read(read: Result<&2, &2, TraceParentError, TraceParentV00>, value: String, +limits: Limits,
  +states: List<&2, String>, base: Maybe<&2, BaseContext>) -> Extraction:
  match read:
    case Fail{error}:
      Extract.kept(base, TraceParentRejected{error}, states)
    case Done{known}:
      Extract.state(limits, states, RemoteContext.from_traceparent(known), Text.trim_ows(value))

# The extraction of a message with these traceparent and tracestate field
# values.
def Extract.parents(+limits: Limits, parents: List<&2, String>, +states: List<&2, String>,
  base: Maybe<&2, BaseContext>) -> Extraction:
  match parents:
    case Nil{}:
      Extract.kept(base, TraceParentAbsent{}, states)
    case Con{+value, Nil{}}:
      Extract.read(TraceParent.read(limits, value), value, limits, states, base)
    case Con{first, Con{second, more}}:
      Extract.kept(base, TraceParentRejected{RepeatedTraceParent{}}, states)

# Extract the trace context of a received message from its carrier, with
# `base` as the context to keep when the message has no usable traceparent
# (spec #1, user stories 14, 15, 16, 24 and 25):
#   - no traceparent field keeps the base, TraceParentAbsent{};
#   - more than one traceparent field, whatever the case of their names, is
#     refused, and so is a single value that TraceParent.read refuses; the
#     base is kept, TraceParentRejected{error};
#   - an accepted value gives the incoming context and replaces the base: its
#     tracestate fields, whatever the case of their names, are read in
#     arrival order as their comma-joined combination, within the tracestate
#     input budget; refused fields are discarded whole, keeping the
#     traceparent;
#   - without an accepted traceparent, tracestate fields are not read.
# Laws: extract_absent, extract_repeated, extract_refused, extract_read,
# state_independent and received_bounds.
def Context.extract(+limits: Limits, +carrier: List<&2, Header>, base: Maybe<&2, BaseContext>) -> Extraction:
  Extract.parents(limits, Carrier.values(carrier, "traceparent"), Carrier.values(carrier, "tracestate"), base)

# Extraction: results and diagnostics
# ===================================

# The context to continue from: this message's incoming context when its
# traceparent was accepted, the base otherwise.
def Extraction.context(extraction: Extraction) -> Maybe<&2, BaseContext>:
  match extraction:
    case Extraction{context, parent, state}:
      context

# What extraction found in the traceparent fields.
def Extraction.parent(extraction: Extraction) -> TraceParentOutcome:
  match extraction:
    case Extraction{context, parent, state}:
      parent

# What extraction did with the tracestate fields.
def Extraction.state(extraction: Extraction) -> StateOutcome:
  match extraction:
    case Extraction{context, parent, state}:
      state

# The incoming context an accepted message gives as its context.
def Extraction.incoming.base(context: Maybe<&2, BaseContext>) -> Maybe<&2, IncomingContext>:
  match context:
    case Some{IncomingBase{incoming}}:
      Some{incoming}
    case _:
      None{}

# This message's own context: the incoming context when its traceparent was
# accepted, None{} when extraction kept the base.
def Extraction.incoming.of(parent: TraceParentOutcome, context: Maybe<&2, BaseContext>) ->
  Maybe<&2, IncomingContext>:
  match parent:
    case TraceParentAccepted{}:
      Extraction.incoming.base(context)
    case TraceParentAbsent{}:
      None{}
    case TraceParentRejected{error}:
      None{}

# The context this message carried, when its traceparent was accepted; None{}
# when extraction kept the base, even an incoming one.
def Extraction.incoming(extraction: Extraction) -> Maybe<&2, IncomingContext>:
  match extraction:
    case Extraction{context, parent, state}:
      Extraction.incoming.of(parent, context)

# The sender's operation.
def IncomingContext.context(incoming: IncomingContext) -> RemoteContext:
  match incoming:
    case IncomingContext{context, state, received}:
      context

# The state received with it: empty when the message had none or when it was
# discarded.
def IncomingContext.state(incoming: IncomingContext) -> TraceState:
  match incoming:
    case IncomingContext{context, state, received}:
      state

# The received pair, when the whole pair was accepted: None{} when the
# tracestate was discarded.
def IncomingContext.received(incoming: IncomingContext) -> Maybe<&2, ReceivedPair>:
  match incoming:
    case IncomingContext{context, state, received}:
      received

# The received context as the parent of a child operation.
def IncomingContext.parent(incoming: IncomingContext) -> Parent:
  RemoteParent{IncomingContext.context(incoming)}

# The received traceparent value, without the whitespace around it.
def ReceivedPair.traceparent(pair: ReceivedPair) -> String:
  match pair:
    case ReceivedPair{traceparent, tracestate}:
      traceparent

# The received tracestate field values, in arrival order.
def ReceivedPair.tracestate(pair: ReceivedPair) -> List<&2, String>:
  match pair:
    case ReceivedPair{traceparent, tracestate}:
      tracestate

# The base as the parent of a child operation: a received context or an
# operation of this participant.
def BaseContext.parent(base: BaseContext) -> Parent:
  match base:
    case IncomingBase{incoming}:
      IncomingContext.parent(incoming)
    case OutgoingBase{outgoing}:
      LocalParent{OutgoingContext.context(outgoing)}

# The state that goes with the base: the state received with an incoming
# context, or the state an outgoing context sends.
def BaseContext.state(base: BaseContext) -> TraceState:
  match base:
    case IncomingBase{incoming}:
      IncomingContext.state(incoming)
    case OutgoingBase{outgoing}:
      OutgoingContext.state(outgoing)

# The name of a traceparent error; InvalidTraceParent adds the codec's error.
def TraceParentError.show(error: TraceParentError) -> String:
  match error:
    case RepeatedTraceParent{}:
      "RepeatedTraceParent"
    case TraceParentTooLarge{}:
      "TraceParentTooLarge"
    case InvalidTraceParent{reason}:
      "InvalidTraceParent " ++ Error.show(reason)

# The name of a traceparent outcome; a rejection adds its error.
def TraceParentOutcome.show(outcome: TraceParentOutcome) -> String:
  match outcome:
    case TraceParentAccepted{}:
      "TraceParentAccepted"
    case TraceParentAbsent{}:
      "TraceParentAbsent"
    case TraceParentRejected{error}:
      "TraceParentRejected " ++ TraceParentError.show(error)

# The name of a tracestate outcome; a discard adds its error.
def StateOutcome.show(outcome: StateOutcome) -> String:
  match outcome:
    case StateAbsent{}:
      "StateAbsent"
    case StateAccepted{}:
      "StateAccepted"
    case StateDiscarded{error}:
      "StateDiscarded " ++ StateError.show(error)
    case StateIgnored{}:
      "StateIgnored"

# Both outcomes of an extraction, for a log line: "TraceParentAccepted,
# StateDiscarded InvalidEntry 1 MissingEquals" for example. No received
# value is included, so the line can be logged as it is.
def Extraction.show(extraction: Extraction) -> String:
  match extraction:
    case Extraction{context, parent, state}:
      TraceParentOutcome.show(parent) ++ ", " ++ StateOutcome.show(state)

# Injection
# =========
#
# Context.inject writes the context of an operation of this participant into
# the carrier of an outgoing message (spec #1, "Participant injection"):
# every old traceparent and tracestate field is removed, whatever the ASCII
# case of its name, the other fields keep their order, and the emitted
# fields are added at the end with lowercase names. An empty tracestate is
# not written. Context.clear removes the context fields alone, for a message
# sent without context. Neither generates an identifier.

# The carrier an injection writes, and the keys of the entries that
# truncation to the output budget dropped from the state, in their original
# order: diagnostics, kept apart from the carrier.
type Injection is Data:
  Injection{carrier: List<&2, Header>, dropped: List<&2, StateKey>}

# Whether a field name is traceparent or tracestate, without regard to ASCII
# case.
def Carrier.is_context(+name: String) -> Bool:
  Bool.or(Carrier.named("traceparent", name), Carrier.named("tracestate", name))

# `header` before `kept` unless it is a context field (`context_field`): one
# step of Carrier.unrelated.go.
def Carrier.keep_unrelated(context_field: Bool, header: Header, kept: List<&2, Header>) -> List<&2, Header>:
  match context_field:
    case True{}:
      kept
    case False{}:
      Con{header, kept}

# The unrelated fields, those that are not context fields, most recent first,
# before `kept`. This is a loop, so a message with many fields needs no deep
# stack.
def Carrier.unrelated.go(carrier: List<&2, Header>, kept: List<&2, Header>) -> List<&2, Header>:
  match carrier:
    case Nil{}:
      kept
    case Con{+header, rest}:
      Carrier.unrelated.go(rest, Carrier.keep_unrelated(Carrier.is_context(Header.name(header)), header, kept))

# The carrier's unrelated fields, followed by `fields`: reversing the loop's
# result onto `fields`, also a loop, puts them back in order.
def Carrier.replace(carrier: List<&2, Header>, fields: List<&2, Header>) -> List<&2, Header>:
  List.reverse.go(&2, Header, Carrier.unrelated.go(carrier, Nil{}), fields)

# The context fields of a traceparent value and a tracestate value, with
# lowercase names; the tracestate field is left out when its value is empty.
def Carrier.context_fields(traceparent: String, +tracestate: String) -> List<&2, Header>:
  Con{Header{"traceparent", traceparent}, Bool.pick(List<&2, Header>, String.is_empty(tracestate), Nil{},
    Con{Header{"tracestate", tracestate}, Nil{}})}

# Remove every traceparent and tracestate field, whatever the case of its
# name, and keep the other fields in their order: the carrier of a message
# sent without context (spec #1, "Provide explicit context-field cleanup for
# the no-context path"). Law: clear_carrier.
def Context.clear(carrier: List<&2, Header>) -> List<&2, Header>:
  Carrier.replace(carrier, Nil{})

# The injection of an emission into a carrier.
def Injection.of(carrier: List<&2, Header>, emission: Emission) -> Injection:
  match emission:
    case Emission{traceparent, tracestate, dropped}:
      Injection{Carrier.replace(carrier, Carrier.context_fields(traceparent, tracestate)), dropped}

# Write an outgoing context into a carrier as a participant: the context
# fields of the carrier are replaced by the emitted traceparent, version 00
# with only the sampled and random-trace-id flags, and the emitted
# tracestate, truncated to the output budget of `limits` and left out when
# empty. The other fields keep their order, and injecting the same context
# into the carrier written gives that carrier again. A receiver that extracts
# the carrier with the same limits continues the injected operation with the
# truncated state. Laws: inject_carrier, inject_dropped, inject_idempotent and
# inject_extracted.
def Context.inject(limits: Limits, outgoing: OutgoingContext, carrier: List<&2, Header>) -> Injection:
  Injection.of(carrier, OutgoingContext.emit(limits, outgoing))

# The carrier to send.
def Injection.carrier(injection: Injection) -> List<&2, Header>:
  match injection:
    case Injection{carrier, dropped}:
      carrier

# The keys of the entries truncation dropped, in their original order; none
# when the state fitted.
def Injection.dropped(injection: Injection) -> List<&2, StateKey>:
  match injection:
    case Injection{carrier, dropped}:
      dropped

# Forwarding
# ==========
#
# Context.forward sends a received context on unchanged, as a service that
# does not take part in the trace does (W3C 3.4, "Unmodified header
# propagation"): the traceparent value and the tracestate text of its
# received pair, without normalizing flags, downgrading the version, or
# editing or truncating the tracestate. The tracestate fields are joined into
# one field (W3C 3.3.2: tracestate "SHOULD be sent as a single field when
# possible"), and the old context fields of the carrier are replaced, as by
# injection. When the pair cannot be sent whole within the limits, forwarding
# refuses it: the caller may continue the trace with a child operation
# instead, whose own traceparent lets its state be truncated (spec #1).

# Why a received context could not be forwarded unchanged:
#   NothingToForward{}            it keeps no received pair: its tracestate was
#                                 discarded when it was extracted
#   ForwardTooLarge{}             its tracestate fields, joined by commas,
#                                 exceed the tracestate output budget
#   InvalidForwardParent{error}   its traceparent value is not one that
#                                 TraceParent.read accepts
#   InvalidForwardState{error}    its tracestate fields are not ones that
#                                 TraceState.parse_fields accepts
# A pair that extraction keeps always passes the last two checks (law
# forward_extracted); they refuse a pair built directly.
type ForwardError is Data:
  NothingToForward{}
  ForwardTooLarge{}
  InvalidForwardParent{error: TraceParentError}
  InvalidForwardState{error: StateError}

# The fields joined by commas, most recent character first, after `done`:
# each field is reversed onto the comma before it. This is a loop.
def Text.joined.go(fields: List<&2, String>, done: String) -> String:
  match fields:
    case Nil{}:
      done
    case Con{field, rest}:
      Text.joined.go(rest, String.reverse.go(field, SCon{',', done}))

# The fields joined by commas into one value, as String.join(fields, ",")
# writes it. It is built by loops, so fields of any length need no deep
# stack.
def Text.joined(fields: List<&2, String>) -> String:
  match fields:
    case Nil{}:
      SNil{}
    case Con{field, rest}:
      String.reverse(Text.joined.go(rest, String.reverse.go(field, SNil{})))

# The carrier with its context fields replaced by a received pair: the
# traceparent value, and the tracestate fields joined into one value, left
# out when empty.
def Forward.carrier(carrier: List<&2, Header>, traceparent: String, tracestate: List<&2, String>) -> List<&2, Header>:
  Carrier.replace(carrier, Carrier.context_fields(traceparent, Text.joined(tracestate)))

# The last check of a forwarded pair: its tracestate fields parse.
def Forward.state(parsed: Result<&2, &2, StateError, TraceState>, carrier: List<&2, Header>, traceparent: String,
  tracestate: List<&2, String>) -> Result<&2, &2, ForwardError, List<&2, Header>>:
  match parsed:
    case Fail{error}:
      Fail{InvalidForwardState{error}}
    case Done{state}:
      Done{Forward.carrier(carrier, traceparent, tracestate)}

# The second check of a forwarded pair: its traceparent value reads back.
def Forward.parent(read: Result<&2, &2, TraceParentError, TraceParentV00>, +limits: Limits, carrier: List<&2, Header>,
  traceparent: String, +tracestate: List<&2, String>) -> Result<&2, &2, ForwardError, List<&2, Header>>:
  match read:
    case Fail{error}:
      Fail{InvalidForwardParent{error}}
    case Done{known}:
      Forward.state(TraceState.parse_fields(limits, tracestate), carrier, traceparent, tracestate)

# The first check of a forwarded pair: its tracestate fields, joined by
# commas, fit the output budget. Measuring stops past the budget.
def Forward.fits(fits: Maybe<&2, Nat>, +limits: Limits, carrier: List<&2, Header>, +traceparent: String,
  +tracestate: List<&2, String>) -> Result<&2, &2, ForwardError, List<&2, Header>>:
  match fits:
    case None{}:
      Fail{ForwardTooLarge{}}
    case Some{left}:
      Forward.parent(TraceParent.read(limits, traceparent), limits, carrier, traceparent, tracestate)

# Forward the received pair, if there is one.
def Forward.pair(+limits: Limits, received: Maybe<&2, ReceivedPair>, carrier: List<&2, Header>) ->
  Result<&2, &2, ForwardError, List<&2, Header>>:
  match received:
    case None{}:
      Fail{NothingToForward{}}
    case Some{ReceivedPair{+traceparent, +tracestate}}:
      Forward.fits(Utf8.left_fields(tracestate, Some{Limits.tracestate_output(limits)}), limits, carrier, traceparent,
        tracestate)

# Forward a received context unchanged into a carrier: its context fields are
# replaced by the traceparent value of the received pair and by its
# tracestate fields joined into one field, and the other fields keep their
# order. The pair must be there, its tracestate must fit the output budget of
# `limits` whole, and both fields must read back under `limits`; otherwise
# forwarding fails with a ForwardError and writes nothing, so a received
# traceparent never travels with an edited or truncated tracestate (W3C 3.4).
# The pair of a context that extraction accepted is refused only when its
# tracestate exceeds the output budget, and forwarding again into the carrier
# written gives that carrier again. Laws: forward_carrier, forward_nothing,
# forward_too_large, forward_extracted and forward_idempotent.
def Context.forward(+limits: Limits, incoming: IncomingContext, carrier: List<&2, Header>) ->
  Result<&2, &2, ForwardError, List<&2, Header>>:
  Forward.pair(limits, IncomingContext.received(incoming), carrier)

# The name of a forwarding error; an invalid field adds its error.
def ForwardError.show(error: ForwardError) -> String:
  match error:
    case NothingToForward{}:
      "NothingToForward"
    case ForwardTooLarge{}:
      "ForwardTooLarge"
    case InvalidForwardParent{reason}:
      "InvalidForwardParent " ++ TraceParentError.show(reason)
    case InvalidForwardState{reason}:
      "InvalidForwardState " ++ StateError.show(reason)

# Continuing or starting
# ======================
#
# Context.continue_or_start_with gives a service its own operation for a
# received message (spec #1, "Continue-or-start creates a child when
# extraction or the retained base supplies a usable context, and creates a
# root otherwise"): a child of the context that extraction keeps, the
# message's or the base, or a root when it keeps none. At a trust boundary, a
# new trace replaces the kept context instead. Context.send_with then gives
# each message the service sends a child of that operation. When generating
# an identifier fails, the policy decides: Lenient{} carries on without an
# operation, forwarding the received pair unchanged when it can and sending
# no context otherwise, and Strict{} returns the error so that the caller can
# refuse the operation.

# How a service takes the context that extraction keeps, the message's or
# the base:
#   Continue{}   continue it with a child
#   Restart{}    replace it with a new trace, as at a trust boundary: its
#                trace ID is not reused, its state is discarded and the root
#                defaults apply
type Reception is Data:
  Continue{}
  Restart{}

# What the operations do when generating an identifier fails:
#   Lenient{}   carry on without a new operation; the result says why
#   Strict{}    fail with the GenerationError, so that the caller can refuse
#               the operation
type FailurePolicy is Data:
  Lenient{}
  Strict{}

# How a service's operation came about:
#   Continued{}   a child of the context that extraction kept
#   Started{}     a root: extraction kept no context
#   Restarted{}   a new trace in place of the kept context (Restart{})
type Origin is Data:
  Continued{}
  Started{}
  Restarted{}

# The service's own operation for a received message, with the state it
# sends, or the error that left it without one. `received` is the message's
# incoming context when the service continues it, kept so that a message it
# sends can forward the received pair if generating fails; it is None{} for
# a root, a restart or a continued base.
type Service is Data:
  Operating{origin: Origin, outgoing: OutgoingContext, received: Maybe<&2, IncomingContext>}
  Untraced{error: GenerationError, received: Maybe<&2, IncomingContext>}

# The type an operation returns under `policy`: the value itself with
# Lenient{}, and the value or the GenerationError with Strict{}.
def FailurePolicy.result(policy: FailurePolicy, A: Data) -> Data:
  match policy:
    case Lenient{}:
      A
    case Strict{}:
      Result<&2, &2, GenerationError, A>

# A value under `policy`: itself with Lenient{}, and what `strict` makes of it
# with Strict{}.
def Policy.apply(policy: FailurePolicy, -A: Data, strict: A -> Result<&2, &2, GenerationError, A>, value: A) ->
  FailurePolicy.result(policy, A):
  match policy:
    case Lenient{}:
      value
    case Strict{}:
      strict(value)

# The source's final state with a value under `policy`.
def Policy.apply.done(-S: Type, policy: FailurePolicy, -A: Data, strict: A -> Result<&2, &2, GenerationError, A>,
  done: S & A) -> S & FailurePolicy.result(policy, A):
  (source, value) = done
  (source, Policy.apply(policy, A, strict, value))

# A new trace's operation with the sampled indication that `sampling`
# resolves from the root default, not sampled: InheritSampled{} has nothing
# to inherit, and SetSampled{} sets its own.
def Serve.start(sampling: Sampling, +context: LocalContext) -> LocalContext:
  LocalContext{LocalContext.trace_id(context), LocalContext.span_id(context), Sampling.resolve(sampling, False{})}

# The service that a child of the kept context gives, with `state`, or
# Untraced with the error.
def Serve.from_child(state: TraceState, received: Maybe<&2, IncomingContext>,
  result: Result<&2, &2, GenerationError, LocalContext>) -> Service:
  match result:
    case Fail{error}:
      Untraced{error, received}
    case Done{context}:
      Operating{Continued{}, OutgoingContext.with_state(context, state), received}

# The service that a new trace gives: the sampling of Serve.start and no
# state, or Untraced with the error. A new trace keeps no received pair.
def Serve.from_start(origin: Origin, sampling: Sampling, result: Result<&2, &2, GenerationError, LocalContext>) ->
  Service:
  match result:
    case Fail{error}:
      Untraced{error, None{}}
    case Done{context}:
      Operating{origin, OutgoingContext.new(Serve.start(sampling, context)), None{}}

# The service's operation as Context.continue_or_start_with decides it for
# a received message, before it reads any word: the generation to drive and
# what the generation's result makes of the service.
#   ContinuePlan{generation, state, received}   a child of the kept context,
#                                               sending its `state`
#   StartPlan{generation, origin, sampling}     a root or a restart
# A host that feeds a generation one word at a time, such as JavaScript code
# calling this module, drives ServicePlan.generation and hands the result to
# ServicePlan.service (law hosted_service).
type ServicePlan is Data:
  ContinuePlan{generation: Generation, state: TraceState, received: Maybe<&2, IncomingContext>}
  StartPlan{generation: Generation, origin: Origin, sampling: Sampling}

# The context that a restart replaces, as Generation.restart takes it: an
# incoming base's received context, or an outgoing base's operation as
# another participant receives it. The new trace ID reuses neither.
def Serve.replaced(base: BaseContext) -> RemoteContext:
  match base:
    case IncomingBase{incoming}:
      IncomingContext.context(incoming)
    case OutgoingBase{outgoing}:
      RemoteContext.from_traceparent(LocalContext.to_traceparent(OutgoingContext.context(outgoing)))

# Continue the kept context with a child, with its parent and state, or
# replace it with a new trace, as `reception` says.
def Serve.usable(+base: BaseContext, received: Maybe<&2, IncomingContext>, reception: Reception,
  sampling: Sampling) -> ServicePlan:
  match reception:
    case Continue{}:
      ContinuePlan{Generation.child(BaseContext.parent(base), sampling), BaseContext.state(base), received}
    case Restart{}:
      StartPlan{Generation.restart(Serve.replaced(base)), Restarted{}, sampling}

# Take the context that extraction keeps, or start a root without one.
def Serve.kept(context: Maybe<&2, BaseContext>, received: Maybe<&2, IncomingContext>, reception: Reception,
  sampling: Sampling) -> ServicePlan:
  match context:
    case None{}:
      StartPlan{Generation.root(), Started{}, sampling}
    case Some{+base}:
      Serve.usable(base, received, reception, sampling)

# The plan of the service's operation for a message (see ServicePlan).
def ServicePlan.new(+extraction: Extraction, reception: Reception, sampling: Sampling) -> ServicePlan:
  Serve.kept(Extraction.context(extraction), Extraction.incoming(extraction), reception, sampling)

# The generation that the plan drives.
def ServicePlan.generation(plan: ServicePlan) -> Generation:
  match plan:
    case ContinuePlan{generation, state, received}:
      generation
    case StartPlan{generation, origin, sampling}:
      generation

# The service that the result of the plan's generation gives, before the
# policy applies: its operation, or Untraced with the error.
def ServicePlan.service(plan: ServicePlan, result: Result<&2, &2, GenerationError, LocalContext>) -> Service:
  match plan:
    case ContinuePlan{generation, state, received}:
      Serve.from_child(state, received, result)
    case StartPlan{generation, origin, sampling}:
      Serve.from_start(origin, sampling, result)

# The source's final state with the service that the plan gives.
def Serve.finish(-S: Type, plan: ServicePlan, done: S & Result<&2, &2, GenerationError, LocalContext>) ->
  S & Service:
  (source, result) = done
  (source, ServicePlan.service(plan, result))

# Drive the plan's generation from a caller's source.
def Serve.run(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S, +plan: ServicePlan) ->
  IO(S & Service):
  IO.bind(S & Result<&2, &2, GenerationError, LocalContext>, S & Service,
    Generation.run_with(~S, ~read, source, ServicePlan.generation(plan)),
    done => IO.pure(S & Service, Serve.finish(S, plan, done)))

# The service for a message, before the policy applies.
def Serve.operation(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  +extraction: Extraction, reception: Reception, sampling: Sampling) -> IO(S & Service):
  Serve.run(~S, ~read, source, ServicePlan.new(extraction, reception, sampling))

# A service without an operation as the GenerationError that caused it.
def Serve.strict(service: Service) -> Result<&2, &2, GenerationError, Service>:
  match service:
    case Operating{origin, outgoing, received}:
      Done{Operating{origin, outgoing, received}}
    case Untraced{error, received}:
      Fail{error}

# Give a service its own operation for a received message, from a caller's
# source (see the section's introduction). Laws: continue_usable,
# restart_usable, start_unusable and restart_keeps_nothing.
def Context.continue_or_start_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S,
  +extraction: Extraction, reception: Reception, sampling: Sampling, +policy: FailurePolicy) ->
  IO(S & FailurePolicy.result(policy, Service)):
  IO.bind(S & Service, S & FailurePolicy.result(policy, Service),
    Serve.operation(~S, ~read, source, extraction, reception, sampling),
    done => IO.pure(S & FailurePolicy.result(policy, Service), Policy.apply.done(S, policy, Service, Serve.strict,
      done)))

# Sending
# =======
#
# Context.send_with gives one message that the service sends the context of
# a new operation: a child of the service's operation, generated anew for
# every message, so that each request of a fan-out is an operation of its
# own (spec #1, "each distinct outgoing operation obtains its own child
# before injection"). When the service has no operation, or when the child
# cannot be generated, no new operation is reported: the message forwards the
# received pair unchanged if it can be sent whole, and carries no context
# fields otherwise (spec #1, "It may forward only an entirely accepted
# original pair that can be sent intact within bounds; otherwise clear
# outgoing context fields").

# Why a message without a new operation does not forward a received pair:
#   NothingKept{}          the service keeps no received context: its
#                          operation is, or was to be, a root, a restart or
#                          a child of a base
#   ForwardFailed{error}   Context.forward refused the received context with
#                          `error`
type Unforwarded is Data:
  NothingKept{}
  ForwardFailed{error: ForwardError}

# The context fields of one message and how they came about:
#   Fresh{operation, injection}      a new operation, injected with the
#                                    service's state
#   Forwarded{carrier, error}        no operation could be generated (`error`);
#                                    the received pair is forwarded unchanged
#   NoContext{carrier, error,        no operation could be generated, and no
#     reason}                        pair was forwarded (`reason`): the context
#                                    fields are cleared
type Sent is Data:
  Fresh{operation: LocalContext, injection: Injection}
  Forwarded{carrier: List<&2, Header>, error: GenerationError}
  NoContext{carrier: List<&2, Header>, error: GenerationError, reason: Unforwarded}

# The fallback when a forwarding of the received pair was tried.
def Send.forwarded(result: Result<&2, &2, ForwardError, List<&2, Header>>, error: GenerationError,
  carrier: List<&2, Header>) -> Sent:
  match result:
    case Done{forwarded}:
      Forwarded{forwarded, error}
    case Fail{reason}:
      NoContext{Context.clear(carrier), error, ForwardFailed{reason}}

# The fields a message carries when no operation could be generated: the
# received pair forwarded unchanged if it can be, and no context fields
# otherwise.
def Send.fallback(+limits: Limits, received: Maybe<&2, IncomingContext>, error: GenerationError,
  +carrier: List<&2, Header>) -> Sent:
  match received:
    case None{}:
      NoContext{Context.clear(carrier), error, NothingKept{}}
    case Some{incoming}:
      Send.forwarded(Context.forward(limits, incoming, carrier), error, carrier)

# The message that a generated child gives: the child injected with the
# service's state, or the fallback.
def Send.of(+limits: Limits, +outgoing: OutgoingContext, received: Maybe<&2, IncomingContext>,
  +carrier: List<&2, Header>, result: Result<&2, &2, GenerationError, LocalContext>) -> Sent:
  match result:
    case Fail{error}:
      Send.fallback(limits, received, error, carrier)
    case Done{+operation}:
      Fresh{operation, Context.inject(limits, OutgoingContext.with_state(operation, OutgoingContext.state(outgoing)),
        carrier)}

# A message's operation as Context.send_with decides it before it reads any
# word, with the limits and the carrier to send it with:
#   SendChild{generation, limits, outgoing, received, carrier}
#     a child of the service's operation, injected with the service's state
#   SendFallback{error, limits, received, carrier}
#     no operation, for a service without one: the fallback, reading no word
# A host that feeds a generation one word at a time drives
# SendPlan.generation and hands the result to SendPlan.sent (law
# hosted_send).
type SendPlan is Data:
  SendChild{generation: Generation, limits: Limits, outgoing: OutgoingContext,
    received: Maybe<&2, IncomingContext>, carrier: List<&2, Header>}
  SendFallback{error: GenerationError, limits: Limits, received: Maybe<&2, IncomingContext>,
    carrier: List<&2, Header>}

# The plan of one message that the service sends (see SendPlan).
def SendPlan.new(limits: Limits, service: Service, sampling: Sampling, carrier: List<&2, Header>) -> SendPlan:
  match service:
    case Operating{origin, +outgoing, received}:
      SendChild{Generation.child(LocalParent{OutgoingContext.context(outgoing)}, sampling), limits, outgoing, received,
        carrier}
    case Untraced{error, received}:
      SendFallback{error, limits, received, carrier}

# The generation that the plan drives. A service without an operation has
# none to drive: its generation has already failed with the service's
# error, so that a host reads no word.
def SendPlan.generation(plan: SendPlan) -> Generation:
  match plan:
    case SendChild{generation, limits, outgoing, received, carrier}:
      generation
    case SendFallback{error, limits, received, carrier}:
      Generation{0n, Failed{error}}

# The message that the result of the plan's generation gives, before the
# policy applies. The fallback of a service without an operation does not
# depend on it.
def SendPlan.sent(plan: SendPlan, result: Result<&2, &2, GenerationError, LocalContext>) -> Sent:
  match plan:
    case SendChild{generation, limits, outgoing, received, carrier}:
      Send.of(limits, outgoing, received, carrier, result)
    case SendFallback{error, limits, received, carrier}:
      Send.fallback(limits, received, error, carrier)

# The source's final state with the message that the plan gives.
def Send.finish(-S: Type, plan: SendPlan, done: S & Result<&2, &2, GenerationError, LocalContext>) -> S & Sent:
  (source, result) = done
  (source, SendPlan.sent(plan, result))

# Drive the plan's generation from a caller's source.
def Send.run(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S, +plan: SendPlan) ->
  IO(S & Sent):
  IO.bind(S & Result<&2, &2, GenerationError, LocalContext>, S & Sent,
    Generation.run_with(~S, ~read, source, SendPlan.generation(plan)),
    done => IO.pure(S & Sent, Send.finish(S, plan, done)))

# A message without a new operation as the GenerationError that caused it.
def Send.strict(sent: Sent) -> Result<&2, &2, GenerationError, Sent>:
  match sent:
    case Fresh{operation, injection}:
      Done{Fresh{operation, injection}}
    case Forwarded{carrier, error}:
      Fail{error}
    case NoContext{carrier, error, reason}:
      Fail{error}

# Give one message that the service sends the context of a new operation,
# from a caller's source (see the section's introduction). `carrier` is the
# message's own fields; its old context fields are replaced in every case.
# Laws: send_operating, send_untraced and send_reports_generated.
def Context.send_with(~S: Type, ~read: S -> IO(S & Result<&1, &1, U32 & String, U32>), source: S, +limits: Limits,
  service: Service, sampling: Sampling, +policy: FailurePolicy, +carrier: List<&2, Header>) ->
  IO(S & FailurePolicy.result(policy, Sent)):
  IO.bind(S & Sent, S & FailurePolicy.result(policy, Sent),
    Send.run(~S, ~read, source, SendPlan.new(limits, service, sampling, carrier)),
    done => IO.pure(S & FailurePolicy.result(policy, Sent), Policy.apply.done(S, policy, Sent, Send.strict, done)))

# The name of an origin.
def Origin.show(origin: Origin) -> String:
  match origin:
    case Continued{}:
      "Continued"
    case Started{}:
      "Started"
    case Restarted{}:
      "Restarted"

# How the service's operation came about; None{} without an operation.
def Service.origin(service: Service) -> Maybe<&2, Origin>:
  match service:
    case Operating{origin, outgoing, received}:
      Some{origin}
    case Untraced{error, received}:
      None{}

# The service's operation with the state it sends; None{} without one.
def Service.outgoing(service: Service) -> Maybe<&2, OutgoingContext>:
  match service:
    case Operating{origin, outgoing, received}:
      Some{outgoing}
    case Untraced{error, received}:
      None{}

# Why the service has no operation; None{} with one.
def Service.error(service: Service) -> Maybe<&2, GenerationError>:
  match service:
    case Operating{origin, outgoing, received}:
      None{}
    case Untraced{error, received}:
      Some{error}

# Add or update an entry of the state that the service's operation sends,
# such as this participant's own (see OutgoingContext.set). A service
# without an operation is unchanged: it sends no state of its own.
def Service.set(service: Service, key: StateKey, value: StateValue) -> Service:
  match service:
    case Operating{origin, outgoing, received}:
      Operating{origin, OutgoingContext.set(outgoing, key, value), received}
    case Untraced{error, received}:
      Untraced{error, received}

# Delete an entry of the state that the service's operation sends (see
# OutgoingContext.remove). A service without an operation is unchanged.
def Service.remove(service: Service, key: StateKey) -> Service:
  match service:
    case Operating{origin, outgoing, received}:
      Operating{origin, OutgoingContext.remove(outgoing, key), received}
    case Untraced{error, received}:
      Untraced{error, received}

# The name of a service's origin, or Untraced with its error. It includes no
# received value.
def Service.show(service: Service) -> String:
  match service:
    case Operating{origin, outgoing, received}:
      Origin.show(origin)
    case Untraced{error, received}:
      "Untraced " ++ GenerationError.show(error)

# Why no pair was forwarded: NothingKept, or the ForwardError's name.
def Unforwarded.show(reason: Unforwarded) -> String:
  match reason:
    case NothingKept{}:
      "NothingKept"
    case ForwardFailed{error}:
      ForwardError.show(error)

# The fields to send with the message, in every case.
def Sent.carrier(sent: Sent) -> List<&2, Header>:
  match sent:
    case Fresh{operation, injection}:
      Injection.carrier(injection)
    case Forwarded{carrier, error}:
      carrier
    case NoContext{carrier, error, reason}:
      carrier

# The new operation that the message carries; None{} for a fallback.
def Sent.operation(sent: Sent) -> Maybe<&2, LocalContext>:
  match sent:
    case Fresh{operation, injection}:
      Some{operation}
    case Forwarded{carrier, error}:
      None{}
    case NoContext{carrier, error, reason}:
      None{}

# Why no operation could be generated; None{} for a new operation.
def Sent.error(sent: Sent) -> Maybe<&2, GenerationError>:
  match sent:
    case Fresh{operation, injection}:
      None{}
    case Forwarded{carrier, error}:
      Some{error}
    case NoContext{carrier, error, reason}:
      Some{error}

# The keys that truncating the service's state to the output budget dropped
# from a new operation's message (see Injection.dropped); none for a
# fallback, which sends no state of its own.
def Sent.dropped(sent: Sent) -> List<&2, StateKey>:
  match sent:
    case Fresh{operation, injection}:
      Injection.dropped(injection)
    case Forwarded{carrier, error}:
      Nil{}
    case NoContext{carrier, error, reason}:
      Nil{}

# The name of a new operation's message, saying whether its state was
# truncated.
def Send.fresh(dropped: List<&2, StateKey>) -> String:
  match dropped:
    case Nil{}:
      "Fresh"
    case Con{key, rest}:
      "Fresh, truncated"

# The name of a message's context: Fresh, saying whether its state was
# truncated, or for a fallback why no operation was generated and, without a
# forwarded pair, why none was forwarded. It includes no received value.
def Sent.show(sent: Sent) -> String:
  match sent:
    case Fresh{operation, injection}:
      Send.fresh(Injection.dropped(injection))
    case Forwarded{carrier, error}:
      "Forwarded after " ++ GenerationError.show(error)
    case NoContext{carrier, error, reason}:
      "NoContext after " ++ GenerationError.show(error) ++ ", " ++ Unforwarded.show(reason)
