# Laws of bend-trace-context
# ==========================
#
# This file is the package's statement of claims. Each `law` below is a
# property the Bend checker must prove for every value it quantifies over:
# it is not a test of a few examples. PROOF.bend proves each law with a def
# of the same name (`law roundtrip` is proved by `def Laws.roundtrip`), and
#
#   ./bend packages/trace-context/PROOF.bend --check-only
#
# prints "ALL PROOFS CHECK" only when every law in this file is proved and
# no definition PROOF.bend imports relies on `@unsafe` or foreign code.
# scripts/validate.sh runs that gate on every backend. By Bend's convention
# the project owner reviews and owns these statements; the proofs may change
# freely as long as the statements hold.
#
# Every law is documented with the same headings:
#
#   Claim        what the law says, in plain words.
#   Requirement  the rule it enforces: a section of the pinned W3C Trace
#                Context Level 2 publication (Candidate Recommendation Draft
#                of 2024-03-28), or a decision of an approved specification
#                (issue #1, and issue #41 for the building blocks of an
#                OpenTelemetry SDK) or of a ticket.
#   Why          what would go wrong for an application without it.
#   Reading      how the Bend statement expresses the claim, when the
#                notation is not obvious.
#   Scope        what the law deliberately leaves out, and where that is
#                tested instead.
#   Proof        where the proof lives.
#
# How to read a law
# -----------------
#
#   law name:                  the claim is called `name`.
#     for x: T                 "for every x of type T". A law holds for every
#                              combination of its `for` lines at once.
#     for h: {a == b : T}      a hypothesis: the claim only covers the values
#                              for which a equals b. Typical hypotheses say
#                              that an operation succeeded
#                              (`{parse(text) == Done{value} : ...}`) or that
#                              a check holds
#                              (`{Nat.is_le(a, b) == True{} : Bool}`).
#     {a == b : T}             the conclusion: a and b are the same value of
#                              type T. `{a != b : T}` says they differ.
#     P & Q                    both P and Q hold.
#
#   `+x` and `-x` are resource annotations: `+x` may be used several times
#   and `-x` exists only for the checker. They never change what a law means.
#
# Values that appear in the statements:
#
#   Done{v}, Fail{e}           the success and the failure of a Result.
#   Some{v}, None{}            a present and an absent optional value (Maybe).
#   True{}, False{}            booleans. Checks such as Nat.is_le(a, b)
#                              ("a <= b") or String.eq(a, b) return a Bool.
#   0n, 32n, 1n+n              natural numbers (Nat); `1n+n` is n + 1.
#   "text", 'c', a ++ b        strings, characters and string concatenation.
#   Con{x, xs}, Nil{}          the list with first element x and rest xs, and
#                              the empty list.
#   List.append(&2, T, a, b)   the list a followed by b. `&2` and the element
#                              type T are arguments Bend requires; they carry
#                              no meaning here.
#   Trace.name                 a definition of the package, from
#                              trace_context.bend.
#
# Definitions made in this file with `def` (for example `emitted_flags`,
# `keys_distinct` or `missing`) are independent specifications used to state
# the laws. They are deliberately not taken from the package, so each law
# compares the package with a second, simpler description of the rule.
#
# Contents
# --------
#
#    1. Strict v00 codec               formatted_length, roundtrip, inverse
#    2. Supplied identifiers           trace_id_parse ... assert_random
#    3. Local contexts and flags       from_ids ... received_trace_flags
#    4. Children and restarts          sampling ... restart_accepts
#    5. Identifiers from source words  trace_words ... words_unasserted
#    6. Generation from a source       feed_failure ... generation_drive,
#                                      trace_id_failure ... restart_composed
#    7. Limits                         limits_bounds ... default_limits
#    8. Tracestate keys and values     key_parse ... value_separators
#    9. Tracestate states and lookups  state_valid, get_entry, get_absent
#   10. Tracestate parsing             state_roundtrip ... first_wins
#   11. Tracestate updates and         set_entries ... emit_accepted
#       emission
#   12. Extraction                     extract_absent ... read_within_budgets
#   13. Injection and forwarding       clear_carrier ... forward_idempotent
#   14. Continuing or starting, and    continue_usable ... hosted_send
#       sending
#   15. Native HTTP headers            http_carrier ... http_send
#   16. Identifiers as bytes           trace_bytes ... zero_bytes

import Base
import ./trace_context.bend as Trace
import ./native_http.bend as NativeHttp
import ./src/digits.bend as Digits

# 1. Strict v00 codec
# ===================
#
# TraceParentV00 is the strict wire codec for version 00 of the traceparent
# field (W3C Level 2, section 3.2.2): "00-", 32 lowercase hexadecimal digits
# (the trace ID), "-", 16 lowercase hexadecimal digits (the parent ID), "-"
# and two hexadecimal digits (the flags). Its type makes invalid values
# impossible to build: each ID is a digit sequence whose length is part of its
# type and which carries a proof that it is not all zero. These laws say that
# the codec is exact: nothing is lost or invented between the text and the
# value, in either direction.

# LAW formatted_length
#   Claim: formatting any strict v00 value produces exactly 55 characters.
#   Requirement: W3C Level 2, section 3.2.2: version 00 has fixed field widths,
#     2 + 1 + 32 + 1 + 16 + 1 + 2 = 55 characters. Spec #1 keeps the strict
#     codec's fixed-length guarantee.
#   Why: a receiver treats a version 00 header of any other length as invalid
#     and drops the trace. 55 is also the smallest traceparent input budget a
#     configuration may choose (see limits_bounds).
#   Reading: `for context: Trace.TraceParentV00` ranges over every value of
#     the type: every nonzero trace ID, every nonzero parent ID and all 256
#     flag bytes.
#   Proof: Laws.formatted_length, via proofs/context.bend, from the encoded
#     length of each digit sequence (proofs/digits.bend) and of joined strings
#     (proofs/strings.bend).
law formatted_length:
  for context: Trace.TraceParentV00
  {String.length(Trace.TraceParentV00.format(context)) == 55n : Nat}

# LAW roundtrip
#   Claim: parsing the text of any strict v00 value gives back exactly that
#     value: the same IDs, the same proofs that they are nonzero and every one
#     of the eight flag bits.
#   Requirement: spec #1, "Preserve the existing strict-codec round trip" and
#     "The strict codec accepts exactly v00 and preserves its entire flag
#     byte".
#   Why: a codec that dropped or changed a bit, a reserved flag for example,
#     would silently alter the context it relays, and a proxy could no longer
#     pass a header on intact.
#   Reading: `Done{context}` is the parser's success carrying the original
#     value. The equation compares whole values, so a difference in any field
#     would falsify it.
#   Proof: Laws.roundtrip, via proofs/context.bend.
law roundtrip:
  for context: Trace.TraceParentV00
  {Trace.TraceParentV00.parse(Trace.TraceParentV00.format(context)) ==
    Done{context} : Result<&2, &2, Trace.Error, Trace.TraceParentV00>}

# LAW inverse
#   Claim: whenever the strict parser accepts a text, formatting the result
#     reproduces that text character for character.
#   Requirement: spec #1, "complete the inverse law for every accepted
#     strict-v00 text" (proved in #5).
#   Why: with `roundtrip`, it makes parse and format exact inverses. Without
#     it, the parser could accept variants, such as an uppercase digit or a
#     suffix, that format differently, and the text received and the text sent
#     could disagree.
#   Reading: `for text: String` ranges over every string, valid or not. The
#     hypothesis `accepted` restricts the claim to the texts the parser
#     accepts; `context` is the value it produced.
#   Proof: Laws.inverse, via the parser views of proofs/inverse.bend.
law inverse:
  for text: String
  for context: Trace.TraceParentV00
  for accepted: {Trace.TraceParentV00.parse(text) == Done{context} :
    Result<&2, &2, Trace.Error, Trace.TraceParentV00>}
  {Trace.TraceParentV00.format(context) == text : String}

# 2. Supplied identifiers
# =======================
#
# Applications that already have IDs, from another tracing system for example,
# turn their text into TraceId and SpanId with TraceId.parse and SpanId.parse.
# A TraceId also records whether its random origin is asserted: that decides
# the random-trace-id flag (W3C Level 2, section 3.2.2.5.2) emitted with it.

# LAW trace_id_parse
#   Claim: an accepted trace ID is exactly the text accepted, and parsing
#     never asserts that the ID was generated randomly.
#   Requirement: spec #1, validated constructors for supplied IDs (user
#     stories 5 and 6), and "Supplied trace IDs default to no randomness
#     assertion; an explicit caller assertion is a responsibility, not a
#     theorem about external entropy".
#   Why: the ID must name the same trace the other system knows. The
#     random-trace-id flag tells receivers they may rely on the ID's
#     randomness, for sampling decisions for example, so it must never be set
#     just because an ID was parsed.
#   Reading: the conclusion `A & B` states both facts; `is_random(id) ==
#     False{}` is the absence of the assertion.
#   Proof: Laws.trace_id_parse, via proofs/ids.bend.
law trace_id_parse:
  for text: String
  for id: Trace.TraceId
  for accepted: {Trace.TraceId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.TraceId>}
  {Trace.TraceId.to_string(id) == text : String} & {Trace.TraceId.is_random(id) == False{} : Bool}

# LAW span_id_parse
#   Claim: an accepted span ID is exactly the text accepted.
#   Requirement: spec #1, validated constructors for supplied IDs.
#   Why: a span ID identifies an operation; changing it would link the next
#     operation to the wrong parent.
#   Proof: Laws.span_id_parse, via proofs/ids.bend.
law span_id_parse:
  for text: String
  for id: Trace.SpanId
  for accepted: {Trace.SpanId.parse(text) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == text : String}

# LAW trace_id_accepts
#   Claim: the text of every trace ID is accepted again by TraceId.parse.
#   Requirement: spec #1, validated constructors. With trace_id_parse, the
#     constructor accepts exactly the canonical texts of trace IDs.
#   Why: an ID the package produced, generated or converted from words, must be
#     accepted when it comes back, for example from another service.
#   Scope: the law claims acceptance (`Result.is_done(...) == True{}`), not
#     equality: parsing makes no randomness assertion, so a random ID comes
#     back without it. span_id_roundtrip states full equality for span IDs,
#     which carry no assertion.
#   Proof: Laws.trace_id_accepts, via proofs/ids.bend.
law trace_id_accepts:
  for id: Trace.TraceId
  {Result.is_done(&2, &2, Trace.Error, Trace.TraceId, Trace.TraceId.parse(Trace.TraceId.to_string(id))) ==
    True{} : Bool}

# LAW span_id_roundtrip
#   Claim: parsing the text of any span ID gives back that span ID.
#   Requirement: spec #1, validated constructors; together with span_id_parse,
#     SpanId.parse accepts exactly the texts of span IDs.
#   Why: a span ID read from a received header can be compared, stored and
#     sent again without changing.
#   Proof: Laws.span_id_roundtrip, via proofs/ids.bend.
law span_id_roundtrip:
  for id: Trace.SpanId
  {Trace.SpanId.parse(Trace.SpanId.to_string(id)) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}

# LAW assert_random
#   Claim: TraceId.assert_random sets the randomness assertion and leaves the
#     identifier itself unchanged.
#   Requirement: spec #1, "an explicit caller assertion is a responsibility":
#     a caller that knows its ID is random says so explicitly.
#   Why: asserting randomness must not rename the trace; only the
#     random-trace-id flag emitted with it changes.
#   Proof: Laws.assert_random, by case analysis in PROOF.bend.
law assert_random:
  for trace_id: Trace.TraceId
  {Trace.TraceId.is_random(Trace.TraceId.assert_random(trace_id)) == True{} : Bool} &
  {Trace.TraceId.to_string(Trace.TraceId.assert_random(trace_id)) == Trace.TraceId.to_string(trace_id) : String}

# 3. Local contexts and flags
# ===========================
#
# A LocalContext identifies an operation of this participant, the one that
# sends a header. A RemoteContext identifies the sender's operation, read
# from a received header or built from its parts (spec #41). They are
# separate types, so a received context cannot be sent as if it were the
# participant's own operation (spec #1, "Distinguish remote context, local
# context and the accepted original header pair"). The flags of W3C Level 2,
# section 3.2.2.5, are bit 0 (sampled) and bit 1 (random-trace-id); the other
# six bits are reserved. Both context types give their known flags as a
# number too, for an exporter (spec #41, "Trace flags"): the last three laws
# state it.

# LAW from_ids
#   Claim: Context.from_ids keeps exactly the trace ID, the span ID and the
#     sampled indication it is given.
#   Requirement: spec #1, "Participant injection accepts a local context
#     produced by root, child or explicit construction for an operation the
#     caller owns".
#   Why: integrations that manage their own IDs need a constructor that does
#     not rewrite them.
#   Proof: Laws.from_ids, by computation.
law from_ids:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  {Trace.LocalContext.trace_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == trace_id : Trace.TraceId} &
  {Trace.LocalContext.span_id(Trace.Context.from_ids(trace_id, span_id, sampled)) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(Trace.Context.from_ids(trace_id, span_id, sampled)) == sampled : Bool}

# LAW root
#   Claim: a root built from supplied IDs is the explicit construction of those
#     IDs with the sampled indication that it is given. With False, it is not
#     sampled, sampled 0, as Context.continue_or_start_with starts a root by
#     default.
#   Requirement: spec #1, "New roots default to sampled 0" (user story 10),
#     which Context.continue_or_start_with applies (start_unusable); spec
#     #41, "Sampling decision when starting a trace": Context.root_from_ids
#     takes the sampled indication explicitly, and no low-level piece applies
#     a default of its own (user story 27).
#   Why: starting a trace, with generated or supplied IDs, must not by itself
#     ask downstream services to record it, and must ask them when the
#     application decides so: sampling stays an explicit decision of the
#     application.
#   Proof: Laws.root, by computation.
law root:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  {Trace.Context.root_from_ids(trace_id, span_id, sampled) == Trace.Context.from_ids(trace_id, span_id, sampled) :
    Trace.LocalContext}

# LAW remote_from_ids
#   Claim: RemoteContext.from_ids keeps exactly the trace ID, the span ID and
#     the sampled indication it is given, so the context asserts
#     random-trace-id exactly when its trace ID does.
#   Requirement: spec #41, "Contexts from parts": RemoteContext.from_ids
#     builds a remote context; it is total, and its randomness comes from the
#     trace ID (user story 18).
#   Why: an OpenTelemetry SDK builds the remote span contexts of links and of
#     propagators of other formats from their parts. A constructor that
#     rewrote them would name another operation than the sender's, and one
#     that set random-trace-id by itself would assert what nobody asserted.
#   Reading: the last conjunct follows from the first, and states the
#     randomness claim on its own.
#   Scope: the result is a RemoteContext, so it still cannot be sent as this
#     participant's operation (tests/reject/remote_as_local.bend).
#   Proof: Laws.remote_from_ids, by computation.
law remote_from_ids:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  {Trace.RemoteContext.trace_id(Trace.RemoteContext.from_ids(trace_id, span_id, sampled)) == trace_id :
    Trace.TraceId} &
  {Trace.RemoteContext.span_id(Trace.RemoteContext.from_ids(trace_id, span_id, sampled)) == span_id :
    Trace.SpanId} &
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_ids(trace_id, span_id, sampled)) == sampled : Bool} &
  {Trace.TraceId.is_random(Trace.RemoteContext.trace_id(Trace.RemoteContext.from_ids(trace_id, span_id, sampled))) ==
    Trace.TraceId.is_random(trace_id) : Bool}

# The flag byte a participant emits for a sampled indication and a randomness
# assertion: "00", "01" (sampled), "02" (random) or "03" (both). It is written
# out literally, so emitted_traceparent compares the package with the four
# permitted strings rather than with the package's own encoding.
def emitted_flags(sampled: Bool, random: Bool) -> String:
  match sampled random:
    case False{} False{}:
      "00"
    case True{} False{}:
      "01"
    case False{} True{}:
      "02"
    case True{} True{}:
      "03"

# LAW emitted_traceparent
#   Claim: every local context is sent as version 00 with its own trace ID and
#     span ID, and with flags 00, 01, 02 or 03: sampled in bit 0,
#     random-trace-id in bit 1 and every reserved bit zero.
#   Requirement: W3C Level 2, section 3.2.2.5.3: vendors set unknown flags to
#     zero on outgoing requests. Spec #1, "Participating emission uses 00 and
#     known flag mask 03".
#   Why: a reserved bit copied from a received header would claim a meaning
#     this package does not implement, and a future version would claim a
#     format it does not produce.
#   Reading: the right side builds the expected text piece by piece with `++`;
#     emitted_flags, above, gives the flag byte literally.
#   Proof: Laws.emitted_traceparent, by case analysis on both flags.
law emitted_traceparent:
  for context: Trace.LocalContext
  {Trace.TraceParentV00.format(Trace.LocalContext.to_traceparent(context)) ==
    "00-" ++ Trace.TraceId.to_string(Trace.LocalContext.trace_id(context)) ++ "-" ++
    Trace.SpanId.to_string(Trace.LocalContext.span_id(context)) ++ "-" ++
    emitted_flags(Trace.LocalContext.is_sampled(context),
      Trace.TraceId.is_random(Trace.LocalContext.trace_id(context))) : String}

# LAW emitted_projection
#   Claim: a receiver that reads what a local context emits recovers the same
#     trace ID, with its randomness assertion, the same span ID, as the parent
#     ID, and the same sampled indication.
#   Requirement: spec #1, "Extraction after participant injection recovers the
#     normalized remotely observable projection of the local context,
#     including emitted flags".
#   Why: this is the core promise of propagation: the next service continues
#     exactly the operation that sent the request.
#   Scope: stated for the traceparent value, through the codec and the context
#     conversions. inject_extracted (section 13) states it over the whole
#     carrier that injection writes and extraction (section 12) reads.
#   Proof: Laws.emitted_projection, by case analysis on both flags.
law emitted_projection:
  for context: Trace.LocalContext
  {Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.trace_id(context) : Trace.TraceId} &
  {Trace.RemoteContext.span_id(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.span_id(context) : Trace.SpanId} &
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(context))) ==
    Trace.LocalContext.is_sampled(context) : Bool}

# LAW received_flags
#   Claim: a context received from a strict v00 value keeps the sender's
#     sampled bit and random-trace-id bit, exactly as the codec reads them.
#   Requirement: W3C Level 2, sections 3.2.2.5.1 and 3.2.2.5.2. Spec #1,
#     "Preserve random-trace-id while preserving trace ID" and "Children
#     inherit sampled unless the caller explicitly overrides it".
#   Why: continuing a trace must not lose the sender's sampling decision or
#     its randomness assertion.
#   Scope: reserved bits are deliberately not part of a remote context. The
#     corpus checks both flag readers on all 256 flag bytes.
#   Proof: Laws.received_flags, by case analysis on the flag byte.
law received_flags:
  for traceparent: Trace.TraceParentV00
  {Trace.RemoteContext.is_sampled(Trace.RemoteContext.from_traceparent(traceparent)) ==
    Trace.TraceParentV00.is_sampled(traceparent) : Bool} &
  {Trace.TraceId.is_random(Trace.RemoteContext.trace_id(Trace.RemoteContext.from_traceparent(traceparent))) ==
    Trace.TraceParentV00.is_random(traceparent) : Bool}

# The trace flags of a sampled indication and a randomness assertion, as a
# number: 0, 1 (sampled), 2 (random) or 3 (both), the values of the flag
# bytes "00" to "03" that emitted_flags gives. It is written out literally,
# so the laws below compare the package's number with these four values
# rather than with the package's own bit operations.
def known_flags(sampled: Bool, random: Bool) -> U32:
  match sampled random:
    case False{} False{}:
      0
    case True{} False{}:
      1
    case False{} True{}:
      2
    case True{} True{}:
      3

# LAW local_flags
#   Claim: a local context's trace flags are its known flags as a number from
#     0 to 3, its sampled indication in bit 0 and its trace ID's randomness
#     assertion in bit 1, and they are the flags of the traceparent that it
#     emits.
#   Requirement: spec #41, "Trace flags": LocalContext.flags gives "the known
#     trace flags as a number from 0 to 3: bit 0 is sampled, and bit 1 is
#     random-trace-id, from the trace ID's assertion", and "A local context's
#     value equals the flags of the traceparent it emits" (user stories 15
#     and 16).
#   Why: an exporter writes these flags into the span that it exports, into
#     OTLP's Span.flags field for example, while the traceparent carries the
#     same operation to the next service. If they differed, the exported span
#     and the propagated context would disagree.
#   Reading: known_flags, above, gives the number of each pair of flags
#     literally. The second equation reads the two known flags back from the
#     emitted traceparent with the codec's readers. Its reserved bits are zero
#     (emitted_traceparent), so the number is the value of its whole flag
#     byte.
#   Proof: Laws.local_flags, by case analysis on both flags.
law local_flags:
  for context: Trace.LocalContext
  {Trace.LocalContext.flags(context) ==
    known_flags(Trace.LocalContext.is_sampled(context), Trace.TraceId.is_random(Trace.LocalContext.trace_id(context))) :
    U32} &
  {Trace.LocalContext.flags(context) ==
    known_flags(Trace.TraceParentV00.is_sampled(Trace.LocalContext.to_traceparent(context)),
      Trace.TraceParentV00.is_random(Trace.LocalContext.to_traceparent(context))) : U32}

# LAW remote_flags
#   Claim: a remote context's trace flags are the known flags that it keeps,
#     as a number from 0 to 3: its sampled indication in bit 0 and its trace
#     ID's randomness assertion in bit 1, however the context was made.
#   Requirement: spec #41, "Trace flags", as for local_flags: a remote
#     context's value is the known flags that it was received or built with
#     (user stories 15 and 17).
#   Why: an SDK exports a remote parent as it exports a local operation. The
#     Booleans stay the canonical form, and the number says no more than they
#     do.
#   Scope: received_trace_flags states the value of a received context in
#     terms of the value received.
#   Proof: Laws.remote_flags, by case analysis on both flags.
law remote_flags:
  for context: Trace.RemoteContext
  {Trace.RemoteContext.flags(context) ==
    known_flags(Trace.RemoteContext.is_sampled(context), Trace.TraceId.is_random(Trace.RemoteContext.trace_id(context))) :
    U32}

# LAW received_trace_flags
#   Claim: the trace flags of a context received from a strict v00 value are
#     that value's known flags: its sampled bit as bit 0 and its
#     random-trace-id bit as bit 1. Its reserved bits are not among them.
#   Requirement: spec #41, "Trace flags" (user story 17); W3C Level 2,
#     sections 3.2.2.5.1 and 3.2.2.5.2.
#   Why: an SDK exports a remote parent with the flags that its sender sent,
#     and never passes on a reserved bit, whose meaning the package does not
#     know, as a known flag.
#   Scope: the corpus checks the codec's two flag readers on all 256 flag
#     bytes (see received_flags).
#   Proof: Laws.received_trace_flags, by remote_flags once the flag byte is
#     split into its two digits.
law received_trace_flags:
  for traceparent: Trace.TraceParentV00
  {Trace.RemoteContext.flags(Trace.RemoteContext.from_traceparent(traceparent)) ==
    known_flags(Trace.TraceParentV00.is_sampled(traceparent), Trace.TraceParentV00.is_random(traceparent)) : U32}

# 4. Children and restarts
# ========================
#
# A child context continues a trace with a new operation: it keeps the
# parent's trace ID and uses its own span ID (W3C Level 2, section 3.4,
# "Update parent-id"). A restart deliberately starts a new trace at a boundary
# where a received context is not continued. These laws cover the operations
# on supplied IDs; section 6 states the same rules for generated IDs.

# LAW sampling
#   Claim: InheritSampled{} gives the parent's sampled indication and
#     SetSampled{sampled} gives `sampled`.
#   Requirement: spec #1, "Children inherit sampled unless the caller
#     explicitly overrides it while creating a new operation" (user stories 11
#     and 12).
#   Why: by default a child keeps the upstream sampling decision, and the
#     application can still apply its own recording policy.
#   Proof: Laws.sampling, by computation.
law sampling:
  for inherited: Bool
  for sampled: Bool
  {Trace.Sampling.resolve(Trace.InheritSampled{}, inherited) == inherited : Bool} &
  {Trace.Sampling.resolve(Trace.SetSampled{sampled}, inherited) == sampled : Bool}

# LAW child
#   Claim: when Context.child_from_id succeeds, the child keeps the parent's
#     trace ID with its randomness assertion, uses the supplied span ID, takes
#     its sampled indication from Sampling.resolve, and its span ID differs
#     from the parent's.
#   Requirement: spec #1, "Successful child creation preserves trace ID/random
#     and applies sampled inheritance or explicit override while enforcing a
#     distinct nonzero operation ID" (user stories 4, 9 and 13).
#   Why: a child that changed the trace ID would start an unrelated trace; a
#     child reusing the parent's span ID would make two operations
#     indistinguishable; and creating a child must never relabel a received
#     trace ID as random.
#   Reading: the hypothesis `accepted` restricts the claim to successful
#     creations. `{a != b : String}` says the two span ID texts differ. Nonzero
#     is guaranteed by the SpanId type itself.
#   Proof: Laws.child, via proofs/lifecycle.bend.
law child:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for created: Trace.LocalContext
  for accepted: {Trace.Context.child_from_id(parent, span_id, sampling) == Done{created} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.span_id(created) == span_id : Trace.SpanId} &
  {Trace.LocalContext.is_sampled(created) ==
    Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# LAW child_reuse
#   Claim: a child whose span ID equals its parent's is refused with
#     ReusedSpanId.
#   Requirement: spec #1, "child creation also rejects equality with the
#     previous operation ID. Supplied IDs pass the same validity checks,
#     including child-ID reuse rejection".
#   Why: the new operation needs its own identity (see `child`).
#   Proof: Laws.child_reuse, via proofs/lifecycle.bend.
law child_reuse:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for reused: {Trace.SpanId.to_string(span_id) == Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) == Fail{Trace.ReusedSpanId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# LAW child_accepts
#   Claim: every other span ID is accepted, and the child is exactly the
#     explicit construction of the parent's trace ID, that span ID and the
#     resolved sampled indication.
#   Requirement: as for `child`; this law rules out refusals for any other
#     reason.
#   Why: with child_reuse it makes reuse the only reason a child can be
#     refused, so callers can rely on creation succeeding otherwise.
#   Proof: Laws.child_accepts, via proofs/lifecycle.bend.
law child_accepts:
  for parent: Trace.Parent
  for span_id: Trace.SpanId
  for sampling: Trace.Sampling
  for distinct: {Trace.SpanId.to_string(span_id) != Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}
  {Trace.Context.child_from_id(parent, span_id, sampling) ==
    Done{Trace.Context.from_ids(Trace.Parent.trace_id(parent), span_id,
      Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)))} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# LAW restart
#   Claim: a successful restart is the root of its supplied IDs with the
#     sampled indication that it is given (random as asserted by the new trace
#     ID), and its trace ID differs from the received one. With False, the root
#     defaults apply, sampled 0 included.
#   Requirement: spec #1, "Explicit restart creates a new trace identity,
#     discards previous tracestate and applies root defaults, including sampled
#     0" (user story 46); spec #41, "Sampling decision when starting a trace":
#     Context.restart_from_ids takes the sampled indication explicitly, and a
#     restart still takes only a remote context (user story 27).
#   Why: a restart that kept the received trace ID would be a continuation in
#     disguise.
#   Scope: discarding the previous tracestate belongs to the continue-or-start
#     operation (laws restart_usable and restart_keeps_nothing, section 14).
#   Proof: Laws.restart, via proofs/lifecycle.bend.
law restart:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  for restarted: Trace.LocalContext
  for accepted: {Trace.Context.restart_from_ids(previous, trace_id, span_id, sampled) == Done{restarted} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {restarted == Trace.Context.root_from_ids(trace_id, span_id, sampled) : Trace.LocalContext} &
  {Trace.TraceId.to_string(trace_id) != Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}

# LAW restart_reuse
#   Claim: a restart whose trace ID equals the received one is refused with
#     ReusedTraceId, whatever its randomness assertion and its sampled
#     indication.
#   Requirement: as for `restart`; the decision to refuse the received trace ID
#     was recorded on #5.
#   Why: see `restart`.
#   Proof: Laws.restart_reuse, via proofs/lifecycle.bend.
law restart_reuse:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  for reused: {Trace.TraceId.to_string(trace_id) ==
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id, sampled) == Fail{Trace.ReusedTraceId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# LAW restart_accepts
#   Claim: every other trace ID is accepted, and the restart is exactly the
#     root of the supplied IDs with the sampled indication that it is given.
#   Why: with restart_reuse it makes reuse the only reason a restart can be
#     refused.
#   Proof: Laws.restart_accepts, via proofs/lifecycle.bend.
law restart_accepts:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for sampled: Bool
  for distinct: {Trace.TraceId.to_string(trace_id) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id, sampled) ==
    Done{Trace.Context.root_from_ids(trace_id, span_id, sampled)} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# 5. Identifiers from source words
# ================================
#
# Generated IDs are built from 32-bit words read from an identifier source:
# four words make a trace ID candidate and two make a span ID candidate
# (spec #1, "Convert four U32 words into a trace ID and two into an operation
# ID, with words and digits ordered big-endian").

# LAW trace_words
#   Claim: a trace ID converted from four words is the eight-digit hexadecimal
#     text of the first word, then of the second, the third and the fourth.
#   Requirement: spec #1, words ordered big-endian: most significant first.
#   Why: a fixed, documented word order lets another implementation, or a test
#     with a replayed source, predict exactly which ID a sequence of words
#     gives.
#   Reading: `made` says the conversion produced Some{id}; it gives None{} for
#     an all-zero candidate.
#   Proof: Laws.trace_words, via proofs/conversion.bend.
law trace_words:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.to_string(id) ==
    Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) ++ Trace.U32.to_hex(third) ++ Trace.U32.to_hex(fourth) : String}

# LAW span_words
#   Claim: a span ID converted from two words is the hexadecimal text of the
#     first word followed by that of the second.
#   Requirement and Why: as for trace_words.
#   Proof: Laws.span_words, via proofs/conversion.bend.
law span_words:
  for first: U32
  for second: U32
  for id: Trace.SpanId
  for made: {Trace.SpanId.from_words(first, second) == Some{id} : Maybe<&2, Trace.SpanId>}
  {Trace.SpanId.to_string(id) == Trace.U32.to_hex(first) ++ Trace.U32.to_hex(second) : String}

# LAW hex_injective
#   Claim: two words with the same eight-digit hexadecimal text are the same
#     word.
#   Requirement: spec #1, the conversion of words into IDs. This law shows the
#     conversion loses no information.
#   Why: if two different words gave the same digits, the conversion would
#     waste the source's entropy and make distinct words collide.
#   Proof: Laws.hex_injective, via proofs/conversion.bend.
law hex_injective:
  for left: U32
  for right: U32
  for same: {Trace.U32.to_hex(left) == Trace.U32.to_hex(right) : String}
  {left == right : U32}

# An independent reading of hexadecimal text, used by word_hex. The value of a
# digit is its position in "0123456789abcdef", counted from `index`.
def hex_digit_value(alphabet: String, +char: Char, +index: Nat) -> Nat:
  match alphabet:
    case SNil{}:
      index
    case SCon{candidate, rest}:
      Bool.pick(Nat, Char.is_eq(char, candidate), index, hex_digit_value(rest, char, 1n+index))

# Multiplication by 16, written with doubling only.
def times16(value: Nat) -> Nat:
  Nat.double(Nat.double(Nat.double(Nat.double(value))))

# The value of a hexadecimal numeral, its first digit the most significant:
# each digit adds its value to 16 times the value of the digits before it.
def hex_numeral(text: String, value: Nat) -> Nat:
  match text:
    case SNil{}:
      value
    case SCon{char, rest}:
      hex_numeral(rest, Nat.add(hex_digit_value("0123456789abcdef", char, 0n), times16(value)))

# LAW word_hex
#   Claim: read as a base-16 numeral, the eight digits of a word are the number
#     that Base assigns to the word.
#   Requirement: spec #1, digits ordered big-endian within each word.
#   Why: trace_words and span_words fix the order of the words; this law fixes
#     the order of the digits inside each word. A converter that consistently
#     swapped two digits would pass every other law but fail this one.
#   Reading: hex_numeral, above, reads the text independently of the package;
#     U32.to_nat is Base's value of the word.
#   Proof: Laws.word_hex, via proofs/words.bend.
law word_hex:
  for word: U32
  {hex_numeral(Trace.U32.to_hex(word), 0n) == U32.to_nat(word) : Nat}

# LAW words_unasserted
#   Claim: a trace ID converted from words makes no randomness assertion.
#   Requirement: spec #1, "A trace ID generated through the package's
#     cryptographic path sets random-trace-id". Only generation, which trusts
#     its source, makes the assertion (generated_root, generated_restart).
#   Why: an application converting words it computed itself must not emit the
#     random flag by accident.
#   Proof: Laws.words_unasserted, via proofs/conversion.bend.
law words_unasserted:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  {Trace.TraceId.is_random(id) == False{} : Bool}

# 6. Generation from an identifier source
# =======================================
#
# Context.root_with, child_with and restart_with read words from a caller's
# source one at a time: they compose the generation of a trace ID and of a
# span ID alone (see "Separate generation" below). The laws describe them
# through the generation machine (Draw and Step in trace_context.bend),
# which feeds each word to the same two pieces, a trace ID draw and a span
# ID draw. Context.root, child and restart in generation.bend do the same
# with the host's cryptographic source. The laws quantify over
# every "tape": a list of word results, errors included, that a deterministic
# source replays. The rules come from spec #1, "Generation and failure
# contracts": the trace ID before the span ID, at most eight candidates per
# ID, zero rejected, a child's candidate equal to the parent's span ID
# rejected, the first source error ends generation, and there is no time or
# counter fallback. The quality of a real host source is outside every law.
# A root and a restart take the sampled indication of the context that they
# create as it is given (spec #41, "Sampling decision when starting a
# trace"), so the laws below state them for every indication; the default of
# new traces, not sampled, lives in Context.continue_or_start_with (section
# 14).

# LAW feed_failure
#   Claim: a source error ends generation at once with SourceFailure, carrying
#     the source's own code and message, whatever the machine was drawing.
#   Requirement: spec #1, "A source error at any word ends generation
#     immediately" and "no time/counter fallback is permitted".
#   Why: continuing after a failed read, or filling in a predictable word,
#     would produce IDs that are not random while claiming they are.
#   Proof: Laws.feed_failure, by computation once the draw is split.
law feed_failure:
  for code: U32
  for message: String
  for draw: Trace.Draw
  {Trace.Draw.feed(Fail{(code, message)}, draw) == Trace.Failed{Trace.SourceFailure{code, message}} : Trace.Step}

# A tape: the word results a replayed source returns, in order. Each result is
# Done{word} or Fail{(code, message)}.
def Tape() -> Type:
  List<&1, Result<&1, &1, U32 & String, U32>>

# The unread rest of a tape, with the machine's state after reading.
def TapeStep() -> Type:
  Tape() & Trace.Step

# The unread rest of a tape, with the generation's result.
def TapeOutcome() -> Type:
  Tape() & Result<&2, &2, Trace.GenerationError, Trace.LocalContext>

# The value an IO action produces when every effect in it is pure: the action
# runs with a continuation that only emits its final value.
def Observe(-A: Type, action: IO(A)) -> IO.OP<A>:
  action(A, value => Emit{value})

# `count` zero words. Four make an all-zero trace ID candidate and two an
# all-zero span ID candidate, which generation must reject.
def zeros(count: Nat) -> Tape():
  match count:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Done{0}, zeros(p)}

# LAW root_tape
#   Claim: generating a root from a tape source, with any sampled indication,
#     does exactly what the pure tape driver Draw.run does with a budget of 48
#     words: the same words are read, in order, and the unread ones are handed
#     back.
#   Requirement: spec #1, "Allow an explicit caller provider and deterministic
#     sources for tests"; the IO operation must follow the machine that the
#     other generation laws describe.
#   Why: it carries every generation law stated on the pure driver over to the
#     operation that applications call.
#   Reading: Observe runs the IO action; Emit{v} is its result.
#   Proof: Laws.root_tape, via proofs/generation.bend.
law root_tape:
  for tape: Tape()
  for sampled: Bool
  {Observe(TapeOutcome(), Trace.Context.root_with(~Tape(), ~Trace.Source.tape, tape, sampled)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.root(sampled))))} : IO.OP<TapeOutcome()>}

# LAW child_tape
#   Claim: as root_tape, for a child with a budget of 16 words.
#   Proof: Laws.child_tape, via proofs/generation.bend.
law child_tape:
  for tape: Tape()
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  {Observe(TapeOutcome(), Trace.Context.child_with(~Tape(), ~Trace.Source.tape, tape, parent, sampling)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))))} :
    IO.OP<TapeOutcome()>}

# LAW restart_tape
#   Claim: as root_tape, for a restart with a budget of 48 words, with any
#     sampled indication.
#   Proof: Laws.restart_tape, via proofs/generation.bend.
law restart_tape:
  for tape: Tape()
  for previous: Trace.RemoteContext
  for sampled: Bool
  {Observe(TapeOutcome(), Trace.Context.restart_with(~Tape(), ~Trace.Source.tape, tape, previous, sampled)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous, sampled))))} :
    IO.OP<TapeOutcome()>}

# LAW root_ends
#   Claim: for every tape and every sampled indication, a root generation has
#     finished, with a context or a failure, within 48 words.
#   Requirement: spec #1, "Allow at most eight candidates per ID": eight trace
#     ID candidates of four words and eight span ID candidates of two.
#   Why: generation always ends with an answer. The IO operation's word budget
#     is exactly this worst case, so it never gives up early either.
#   Reading: Draw.ended says the driver's step is Created or Failed.
#   Proof: Laws.root_ends, via proofs/generation.bend.
law root_ends:
  for tape: Tape()
  for +sampled: Bool
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.root(sampled)))) == True{} : Bool}

# LAW child_ends
#   Claim: for every tape, a child generation has finished within 16 words:
#     eight span ID candidates of two words.
#   Requirement and Why: as for root_ends.
#   Proof: Laws.child_ends, via proofs/generation.bend.
law child_ends:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  {Trace.Draw.ended(Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling)))) == True{} : Bool}

# LAW restart_ends
#   Claim: for every tape and every sampled indication, a restart has
#     finished within 48 words.
#   Requirement and Why: as for root_ends.
#   Proof: Laws.restart_ends, via proofs/generation.bend.
law restart_ends:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  for +sampled: Bool
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous, sampled)))) == True{} : Bool}

# LAW root_exhaustion
#   Claim: eight all-zero trace ID candidates (32 zero words) make a root fail
#     with ExhaustedTraceId, whatever its sampled indication, and the words
#     after them are not read.
#   Requirement: spec #1, "Allow at most eight candidates per ID. Reject zero",
#     and the test decision "prevention of a ninth attempt".
#   Why: a source stuck on zeros must produce a structured error instead of
#     looping or accepting an invalid ID; not reading a ninth candidate bounds
#     the work.
#   Scope: proved for all-zero candidates. Exhaustion through reused IDs is
#     tested in tests/GENERATION.bend.
#   Proof: Laws.root_exhaustion, by computation.
law root_exhaustion:
  for sampled: Bool
  for rest: Tape()
  {Trace.Draw.run(48n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest),
    Trace.Draw.root(sampled))) == (rest, Trace.Failed{Trace.ExhaustedTraceId{}}) : TapeStep()}

# LAW child_exhaustion
#   Claim: eight all-zero span ID candidates (16 zero words) make a child fail
#     with ExhaustedSpanId, and the words after them are not read.
#   Requirement, Why and Scope: as for root_exhaustion.
#   Proof: Laws.child_exhaustion, by computation.
law child_exhaustion:
  for parent: Trace.Parent
  for sampling: Trace.Sampling
  for rest: Tape()
  {Trace.Draw.run(16n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(16n), rest),
    Trace.Draw.child(parent, sampling))) == (rest, Trace.Failed{Trace.ExhaustedSpanId{}}) : TapeStep()}

# LAW generated_root
#   Claim: a root created from any tape asserts random-trace-id and has the
#     sampled indication that it was given, so it is emitted with flags 03
#     when it is sampled and 02 when it is not. With False, it is not
#     sampled and is emitted with flags 02, as the root that
#     Context.continue_or_start_with starts by default.
#   Requirement: spec #1, "a default internally generated root has flags 02,
#     despite sampled being 0", which Context.continue_or_start_with applies
#     by passing False for InheritSampled{} (start_unusable); spec #41,
#     "Sampling decision when starting a trace": root generation takes the
#     sampled indication explicitly, and no low-level piece applies a default
#     of its own (user story 25).
#   Why: receivers may rely on the random flag of IDs this package generates,
#     and a new root asks for recording exactly when its caller decides so: a
#     background job that the application traces can be sampled without
#     rebuilding its root from the IDs.
#   Reading: the flags follow from the two conclusions by
#     emitted_traceparent (section 3), whose flag byte is
#     emitted_flags(is_sampled, is_random) of the root: with random-trace-id
#     asserted, emitted_flags(sampled, True{}), which is 02 for False and 03
#     for True.
#   Scope: the source is trusted to be random; no law speaks about the quality
#     of a real source.
#   Proof: Laws.generated_root, via proofs/generation.bend.
law generated_root:
  for tape: Tape()
  for +sampled: Bool
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.root(sampled))) == (rest, Trace.Created{created}) :
    TapeStep()}
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == sampled : Bool}

# LAW generated_child
#   Claim: a child created from any tape keeps the parent's trace ID with its
#     randomness assertion, takes sampled from Sampling.resolve, and never
#     reuses the parent's span ID.
#   Requirement: spec #1, "Merely generating a child's operation ID cannot turn
#     an incoming random 0 into 1" and the reuse rule of `child`.
#   Why: generating the operation's own ID must not change the trace it
#     continues.
#   Proof: Laws.generated_child, via proofs/generation.bend.
law generated_child:
  for tape: Tape()
  for +parent: Trace.Parent
  for +sampling: Trace.Sampling
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(16n, (tape, Trace.Draw.child(parent, sampling))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.LocalContext.trace_id(created) == Trace.Parent.trace_id(parent) : Trace.TraceId} &
  {Trace.LocalContext.is_sampled(created) == Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)) : Bool} &
  {Trace.SpanId.to_string(Trace.LocalContext.span_id(created)) !=
    Trace.SpanId.to_string(Trace.Parent.span_id(parent)) : String}

# LAW generated_restart
#   Claim: a restart created from any tape has a trace ID other than the
#     received one, asserts random-trace-id and has the sampled indication
#     that it was given, so it is emitted with flags 03 when it is sampled and
#     02 when it is not. With False, it is not sampled, as the restart that
#     Context.continue_or_start_with starts by default at a trust boundary.
#   Requirement: as for `restart` and generated_root; spec #41, "Sampling
#     decision when starting a trace": a restart takes the sampled indication
#     explicitly, and still takes only a remote context (user story 26).
#   Why: a trust boundary restarts traces under the application's sampling
#     policy, and the new trace never reuses the received one, whatever the
#     indication.
#   Reading: the flags follow from the last two conclusions by
#     emitted_traceparent (section 3), as for generated_root.
#   Proof: Laws.generated_restart, via proofs/generation.bend.
law generated_restart:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  for +sampled: Bool
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous, sampled))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.to_string(Trace.LocalContext.trace_id(created)) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String} &
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == sampled : Bool}

# The loop of a host that drives a generation itself, one word at a time,
# as JavaScript code calling the package does with WebCrypto words: while
# Generation.needs says the generation needs a word, feed it the tape's next
# word; then take the generation's result. An empty tape gives the failure
# that Source.tape gives, 1 tape-exhausted. `steps` bounds the loop, as Bend
# requires for termination; generation_drive shows that the bound makes no
# difference once it covers the generation's budget, so a loop without one
# ends by itself.
def host.loop(steps: Nat, needs: Bool, tape: Tape(), +generation: Trace.Generation) -> TapeOutcome():
  match steps needs tape:
    case 0n _ _:
      (tape, Trace.Generation.result(generation))
    case 1n+p False{} _:
      (tape, Trace.Generation.result(generation))
    case 1n+p True{} Nil{}:
      +next = Trace.Generation.feed(generation, Fail{(1, "tape-exhausted")})
      host.loop(p, Trace.Generation.needs(next), Nil{}, next)
    case 1n+p True{} Con{word, rest}:
      +next = Trace.Generation.feed(generation, word)
      host.loop(p, Trace.Generation.needs(next), rest, next)

def host(steps: Nat, tape: Tape(), +generation: Trace.Generation) -> TapeOutcome():
  host.loop(steps, Trace.Generation.needs(generation), tape, generation)

# The host's loop bounded by the generation's own budget.
def host.drive(tape: Tape(), generation: Trace.Generation) -> TapeOutcome():
  match generation:
    case Trace.Generation{+fuel, step}:
      host(fuel, tape, Trace.Generation{fuel, step})

# LAW generation_drive
#   Claim: a host that feeds a generation the next word of its source while
#     Generation.needs says it needs one reads the same words, in order, and
#     gets the same result as the pure driver Draw.run with the generation's
#     budget, whatever bound its loop has beyond that budget: the loop ends
#     by itself.
#   Requirement: ticket #13, "without a second protocol implementation": a
#     JavaScript host feeds WebCrypto words to the package's machine instead
#     of generating identifiers itself; spec #1, "Allow an explicit caller
#     provider".
#   Why: with root_tape and its siblings, the generation a host drives is the
#     IO operation that every other generation law describes, candidate
#     rules, budgets and failures included.
#   Reading: Generation{fuel, step} is a generation with `fuel` words of
#     budget left; Generation.root, child and restart start with 48, 16 and
#     48. host is defined above, and `extra` is any additional bound.
#   Proof: Laws.generation_drive, via proofs/generation.bend.
law generation_drive:
  for fuel: Nat
  for tape: Tape()
  for step: Trace.Step
  for extra: Nat
  {host(Nat.add(fuel, extra), tape, Trace.Generation{fuel, step}) ==
    Trace.Draw.outcome(Tape(), Trace.Draw.run(fuel, (tape, step))) : TapeOutcome()}

# Separate generation
# -------------------
#
# TraceId.generate_with and SpanId.generate_with generate one identifier
# alone from a caller's source, and TraceId.generate and SpanId.generate in
# generation.bend on the host's, as an OpenTelemetry SDK needs to start a
# span (GUIDE.md, "Building blocks for an OpenTelemetry SDK"). Each runs one
# piece of the generation machine: a trace ID draw (TraceDraw and TraceStep
# in trace_context.bend) or a span ID draw (SpanDraw and SpanStep), with the
# candidate rules above and an optional identifier to exclude. The rules
# come from spec #41, "Separate generation". As above, the laws quantify
# over every tape, state the pieces on their pure drivers, TraceDraw.run and
# SpanDraw.run, and tie those drivers to the IO operations.

# A tape's unread rest, with a trace ID draw's state after reading.
def TapeTraceStep() -> Type:
  Tape() & Trace.TraceStep

# A tape's unread rest, with the trace ID generated or why it failed.
def TapeTraceId() -> Type:
  Tape() & Result<&2, &2, Trace.GenerationError, Trace.TraceId>

# The claim that a generated trace ID avoids the one to exclude: nothing to
# prove without one (Unit), and otherwise that their texts differ.
def TraceAvoids(excluded: Maybe<&2, Trace.TraceId>, id: Trace.TraceId) -> Type:
  match excluded:
    case None{}:
      Unit
    case Some{old}:
      {Trace.TraceId.to_string(id) != Trace.TraceId.to_string(old) : String}

# LAW trace_id_failure
#   Claim: a source error ends a trace ID draw at once with SourceFailure,
#     carrying the source's own code and message, whatever the draw was doing.
#   Requirement: spec #41, "Separate generation": trace ID generation "fails
#     with SourceFailure or ExhaustedTraceId"; spec #1, "A source error at any
#     word ends generation immediately".
#   Why: as for feed_failure, a draw that went on after a failed read, or
#     filled in a word, would give a trace ID that is not random while
#     asserting that it is.
#   Proof: Laws.trace_id_failure, by computation.
law trace_id_failure:
  for code: U32
  for message: String
  for remaining: Nat
  for words: Trace.TraceWords
  for excluded: Maybe<&2, Trace.TraceId>
  {Trace.TraceDraw.feed(Fail{(code, message)}, remaining, words, excluded) ==
    Trace.TraceFailed{Trace.SourceFailure{code, message}} : Trace.TraceStep}

# LAW trace_id_tape
#   Claim: generating a trace ID alone from a tape source does exactly what the
#     pure driver TraceDraw.run does with a budget of 32 words, for every
#     trace ID to exclude: the same words are read, in order, and the unread
#     ones are handed back.
#   Requirement: spec #41, "Separate generation": both forms exist "with a
#     caller's identifier source"; user story 33 of #41, a replayed tape
#     drives the separate generation.
#   Why: it carries the laws below, stated on the pure driver, over to the
#     operation that an SDK and its tests call.
#   Proof: Laws.trace_id_tape, via proofs/separate.bend.
law trace_id_tape:
  for tape: Tape()
  for excluded: Maybe<&2, Trace.TraceId>
  {Observe(TapeTraceId(), Trace.TraceId.generate_with(~Tape(), ~Trace.Source.tape, tape, excluded)) ==
    Emit{Trace.TraceDraw.outcome(Tape(), Trace.TraceDraw.run(32n, (tape, Trace.TraceDraw.start(excluded))))} :
    IO.OP<TapeTraceId()>}

# LAW trace_id_candidate
#   Claim: when the first four words of a tape make a trace ID, generating a
#     trace ID with none to exclude reads exactly those four words and gives
#     that trace ID, which asserts random-trace-id.
#   Requirement: spec #41, "Separate generation": trace ID generation "reads
#     four source words per candidate, most significant first" and "asserts
#     random-trace-id on the result".
#   Why: with trace_words, it fixes which trace ID a sequence of words gives
#     and that no word beyond the candidate is read, so that another
#     implementation or a test with a replayed source can predict it.
#   Reading: `made` says the four words make a nonzero candidate, `id`, as
#     TraceId.from_words converts them.
#   Scope: stated with nothing to exclude; generated_trace_id covers the
#     excluded trace ID, and the consumer's SDK flow shows an excluded
#     candidate replaced by the next one.
#   Proof: Laws.trace_id_candidate, by computation once `made` is rewritten.
law trace_id_candidate:
  for first: U32
  for second: U32
  for third: U32
  for fourth: U32
  for id: Trace.TraceId
  for made: {Trace.TraceId.from_words(first, second, third, fourth) == Some{id} : Maybe<&2, Trace.TraceId>}
  for rest: Tape()
  {Trace.TraceDraw.run(32n, (Con{Done{first}, Con{Done{second}, Con{Done{third}, Con{Done{fourth}, rest}}}},
    Trace.TraceDraw.start(None{}))) == (rest, Trace.DrawnTraceId{Trace.TraceId.assert_random(id)}) :
    TapeTraceStep()}

# LAW trace_id_ends
#   Claim: for every tape and every trace ID to exclude, a trace ID draw has
#     finished, with a trace ID or a failure, within 32 words.
#   Requirement: spec #41, "Separate generation": trace ID generation reads
#     four words per candidate "for at most eight candidates".
#   Why: generation always ends with an answer, and the budget of
#     TraceId.generate_with is exactly this worst case, so it never gives up
#     early.
#   Reading: TraceDraw.ended says the driver's step is DrawnTraceId or
#     TraceFailed.
#   Proof: Laws.trace_id_ends, via proofs/separate.bend.
law trace_id_ends:
  for tape: Tape()
  for +excluded: Maybe<&2, Trace.TraceId>
  {Trace.TraceDraw.ended(Trace.TraceDraw.run(32n, (tape, Trace.TraceDraw.start(excluded)))) == True{} : Bool}

# LAW trace_id_exhaustion
#   Claim: eight all-zero trace ID candidates (32 zero words) make a trace ID
#     draw fail with ExhaustedTraceId, whatever it must exclude, and the words
#     after them are not read.
#   Requirement: spec #41, "Separate generation": trace ID generation "rejects
#     all-zero candidates" for "at most eight candidates" and "fails with ...
#     ExhaustedTraceId".
#   Why: as for root_exhaustion, a source stuck on zeros gets a structured
#     error instead of an invalid ID or an endless loop.
#   Scope: proved for all-zero candidates; a candidate equal to the excluded
#     trace ID is refused by generated_trace_id.
#   Proof: Laws.trace_id_exhaustion, by computation.
law trace_id_exhaustion:
  for excluded: Maybe<&2, Trace.TraceId>
  for rest: Tape()
  {Trace.TraceDraw.run(32n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest),
    Trace.TraceDraw.start(excluded))) == (rest, Trace.TraceFailed{Trace.ExhaustedTraceId{}}) : TapeTraceStep()}

# LAW generated_trace_id
#   Claim: a trace ID generated alone from any tape asserts random-trace-id,
#     and its text differs from that of the trace ID to exclude, if there is
#     one.
#   Requirement: spec #41, "Separate generation": trace ID generation "rejects
#     ... an optional trace ID to exclude" and "asserts random-trace-id on the
#     result"; "generation trusts its source, so every generated trace ID
#     asserts random-trace-id, as root generation does".
#   Why: the spans that an SDK starts on a generated trace ID emit the
#     random-trace-id flag as generated roots do, and a restart's new trace
#     never reuses the one it replaces.
#   Reading: TraceAvoids, above, is Unit without a trace ID to exclude.
#   Scope: the source is trusted to be random; no law speaks about the quality
#     of a real source.
#   Proof: Laws.generated_trace_id, via proofs/separate.bend.
law generated_trace_id:
  for tape: Tape()
  for +excluded: Maybe<&2, Trace.TraceId>
  for rest: Tape()
  for id: Trace.TraceId
  for generated: {Trace.TraceDraw.run(32n, (tape, Trace.TraceDraw.start(excluded))) ==
    (rest, Trace.DrawnTraceId{id}) : TapeTraceStep()}
  {Trace.TraceId.is_random(id) == True{} : Bool} & TraceAvoids(excluded, id)

# A tape's unread rest, with a span ID draw's state after reading.
def TapeSpanStep() -> Type:
  Tape() & Trace.SpanStep

# A tape's unread rest, with the span ID generated or why it failed.
def TapeSpanId() -> Type:
  Tape() & Result<&2, &2, Trace.GenerationError, Trace.SpanId>

# The claim that a generated span ID avoids the one to exclude, as
# TraceAvoids states it of trace IDs.
def SpanAvoids(excluded: Maybe<&2, Trace.SpanId>, id: Trace.SpanId) -> Type:
  match excluded:
    case None{}:
      Unit
    case Some{old}:
      {Trace.SpanId.to_string(id) != Trace.SpanId.to_string(old) : String}

# LAW span_id_failure
#   Claim: a source error ends a span ID draw at once with SourceFailure,
#     carrying the source's own code and message, whatever the draw was doing.
#   Requirement: spec #41, "Separate generation": span ID generation "fails
#     with SourceFailure or ExhaustedSpanId"; spec #1, "A source error at any
#     word ends generation immediately".
#   Why: as for trace_id_failure.
#   Proof: Laws.span_id_failure, by computation.
law span_id_failure:
  for code: U32
  for message: String
  for remaining: Nat
  for words: Trace.SpanWords
  for excluded: Maybe<&2, Trace.SpanId>
  {Trace.SpanDraw.feed(Fail{(code, message)}, remaining, words, excluded) ==
    Trace.SpanFailed{Trace.SourceFailure{code, message}} : Trace.SpanStep}

# LAW span_id_tape
#   Claim: as trace_id_tape, for a span ID generated alone with a budget of 16
#     words.
#   Proof: Laws.span_id_tape, via proofs/separate.bend.
law span_id_tape:
  for tape: Tape()
  for excluded: Maybe<&2, Trace.SpanId>
  {Observe(TapeSpanId(), Trace.SpanId.generate_with(~Tape(), ~Trace.Source.tape, tape, excluded)) ==
    Emit{Trace.SpanDraw.outcome(Tape(), Trace.SpanDraw.run(16n, (tape, Trace.SpanDraw.start(excluded))))} :
    IO.OP<TapeSpanId()>}

# LAW span_id_candidate
#   Claim: when the first two words of a tape make a span ID, generating a
#     span ID with none to exclude reads exactly those two words and gives
#     that span ID.
#   Requirement: spec #41, "Separate generation": span ID generation "reads
#     two words per candidate", most significant first as for trace IDs.
#   Why and Scope: as for trace_id_candidate, with span_words.
#   Proof: Laws.span_id_candidate, by computation once `made` is rewritten.
law span_id_candidate:
  for first: U32
  for second: U32
  for id: Trace.SpanId
  for made: {Trace.SpanId.from_words(first, second) == Some{id} : Maybe<&2, Trace.SpanId>}
  for rest: Tape()
  {Trace.SpanDraw.run(16n, (Con{Done{first}, Con{Done{second}, rest}}, Trace.SpanDraw.start(None{}))) ==
    (rest, Trace.DrawnSpanId{id}) : TapeSpanStep()}

# LAW span_id_ends
#   Claim: for every tape and every span ID to exclude, a span ID draw has
#     finished within 16 words: eight candidates of two words.
#   Requirement: spec #41, "Separate generation": span ID generation reads two
#     words per candidate "for at most eight candidates".
#   Why: as for trace_id_ends, for SpanId.generate_with.
#   Proof: Laws.span_id_ends, via proofs/separate.bend.
law span_id_ends:
  for tape: Tape()
  for +excluded: Maybe<&2, Trace.SpanId>
  {Trace.SpanDraw.ended(Trace.SpanDraw.run(16n, (tape, Trace.SpanDraw.start(excluded)))) == True{} : Bool}

# LAW span_id_exhaustion
#   Claim: eight all-zero span ID candidates (16 zero words) make a span ID
#     draw fail with ExhaustedSpanId, whatever it must exclude, and the words
#     after them are not read.
#   Requirement: spec #41, "Separate generation": span ID generation "rejects
#     all-zero candidates" for "at most eight candidates" and "fails with ...
#     ExhaustedSpanId".
#   Why and Scope: as for trace_id_exhaustion.
#   Proof: Laws.span_id_exhaustion, by computation.
law span_id_exhaustion:
  for excluded: Maybe<&2, Trace.SpanId>
  for rest: Tape()
  {Trace.SpanDraw.run(16n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(16n), rest),
    Trace.SpanDraw.start(excluded))) == (rest, Trace.SpanFailed{Trace.ExhaustedSpanId{}}) : TapeSpanStep()}

# LAW generated_span_id
#   Claim: the text of a span ID generated alone from any tape differs from
#     that of the span ID to exclude, if there is one.
#   Requirement: spec #41, "Separate generation": span ID generation "rejects
#     ... an optional span ID to exclude"; user story 3 of #41, "a child span
#     never reuses its parent's span ID".
#   Why: an SDK that excludes a parent's span ID gets a child span that
#     identifies an operation of its own.
#   Reading: SpanAvoids, above, is Unit without a span ID to exclude.
#   Scope: the exclusion compares with one span ID only, as for children:
#     siblings may get the same span ID if the source repeats its words.
#   Proof: Laws.generated_span_id, via proofs/separate.bend.
law generated_span_id:
  for tape: Tape()
  for +excluded: Maybe<&2, Trace.SpanId>
  for rest: Tape()
  for id: Trace.SpanId
  for generated: {Trace.SpanDraw.run(16n, (tape, Trace.SpanDraw.start(excluded))) ==
    (rest, Trace.DrawnSpanId{id}) : TapeSpanStep()}
  SpanAvoids(excluded, id)

# Root, child and restart generation as compositions
# --------------------------------------------------
#
# The laws below state that, for every tape, root, child and restart
# generation are the compositions of the separate generation that spec #41
# describes. With root_tape, child_tape and restart_tape, they also say that
# the separate generation follows the machine that the laws above describe,
# word for word.

# The context of a span ID generated from a tape for an operation of
# `trace_id` with the sampled indication `sampled`: its failure is the
# context's, and otherwise it is Context.from_ids of the three, with the
# words left.
def context_of(+trace_id: Trace.TraceId, +sampled: Bool, done: TapeSpanId()) -> TapeOutcome():
  match done:
    case Tuple{rest, Fail{error}}:
      (rest, Fail{error})
    case Tuple{rest, Done{span_id}}:
      (rest, Done{Trace.Context.from_ids(trace_id, span_id, sampled)})

# What follows a root's or a restart's trace ID: its failure is the
# generation's, and otherwise a span ID, with none to exclude, from the words
# left, and the root of both with the sampled indication `sampled`.
def root_of(sampled: Bool, done: TapeTraceId()) -> IO(TapeOutcome()):
  match done:
    case Tuple{rest, Fail{error}}:
      IO.pure(TapeOutcome(), (rest, Fail{error}))
    case Tuple{rest, Done{trace_id}}:
      IO.bind(TapeSpanId(), TapeOutcome(), Trace.SpanId.generate_with(~Tape(), ~Trace.Source.tape, rest, None{}),
        spanned => IO.pure(TapeOutcome(), context_of(trace_id, sampled, spanned)))

# LAW root_composed
#   Claim: for every tape and every sampled indication, generating a root is
#     generating a trace ID with none to exclude, then a span ID from the
#     words left with none to exclude, and making the root of both with that
#     indication; either failure is the root's.
#   Requirement: spec #41, "Separate generation": "A root is a trace ID then
#     a span ID", keeping "their word order, word budgets and results".
#   Why: an SDK that composes the separate generation gets the roots that
#     the package generates, so both follow one implementation of the
#     identifier rules, and root_tape and the laws after it describe both.
#   Reading: root_of and context_of are defined above; Observe runs each IO
#     action, as in root_tape.
#   Scope: stated for tapes, as the other generation laws are; the host
#     source runs through the same operations.
#   Proof: Laws.root_composed, via proofs/separate.bend.
law root_composed:
  for tape: Tape()
  for +sampled: Bool
  {Observe(TapeOutcome(), Trace.Context.root_with(~Tape(), ~Trace.Source.tape, tape, sampled)) ==
    Observe(TapeOutcome(), IO.bind(TapeTraceId(), TapeOutcome(),
      Trace.TraceId.generate_with(~Tape(), ~Trace.Source.tape, tape, None{}), traced => root_of(sampled, traced))) :
    IO.OP<TapeOutcome()>}

# LAW child_composed
#   Claim: for every tape, generating a child of `parent` is generating a
#     span ID that excludes the parent's, and making the context of the
#     parent's trace ID, that span ID and the sampled indication that
#     Sampling.resolve gives; a failure is the child's.
#   Requirement: spec #41, "Separate generation": "a child is a span ID
#     excluding the parent's", with unchanged results.
#   Why: as for root_composed; an SDK starts a child span by generating its
#     span ID alone, excluding its parent's.
#   Scope: as for root_composed.
#   Proof: Laws.child_composed, via proofs/separate.bend.
law child_composed:
  for tape: Tape()
  for +parent: Trace.Parent
  for sampling: Trace.Sampling
  {Observe(TapeOutcome(), Trace.Context.child_with(~Tape(), ~Trace.Source.tape, tape, parent, sampling)) ==
    Observe(TapeOutcome(), IO.bind(TapeSpanId(), TapeOutcome(),
      Trace.SpanId.generate_with(~Tape(), ~Trace.Source.tape, tape, Some{Trace.Parent.span_id(parent)}),
      spanned => IO.pure(TapeOutcome(), context_of(Trace.Parent.trace_id(parent),
        Trace.Sampling.resolve(sampling, Trace.Parent.is_sampled(parent)), spanned)))) : IO.OP<TapeOutcome()>}

# LAW restart_composed
#   Claim: for every tape and every sampled indication, generating a restart
#     of `previous` is generating a trace ID that excludes the received one,
#     then what follows a root's trace ID with that indication (root_of).
#   Requirement: spec #41, "Separate generation": "a restart is a trace ID
#     excluding the received one, then a span ID", with unchanged results.
#   Why and Scope: as for root_composed.
#   Proof: Laws.restart_composed, via proofs/separate.bend.
law restart_composed:
  for tape: Tape()
  for previous: Trace.RemoteContext
  for +sampled: Bool
  {Observe(TapeOutcome(), Trace.Context.restart_with(~Tape(), ~Trace.Source.tape, tape, previous, sampled)) ==
    Observe(TapeOutcome(), IO.bind(TapeTraceId(), TapeOutcome(),
      Trace.TraceId.generate_with(~Tape(), ~Trace.Source.tape, tape, Some{Trace.RemoteContext.trace_id(previous)}),
      traced => root_of(sampled, traced))) : IO.OP<TapeOutcome()>}

# Tracestate
# ----------

# 7. Limits
# =========
#
# Limits holds three budgets, in UTF-8 octets: the most a received traceparent
# value may take, the most a combined tracestate value may take, and the most
# an emitted tracestate may take (spec #1, "Tracestate policy and resource
# bounds"). Budgets bound the work a received message can cause (W3C Level 2,
# section 7.2, "Denial of Service"), and a configuration must accept what it
# emits itself.

# LAW limits_bounds
#   Claim: every Limits value has a traceparent input budget of at least 55, an
#     output budget of at least 512, and an input budget no smaller than its
#     output budget.
#   Requirement: spec #1, "Validated limits require a traceparent input budget
#     of at least 55 bytes and a tracestate input budget no smaller than its
#     output budget, so a configuration accepts its own normalized emitted
#     representation", and "A configured output budget must be at least 512".
#   Why: a configuration that refused its own 55-character traceparent, or
#     tracestate it emits itself, would break propagation between two
#     instances of the same service.
#   Reading: the law ranges over every value of the type, however it was
#     obtained: each Limits value stores the proof of these rules.
#   Proof: Laws.limits_bounds, via proofs/limits.bend.
law limits_bounds:
  for limits: Trace.Limits
  {Nat.is_ge(Trace.Limits.traceparent_input(limits), 55n) == True{} : Bool} &
  {Nat.is_ge(Trace.Limits.tracestate_output(limits), 512n) == True{} : Bool} &
  {Nat.is_ge(Trace.Limits.tracestate_input(limits), Trace.Limits.tracestate_output(limits)) == True{} : Bool}

# LAW limits_new
#   Claim: Limits.new succeeds exactly when the three rules of limits_bounds
#     hold.
#   Requirement: as for limits_bounds. W3C Level 2, section 3.3.3.1: "Vendors
#     SHOULD propagate at least 512 characters of a combined header".
#   Why: no valid configuration is refused, and no invalid one accepted.
#   Reading: Result.is_done(...) is True{} for a success; the right side spells
#     out the three rules independently of the package's own check.
#   Proof: Laws.limits_new, via proofs/limits.bend.
law limits_new:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  {Result.is_done(&2, &2, Trace.LimitsError, Trace.Limits,
    Trace.Limits.new(traceparent_input, tracestate_input, tracestate_output)) ==
    Bool.and(Nat.is_ge(traceparent_input, 55n),
      Bool.and(Nat.is_ge(tracestate_output, 512n), Nat.is_ge(tracestate_input, tracestate_output))) : Bool}

# LAW limits_fields
#   Claim: the limits Limits.new returns have exactly the budgets passed in.
#   Why: a constructor that adjusted a budget would silently change what the
#     caller configured.
#   Proof: Laws.limits_fields, via proofs/limits.bend.
law limits_fields:
  for +traceparent_input: Nat
  for +tracestate_input: Nat
  for +tracestate_output: Nat
  for limits: Trace.Limits
  for accepted: {Trace.Limits.new(traceparent_input, tracestate_input, tracestate_output) == Done{limits} :
    Result<&2, &2, Trace.LimitsError, Trace.Limits>}
  {Trace.Limits.traceparent_input(limits) == traceparent_input : Nat} &
  {Trace.Limits.tracestate_input(limits) == tracestate_input : Nat} &
  {Trace.Limits.tracestate_output(limits) == tracestate_output : Nat}

# LAW default_limits
#   Claim: the default limits are 32768 octets (32 KiB) for a traceparent
#     value, 32768 for a combined tracestate value and 512 for an emitted
#     tracestate.
#   Requirement: spec #1, "Default input budgets are 32 KiB per traceparent
#     value and 32 KiB for the combined tracestate value" and "Default emitted
#     tracestate budget is 512 bytes". The 512 is this package's capacity
#     policy, not a maximum set by W3C.
#   Proof: Laws.default_limits, by computation.
law default_limits:
  {Trace.Limits.traceparent_input(Trace.Limits.default()) == 32768n : Nat} &
  {Trace.Limits.tracestate_input(Trace.Limits.default()) == 32768n : Nat} &
  {Trace.Limits.tracestate_output(Trace.Limits.default()) == 512n : Nat}

# 8. Tracestate keys and values
# =============================
#
# A tracestate entry is `key=value` (W3C Level 2, section 3.3.2.2). A key has
# 1 to 256 characters: a lowercase ASCII letter or a digit, then lowercase
# letters, digits, "_", "-", "*", "/" or "@". A value has 1 to 256 printable
# ASCII characters other than "," and "=", and does not end with a space.
# StateKey and StateValue carry a proof that their text follows these rules,
# so the grammar is checked once, when a key or value is built.

# LAW key_parse
#   Claim: when StateKey.parse accepts a text, the key is exactly that text.
#   Requirement: W3C Level 2, section 3.3.2.2.1. Spec #1, "Query, insert,
#     update and remove entries through validated operations".
#   Why: a key names a vendor. A parser that trimmed or folded case would make
#     an application read or write another vendor's entry.
#   Proof: Laws.key_parse, via proofs/tracestate.bend.
law key_parse:
  for +text: String
  for key: Trace.StateKey
  for accepted: {Trace.StateKey.parse(text) == Done{key} : Result<&2, &2, Trace.EntryError, Trace.StateKey>}
  {Trace.StateKey.to_string(key) == text : String}

# LAW key_roundtrip
#   Claim: the text of every key is accepted back as that same key.
#   Why: with key_parse, StateKey.parse accepts exactly the texts of keys, so a
#     key taken from a received tracestate can be used again for lookups.
#   Proof: Laws.key_roundtrip, via proofs/tracestate.bend.
law key_roundtrip:
  for key: Trace.StateKey
  {Trace.StateKey.parse(Trace.StateKey.to_string(key)) == Done{key} : Result<&2, &2, Trace.EntryError, Trace.StateKey>}

# LAW value_parse
#   Claim: when StateValue.parse accepts a text, the value is exactly that
#     text, leading spaces included.
#   Requirement: W3C Level 2, section 3.3.2.2.2: "All leading spaces MUST be
#     preserved as part of the value".
#   Why: a value is opaque to everyone but its vendor, so the package must not
#     change a single character of it.
#   Proof: Laws.value_parse, via proofs/tracestate.bend.
law value_parse:
  for +text: String
  for value: Trace.StateValue
  for accepted: {Trace.StateValue.parse(text) == Done{value} : Result<&2, &2, Trace.EntryError, Trace.StateValue>}
  {Trace.StateValue.to_string(value) == text : String}

# LAW value_roundtrip
#   Claim: the text of every value is accepted back as that same value.
#   Why: as for key_roundtrip.
#   Proof: Laws.value_roundtrip, via proofs/tracestate.bend.
law value_roundtrip:
  for value: Trace.StateValue
  {Trace.StateValue.parse(Trace.StateValue.to_string(value)) == Done{value} :
    Result<&2, &2, Trace.EntryError, Trace.StateValue>}

# Whether no character of `text` is `char`.
def lacks(+char: Char, text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{first, rest}:
      Bool.and(Bool.not(Char.is_eq(first, char)), lacks(char, rest))

# LAW key_separators
#   Claim: no key contains "," or "=".
#   Requirement: W3C Level 2, sections 3.3.2.1 and 3.3.2.2: "," separates list
#     members and "=" separates a key from its value.
#   Why: a key containing either would make a formatted tracestate ambiguous:
#     the receiver would split it differently from what was sent.
#   Proof: Laws.key_separators, via proofs/normal.bend.
law key_separators:
  for key: Trace.StateKey
  {lacks(',', Trace.StateKey.to_string(key)) == True{} : Bool} &
  {lacks('=', Trace.StateKey.to_string(key)) == True{} : Bool}

# LAW value_separators
#   Claim: no value contains "," or "=".
#   Requirement and Why: as for key_separators.
#   Proof: Laws.value_separators, via proofs/normal.bend.
law value_separators:
  for value: Trace.StateValue
  {lacks(',', Trace.StateValue.to_string(value)) == True{} : Bool} &
  {lacks('=', Trace.StateValue.to_string(value)) == True{} : Bool}

# 9. Tracestate states and lookups
# ================================
#
# A TraceState is the ordered list of vendor entries of a tracestate, the
# leftmost first (W3C Level 2, section 3.3.3). It carries a proof that its
# keys are distinct and that it has at most 32 entries (section 3.3.2: "There
# can be a maximum of 32 list-members in a list"; section 3.3.3: "Only one
# entry per key is allowed").

# Whether an entry of `entries` has the key `key`: an ordinary search through
# the list, written independently of the package's own lookup.
def key_among(+key: String, entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(String.eq(key, Trace.StateEntry.key_text(entry)), key_among(key, rest))

# No two entries share a key: no entry's key appears in an entry after it.
def keys_distinct(entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{entry, +rest}:
      Bool.and(Bool.not(key_among(Trace.StateEntry.key_text(entry), rest)), keys_distinct(rest))

# LAW state_valid
#   Claim: every state has distinct keys and at most 32 entries.
#   Requirement: W3C Level 2, sections 3.3.2 and 3.3.3. Spec #1, "State
#     operations preserve grammar, uniqueness, count bounds and unrelated-entry
#     order".
#   Why: every operation on states, parsing, editing and emitting (section
#     11) and injection (section 13), can rely on these invariants without
#     checking them again.
#   Reading: keys_distinct is this file's own definition. The package checks
#     distinct keys differently, each key against the entries before it, and
#     the proof shows the two agree.
#   Proof: Laws.state_valid, via proofs/distinct.bend.
law state_valid:
  for state: Trace.TraceState
  {keys_distinct(Trace.TraceState.entries(state)) == True{} : Bool} &
  {Nat.is_le(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}

# LAW get_entry
#   Claim: for every entry of a state, looking up its key gives its value.
#   Requirement: spec #1, "I want to inspect provider state by key, so that I
#     can use my own entry while preserving other providers' data" (user story
#     19).
#   Why: an application must find its own entry wherever it is in the list.
#   Reading: `split` says the state's entries are `before`, then `entry`, then
#     `after`: it picks out any one entry of the state.
#   Proof: Laws.get_entry, via proofs/distinct.bend.
law get_entry:
  for state: Trace.TraceState
  for +before: List<&2, Trace.StateEntry>
  for +entry: Trace.StateEntry
  for +after: List<&2, Trace.StateEntry>
  for +split: {Trace.TraceState.entries(state) == List.append(&2, Trace.StateEntry, before, Con{entry, after}) :
    List<&2, Trace.StateEntry>}
  {Trace.TraceState.get(state, Trace.StateEntry.key(entry)) == Some{Trace.StateEntry.value(entry)} :
    Maybe<&2, Trace.StateValue>}

# LAW get_absent
#   Claim: looking up a key that no entry has gives None{}.
#   Why: with get_entry, lookups answer exactly from the entries and never
#     invent a value.
#   Proof: Laws.get_absent, via proofs/distinct.bend.
law get_absent:
  for state: Trace.TraceState
  for +key: Trace.StateKey
  for absent: {key_among(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)) == False{} : Bool}
  {Trace.TraceState.get(state, key) == None{} : Maybe<&2, Trace.StateValue>}

# 10. Tracestate parsing
# ======================
#
# TraceState.parse reads one combined tracestate value, and
# TraceState.parse_fields reads the repeated tracestate fields of a message in
# arrival order (W3C Level 2, section 3.3.2: multiple fields "MUST be combined
# into a single header according to RFC9110"). TraceState.format gives a
# state's normalized value: the entries in order, as `key=value`, joined by
# commas, with no optional whitespace. These laws relate parsing to
# formatting and fix the policies of spec #1, "Tracestate policy and resource
# bounds". The corpus, tests/TRACESTATE.bend, covers the character classes,
# whitespace between members, the member numbers of diagnostics and other
# inputs that are not normalized values.

# LAW state_roundtrip
#   Claim: parsing a state's normalized value gives back that state whenever
#     the value fits the tracestate input budget.
#   Requirement: ticket #7, "Prove validity, uniqueness/order properties and
#     the appropriate normalized parsing/formatting law". The normalized value
#     is what the package sends, so it must read back unchanged.
#   Why: state sent by one instance of the package and read by another must
#     arrive with the same entries in the same order.
#   Reading: `fits` bounds the formatted value's UTF-8 octets, Utf8.length, by
#     the budget. The conclusion compares whole states: entries and proofs.
#   Scope: received text is not restored: parsing drops optional whitespace,
#     empty members and later duplicates, so the law starts from a state, not
#     from arbitrary text.
#   Proof: Laws.state_roundtrip, as the case of ows_around with no whitespace
#     (proofs/normal.bend).
law state_roundtrip:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state)), Trace.Limits.tracestate_input(limits)) ==
    True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state)) == Done{state} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# Whether every character of `text` is optional whitespace: a space or a
# horizontal tab (OWS in RFC 9110, section 5.6.3).
def all_ows(text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{+first, rest}:
      Bool.and(Bool.or(Char.is_eq(first, ' '), Char.is_eq(first, '\t')), all_ows(rest))

# LAW ows_around
#   Claim: optional whitespace before and after a normalized value changes
#     nothing: the value still parses to the same state.
#   Requirement: W3C Level 2, section 3.3.2: "Spaces and horizontal tabs
#     surrounding list-members are ignored"; section 3.3.2.2.2: "All trailing
#     spaces are considered to be optional whitespace characters not part of
#     the value".
#   Why: hosts and proxies add whitespace around combined header values, and it
#     must not change a vendor's value.
#   Scope: whitespace between members, whitespace next to "=" and spaces at the
#     start of a value, which belong to the value, are covered by the corpus.
#   Proof: Laws.ows_around, via proofs/normal.bend.
law ows_around:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for +before: String
  for +after: String
  for before_ows: {all_ows(before) == True{} : Bool}
  for after_ows: {all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(before ++ Trace.TraceState.format(state) ++ after),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, before ++ Trace.TraceState.format(state) ++ after) == Done{state} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# LAW over_budget
#   Claim: a value whose UTF-8 octets exceed the tracestate input budget is
#     refused with StateTooLarge, whatever it contains.
#   Requirement: ticket #7, "Bound combined input by its configurable UTF-8
#     byte budget". Spec #1, "Stop bounded processing once the relevant budget
#     is exceeded".
#   Why: an oversized header must not make a service do unbounded work, and the
#     result must not depend on where an invalid character happens to be.
#   Scope: the law states the outcome. That measuring stops at the first
#     character past the budget follows from the definition of Utf8.left, and
#     the corpus checks it with a mebibyte input.
#   Proof: Laws.over_budget, via proofs/tracestate.bend.
law over_budget:
  for +limits: Trace.Limits
  for +text: String
  for larger: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(limits)) == False{} : Bool}
  {Trace.TraceState.parse(limits, text) == Fail{Trace.StateTooLarge{}} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# LAW within_budgets
#   Claim: for a value that fits two budgets, parsing with either gives the
#     same result.
#   Requirement: spec #1: budgets only refuse input; they are not parsing
#     rules.
#   Why: with over_budget, a budget either refuses a value or has no effect at
#     all: raising it never changes what a fitting value means.
#   Proof: Laws.within_budgets, via proofs/tracestate.bend.
law within_budgets:
  for +first: Trace.Limits
  for +second: Trace.Limits
  for +text: String
  for first_fits: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(first)) == True{} : Bool}
  for second_fits: {Nat.is_le(Trace.Utf8.length(text), Trace.Limits.tracestate_input(second)) == True{} : Bool}
  {Trace.TraceState.parse(first, text) == Trace.TraceState.parse(second, text) :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# LAW fields_join
#   Claim: parsing repeated fields gives exactly the result of parsing their
#     values joined with commas.
#   Requirement: W3C Level 2, section 3.3.2: multiple tracestate fields "MUST
#     be combined into a single header according to RFC9110". Spec #1, "for
#     repeated tracestate fields include the commas used to combine them" in
#     the budget.
#   Why: an adapter that receives the fields separately and one whose host
#     already combined them must see the same state, the same budget and the
#     same member numbers in diagnostics.
#   Proof: Laws.fields_join, via proofs/tracestate.bend.
law fields_join:
  for +limits: Trace.Limits
  for +fields: List<&2, String>
  {Trace.TraceState.parse_fields(limits, fields) == Trace.TraceState.parse(limits, String.join(fields, ",")) :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# LAW later_duplicate
#   Claim: when a state's value is followed by a comma and an entry whose key
#     the state already has, parsing gives back exactly the state: the later
#     entry is dropped.
#   Requirement: spec #1, "Preserve the first occurrence of a duplicate key".
#     W3C Level 2, section 3.3.3: "Only one entry per key is allowed".
#   Why: the leftmost entry is the vendor's most recent position; a later copy
#     is stale and must not replace it.
#   Reading: `present` says the key is among the state's keys. `room` says the
#     state has fewer than 32 entries, because the dropped entry still counts
#     as a member (see full_state).
#   Proof: Laws.later_duplicate, via proofs/merge.bend.
law later_duplicate:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  for +entry: Trace.StateEntry
  for present: {key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)) == True{} : Bool}
  for room: {Nat.is_lt(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)) ==
    Done{state} : Result<&2, &2, Trace.StateError, Trace.TraceState>}

# LAW later_new_key
#   Claim: when the entry's key is new, the entry follows all of the state's
#     entries, which keep their order.
#   Requirement: W3C Level 2, section 3.3.3: tracestate is an ordered list.
#     Spec #1: the order of unrelated entries is preserved.
#   Why: parsing must never reorder vendors' entries.
#   Reading: Result.map applies TraceState.entries to a successful result, so
#     the conclusion compares the parsed entries with a list.
#   Proof: Laws.later_new_key, via proofs/merge.bend.
law later_new_key:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  for +entry: Trace.StateEntry
  for +absent: {key_among(Trace.StateEntry.key_text(entry), Trace.TraceState.entries(state)) == False{} : Bool}
  for +room: {Nat.is_lt(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, Trace.StateError, Trace.TraceState, List<&2, Trace.StateEntry>,
    parsed => Trace.TraceState.entries(parsed),
    Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry))) ==
    Done{List.append(&2, Trace.StateEntry, Trace.TraceState.entries(state), Con{entry, Nil{}})} :
    Result<&2, &2, Trace.StateError, List<&2, Trace.StateEntry>>}

# LAW full_state
#   Claim: after a state of 32 entries, any further entry makes parsing fail
#     with TooManyMembers, even an entry repeating one of the keys.
#   Requirement: spec #1, "count those members before deduplication and reject
#     state with more than 32". W3C Level 2, section 3.3.2: "There can be a
#     maximum of 32 list-members in a list".
#   Why: counting before duplicates are dropped bounds the work of a hostile
#     header full of repeats, and spec #1 discards the whole state on a member
#     limit error.
#   Proof: Laws.full_state, via proofs/merge.bend.
law full_state:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  for entry: Trace.StateEntry
  for full: {List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)) == 32n : Nat}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Trace.TraceState.parse(limits, Trace.TraceState.format(state) ++ "," ++ Trace.StateEntry.format(entry)) ==
    Fail{Trace.TooManyMembers{}} : Result<&2, &2, Trace.StateError, Trace.TraceState>}

# The entries of `later` whose keys no entry of `earlier` has, in order.
def missing(+earlier: List<&2, Trace.StateEntry>, later: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match later:
    case Nil{}:
      Nil{}
    case Con{+entry, +rest}:
      Bool.pick(List<&2, Trace.StateEntry>, key_among(Trace.StateEntry.key_text(entry), earlier),
        missing(earlier, rest), Con{entry, missing(earlier, rest)})

# LAW first_wins
#   Claim: two states' values joined by a comma parse as the first state's
#     entries, followed in order by the second state's entries whose keys the
#     first lacks, whenever the value fits the budget and the two states have
#     at most 32 entries together.
#   Requirement: spec #1, "Preserve the first occurrence of a duplicate key"
#     and "count those members before deduplication". W3C Level 2, section
#     3.3.3.
#   Why: this is the general form of later_duplicate and later_new_key: it
#     covers any number of duplicates anywhere after the first state. For
#     example, "a=1" followed by "a=2,b=3" gives the entries a=1 and b=3.
#   Reading: `count` adds both states' entries because every member counts
#     before duplicates are dropped; `missing` is defined just above.
#   Proof: Laws.first_wins, via proofs/first.bend.
law first_wins:
  for +limits: Trace.Limits
  for first: Trace.TraceState
  for second: Trace.TraceState
  for +count: {Nat.is_le(Nat.add(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(first)),
    List.length(&2, Trace.StateEntry, Trace.TraceState.entries(second))), 32n) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceState.format(first) ++ "," ++ Trace.TraceState.format(second)),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}
  {Result.map(&2, &2, Trace.StateError, Trace.TraceState, List<&2, Trace.StateEntry>,
    parsed => Trace.TraceState.entries(parsed),
    Trace.TraceState.parse(limits, Trace.TraceState.format(first) ++ "," ++ Trace.TraceState.format(second))) ==
    Done{List.append(&2, Trace.StateEntry, Trace.TraceState.entries(first),
      missing(Trace.TraceState.entries(first), Trace.TraceState.entries(second)))} :
    Result<&2, &2, Trace.StateError, List<&2, Trace.StateEntry>>}

# 11. Tracestate updates and emission
# ===================================
#
# A participant may edit the state it sends with an operation of its own
# (W3C Level 2, section 3.5): a changed entry moves to the front and the
# other entries keep their order. The value it emits must fit the output
# budget of its limits; when it does not, whole entries are removed (section
# 3.3.3.1) in the order that spec #1 approves. An outgoing context pairs a
# local context with the state it sends, so an edited state travels with the
# traceparent of an operation of this participant, provided that
# Context.from_ids is only given the IDs of the caller's own operation
# (section 3.4 forbids editing the state of an unchanged traceparent).

# The entries whose key is not `key`, in order.
def without(+key: String, entries: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, +rest}:
      Bool.pick(List<&2, Trace.StateEntry>, String.eq(key, Trace.StateEntry.key_text(entry)),
        without(key, rest), Con{entry, without(key, rest)})

# LAW set_entries
#   Claim: setting a key puts its entry, with the new value, first, and the
#     other entries follow in their order, at most 31 of them.
#   Requirement: W3C Level 2, section 3.5: "Modified keys MUST be moved to
#     the beginning (left) of the list" and "the order of unmodified
#     key/value pairs MUST be preserved". Spec #1: "Insert/update moves the
#     affected key to the front and preserves the order of other entries".
#   Why: this one statement covers adding and updating. The key's previous
#     entry, if any, disappears, so the key stays unique, and the cap of 31
#     other entries keeps the state within 32.
#   Reading: `without` is defined just above. List.take(&2, T, list, 31n) is
#     the first 31 entries of `list`, or all of them when there are fewer.
#   Proof: Laws.set_entries, via proofs/update.bend.
law set_entries:
  for +state: Trace.TraceState
  for +key: Trace.StateKey
  for value: Trace.StateValue
  {Trace.TraceState.entries(Trace.TraceState.set(state, key, value)) ==
    Con{Trace.StateEntry{key, value}, List.take(&2, Trace.StateEntry,
      without(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)), 31n)} :
    List<&2, Trace.StateEntry>}

# LAW update_keeps_all
#   Claim: updating a key that the state has keeps every other entry, in its
#     order: no entry is evicted, even from a full state.
#   Requirement: spec #1, "Updating an existing key in a full state does not
#     evict another entry".
#   Why: a participant refreshing its own entry must not destroy another
#     vendor's state.
#   Reading: `present` says that the key is among the state's keys.
#   Proof: Laws.update_keeps_all, via proofs/update.bend.
law update_keeps_all:
  for +state: Trace.TraceState
  for +key: Trace.StateKey
  for value: Trace.StateValue
  for present: {key_among(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)) == True{} : Bool}
  {Trace.TraceState.entries(Trace.TraceState.set(state, key, value)) ==
    Con{Trace.StateEntry{key, value}, without(Trace.StateKey.to_string(key), Trace.TraceState.entries(state))} :
    List<&2, Trace.StateEntry>}

# LAW insert_entries
#   Claim: adding a key that the state lacks puts its entry first, followed
#     by the state's first 31 entries: in a full state the last entry is
#     removed, and in any other state nothing is.
#   Requirement: spec #1, "inserting a new 33rd key removes the last entry".
#     W3C Level 2, section 3.3.2: "There can be a maximum of 32 list-members
#     in a list".
#   Why: the state stays within 32 entries, and the entry removed is the one
#     farthest from the front, the least recently changed.
#   Reading: `absent` says that no entry has the key. List.take keeps the
#     first 31 entries, which are all of them when there are at most 31.
#   Proof: Laws.insert_entries, via proofs/update.bend.
law insert_entries:
  for +state: Trace.TraceState
  for +key: Trace.StateKey
  for value: Trace.StateValue
  for absent: {key_among(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)) == False{} : Bool}
  {Trace.TraceState.entries(Trace.TraceState.set(state, key, value)) ==
    Con{Trace.StateEntry{key, value}, List.take(&2, Trace.StateEntry, Trace.TraceState.entries(state), 31n)} :
    List<&2, Trace.StateEntry>}

# LAW set_get
#   Claim: after setting a key, looking it up gives the value just set.
#   Requirement: spec #1, "Query, insert, update and remove entries through
#     validated operations".
#   Why: a participant reads back what it wrote, whatever the state held
#     before.
#   Proof: Laws.set_get, via proofs/update.bend.
law set_get:
  for state: Trace.TraceState
  for +key: Trace.StateKey
  for +value: Trace.StateValue
  {Trace.TraceState.get(Trace.TraceState.set(state, key, value), key) == Some{value} :
    Maybe<&2, Trace.StateValue>}

# LAW remove_entries
#   Claim: removing a key leaves every other entry, in its order.
#   Requirement: W3C Level 2, section 3.5: "Delete a key/value pair" and "the
#     order of unmodified key/value pairs MUST be preserved". Spec #1 (user
#     story 21): remove "state it chooses not to propagate".
#   Why: removal must be exact: the other vendors' entries neither move nor
#     disappear.
#   Scope: W3C asks vendors not to delete keys other vendors generated; the
#     package cannot know which vendor generated a key, so that choice stays
#     with the caller.
#   Proof: Laws.remove_entries, via proofs/update.bend.
law remove_entries:
  for +state: Trace.TraceState
  for +key: Trace.StateKey
  {Trace.TraceState.entries(Trace.TraceState.remove(state, key)) ==
    without(Trace.StateKey.to_string(key), Trace.TraceState.entries(state)) : List<&2, Trace.StateEntry>}

# LAW remove_get
#   Claim: after removing a key, looking it up gives None{}.
#   Why: a removed entry is not sent.
#   Proof: Laws.remove_get, via proofs/update.bend.
law remove_get:
  for state: Trace.TraceState
  for +key: Trace.StateKey
  {Trace.TraceState.get(Trace.TraceState.remove(state, key), key) == None{} : Maybe<&2, Trace.StateValue>}

# LAW entry_size
#   Claim: StateEntry.size is the number of UTF-8 octets of the entry's
#     text, key=value.
#   Requirement: spec #1, "Count commas in emitted size and key, equals sign
#     and value in an entry's size".
#   Why: truncation decides which entries are larger than 128 octets with this
#     size, so it must be the exact size of what is sent.
#   Proof: Laws.entry_size, via proofs/emit.bend.
law entry_size:
  for +entry: Trace.StateEntry
  {Trace.StateEntry.size(entry) == Trace.Utf8.length(Trace.StateEntry.format(entry)) : Nat}

# LAW state_size
#   Claim: TraceState.size is the number of UTF-8 octets of the state's
#     normalized value, the commas between entries included.
#   Requirement: spec #1, "Count commas in emitted size". W3C Level 2,
#     section 3.3.3.1: the length "includes commas required to separate list
#     items".
#   Why: the output budget is compared with this size, so it must count every
#     octet that is sent and nothing else.
#   Proof: Laws.state_size, via proofs/emit.bend.
law state_size:
  for +state: Trace.TraceState
  {Trace.TraceState.size(state) == Trace.Utf8.length(Trace.TraceState.format(state)) : Nat}

# LAW truncate_fits
#   Claim: the state that truncation keeps fits the output budget of the
#     limits.
#   Requirement: spec #1, "Default emitted tracestate budget is 512 bytes. A
#     configured output budget must be at least 512". W3C Level 2, section
#     3.3.3.1 on truncating an oversized tracestate.
#   Why: an emitted value never exceeds what the configuration promises to
#     its peers, whatever the state held.
#   Proof: Laws.truncate_fits, via proofs/emit.bend.
law truncate_fits:
  for +limits: Trace.Limits
  for state: Trace.TraceState
  {Nat.is_le(Trace.TraceState.size(Trace.Truncation.kept(Trace.TraceState.truncate(limits, state))),
    Trace.Limits.tracestate_output(limits)) == True{} : Bool}

# LAW truncate_whole
#   Claim: a state that fits the output budget is kept whole, and no key is
#     reported dropped.
#   Requirement: spec #1, "stop as soon as the budget is met".
#   Why: truncation never removes an entry that did not have to go.
#   Reading: truncate_steps below states the whole procedure; this law and
#     the next ones state its consequences plainly.
#   Proof: Laws.truncate_whole, via proofs/emit.bend.
law truncate_whole:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  for fits: {Nat.is_le(Trace.TraceState.size(state), Trace.Limits.tracestate_output(limits)) == True{} : Bool}
  {Trace.TraceState.truncate(limits, state) == Trace.Truncation{state, Nil{}} : Trace.Truncation}

# Whether two entries have the same key and the same value.
def same_entry(+a: Trace.StateEntry, +b: Trace.StateEntry) -> Bool:
  Bool.and(String.eq(Trace.StateEntry.key_text(a), Trace.StateEntry.key_text(b)),
    String.eq(Trace.StateValue.to_string(Trace.StateEntry.value(a)),
      Trace.StateValue.to_string(Trace.StateEntry.value(b))))

# Whether `kept` is `original` with some entries removed: the entries of
# `kept` appear in `original`, in the same order.
def in_order(original: List<&2, Trace.StateEntry>, kept: List<&2, Trace.StateEntry>) -> Bool:
  match original kept:
    case Nil{} _:
      List.is_empty(&2, Trace.StateEntry, kept)
    case Con{candidate, rest} Nil{}:
      True{}
    case Con{+candidate, +rest} Con{+entry, +more}:
      Bool.pick(Bool, same_entry(candidate, entry), in_order(rest, more), in_order(rest, Con{entry, more}))

# LAW truncate_order
#   Claim: truncation only removes entries: the entries it keeps appear in
#     the state, in their order.
#   Requirement: W3C Level 2, section 3.3.3.1: "the vendor MUST truncate
#     whole entries". Spec #1: "Remove only whole entries ... preserve
#     survivor order".
#   Why: an entry is never cut or altered, and the survivors keep the order
#     that tells vendors which one changed most recently.
#   Reading: in_order is defined just above.
#   Proof: Laws.truncate_order, via proofs/emit.bend.
law truncate_order:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  {in_order(Trace.TraceState.entries(state),
    Trace.TraceState.entries(Trace.Truncation.kept(Trace.TraceState.truncate(limits, state)))) == True{} : Bool}

# The keys of the entries, in order.
def keys(entries: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateKey>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{entry, rest}:
      Con{Trace.StateEntry.key(entry), keys(rest)}

# LAW truncate_dropped
#   Claim: the keys that truncation reports dropped are exactly the keys of
#     the state's entries it did not keep, in their order.
#   Requirement: spec #1, "report truncation" and "Diagnostics distinguish
#     absence, rejection, state discard, truncation".
#   Why: the diagnostic tells exactly which vendors' entries were not sent,
#     without repeating their opaque values.
#   Reading: missing, defined in section 10, gives the state's entries whose
#     keys no kept entry has; `keys` just above lists their keys.
#   Proof: Laws.truncate_dropped, via proofs/emit.bend.
law truncate_dropped:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  {Trace.Truncation.dropped(Trace.TraceState.truncate(limits, state)) ==
    keys(missing(Trace.TraceState.entries(Trace.Truncation.kept(Trace.TraceState.truncate(limits, state))),
      Trace.TraceState.entries(state))) : List<&2, Trace.StateKey>}

# The entries as `key=value`, each after the first preceded by a comma.
def joined.rest(entries: List<&2, Trace.StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      "," ++ Trace.StateEntry.format(entry) ++ joined.rest(rest)

# The entries as `key=value`, joined by commas: the value a state with these
# entries emits.
def joined(entries: List<&2, Trace.StateEntry>) -> String:
  match entries:
    case Nil{}:
      ""
    case Con{entry, rest}:
      Trace.StateEntry.format(entry) ++ joined.rest(rest)

# Whether the entry takes more than 128 octets, which W3C Level 2, section
# 3.3.3.1, asks to remove first.
def large(+entry: Trace.StateEntry) -> Bool:
  Nat.is_gt(Trace.Utf8.length(Trace.StateEntry.format(entry)), 128n)

# Whether one of the entries takes more than 128 octets.
def any_large(entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{entry, rest}:
      Bool.or(large(entry), any_large(rest))

# The entries without the rightmost one that takes more than 128 octets: an
# entry stays when a large entry follows it.
def without_last_large(entries: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{+entry, +rest}:
      Bool.pick(List<&2, Trace.StateEntry>, any_large(rest), Con{entry, without_last_large(rest)},
        Bool.pick(List<&2, Trace.StateEntry>, large(entry), rest, Con{entry, rest}))

# The entries without the rightmost one.
def without_last(entries: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{entry, +rest}:
      Bool.pick(List<&2, Trace.StateEntry>, List.is_empty(&2, Trace.StateEntry, rest), Nil{},
        Con{entry, without_last(rest)})

# Spec #1's truncation, one removal at a time: while the value of the entries
# takes more than `budget` octets, remove the rightmost entry larger than 128
# octets, or the rightmost entry when none is, and stop as soon as the value
# fits. `steps` bounds the removals.
def truncated(steps: Nat, +budget: Nat, +entries: List<&2, Trace.StateEntry>) -> List<&2, Trace.StateEntry>:
  match steps:
    case 0n:
      entries
    case 1n+more:
      Bool.pick(List<&2, Trace.StateEntry>, Nat.is_le(Trace.Utf8.length(joined(entries)), budget), entries,
        truncated(more, budget, Bool.pick(List<&2, Trace.StateEntry>, any_large(entries), without_last_large(entries),
          without_last(entries))))

# LAW truncate_steps
#   Claim: truncation keeps exactly the entries that spec #1's procedure
#     keeps: while the value is over the output budget, it removes the
#     rightmost entry larger than 128 octets, or the rightmost entry when
#     none is, and it stops as soon as the value fits.
#   Requirement: spec #1, "While over budget, remove the rightmost entry
#     larger than 128 characters; when none remain, remove from the right.
#     Remove only whole entries, stop as soon as the budget is met". W3C
#     Level 2, section 3.3.3.1: "Entries larger than 128 characters long
#     SHOULD be removed first. Then entries SHOULD be removed starting from
#     the end of tracestate".
#   Why: this pins down which entries go, not only that the rest fits: a
#     vendor's entry is never removed while a larger one to its right could
#     go instead, and no entry goes once the value fits.
#   Reading: `truncated` and the definitions above it restate the procedure
#     independently of the package, measuring with Utf8.length of the
#     entries' value. One step per entry is enough: after removing them all,
#     the empty value fits. Keys and values are ASCII, so the octets are also
#     the characters that W3C counts.
#   Proof: Laws.truncate_steps, via proofs/emit.bend.
law truncate_steps:
  for +limits: Trace.Limits
  for +state: Trace.TraceState
  {Trace.TraceState.entries(Trace.Truncation.kept(Trace.TraceState.truncate(limits, state))) ==
    truncated(List.length(&2, Trace.StateEntry, Trace.TraceState.entries(state)), Trace.Limits.tracestate_output(limits),
      Trace.TraceState.entries(state)) : List<&2, Trace.StateEntry>}

# LAW outgoing_set
#   Claim: setting an entry of an outgoing context changes its state as
#     TraceState.set does and keeps its local context.
#   Requirement: spec #1, "Apply associated-state changes only through the
#     allowed context transitions".
#   Why: editing the state never changes which operation the traceparent
#     identifies.
#   Proof: Laws.outgoing_set, by computation.
law outgoing_set:
  for +outgoing: Trace.OutgoingContext
  for key: Trace.StateKey
  for value: Trace.StateValue
  {Trace.OutgoingContext.set(outgoing, key, value) == Trace.OutgoingContext.with_state(Trace.OutgoingContext.context(outgoing),
    Trace.TraceState.set(Trace.OutgoingContext.state(outgoing), key, value)) : Trace.OutgoingContext}

# LAW outgoing_remove
#   Claim: removing an entry of an outgoing context changes its state as
#     TraceState.remove does and keeps its local context.
#   Requirement: as outgoing_set.
#   Proof: Laws.outgoing_remove, by computation.
law outgoing_remove:
  for +outgoing: Trace.OutgoingContext
  for key: Trace.StateKey
  {Trace.OutgoingContext.remove(outgoing, key) == Trace.OutgoingContext.with_state(Trace.OutgoingContext.context(outgoing),
    Trace.TraceState.remove(Trace.OutgoingContext.state(outgoing), key)) : Trace.OutgoingContext}

# LAW emit_traceparent
#   Claim: an outgoing context emits the participating traceparent of its
#     local context.
#   Requirement: spec #1, "Participating emission uses `00` and known flag
#     mask `03`" (see emitted_traceparent).
#   Why: the traceparent sent is the one of the local operation, never a
#     received value.
#   Proof: Laws.emit_traceparent, by computation.
law emit_traceparent:
  for limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  {Trace.Emission.traceparent(Trace.OutgoingContext.emit(limits, outgoing)) ==
    Trace.TraceParentV00.format(Trace.LocalContext.to_traceparent(Trace.OutgoingContext.context(outgoing))) : String}

# LAW emit_tracestate
#   Claim: an outgoing context emits the normalized value of its state
#     truncated to the output budget, and reports the keys truncation
#     dropped.
#   Requirement: spec #1, "Default emitted tracestate budget is 512 bytes"
#     and "report truncation".
#   Why: with truncate_fits, truncate_order and truncate_dropped, this ties
#     what is sent to the laws of truncation.
#   Proof: Laws.emit_tracestate, by computation.
law emit_tracestate:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  {Trace.Emission.tracestate(Trace.OutgoingContext.emit(limits, outgoing)) == Trace.TraceState.format(
    Trace.Truncation.kept(Trace.TraceState.truncate(limits, Trace.OutgoingContext.state(outgoing)))) : String} &
  {Trace.Emission.dropped(Trace.OutgoingContext.emit(limits, outgoing)) ==
    Trace.Truncation.dropped(Trace.TraceState.truncate(limits, Trace.OutgoingContext.state(outgoing))) :
    List<&2, Trace.StateKey>}

# LAW emit_fits
#   Claim: the emitted tracestate value takes at most the output budget, in
#     UTF-8 octets.
#   Requirement: spec #1, "Default emitted tracestate budget is 512 bytes".
#   Why: this is the promise the output budget makes, stated on the text that
#     is sent.
#   Proof: Laws.emit_fits, from truncate_fits and state_size.
law emit_fits:
  for +limits: Trace.Limits
  for outgoing: Trace.OutgoingContext
  {Nat.is_le(Trace.Utf8.length(Trace.Emission.tracestate(Trace.OutgoingContext.emit(limits, outgoing))),
    Trace.Limits.tracestate_output(limits)) == True{} : Bool}

# LAW emit_accepted
#   Claim: the same limits parse the emitted tracestate value back into the
#     state that was emitted.
#   Requirement: spec #1, "a tracestate input budget no smaller than its
#     output budget, so a configuration accepts its own normalized emitted
#     representation".
#   Why: two participants with the same configuration always accept each
#     other's state; this is why Limits requires the input budget to be at
#     least the output budget.
#   Proof: Laws.emit_accepted, via proofs/emit.bend, from emit_fits,
#     limits_bounds and state_roundtrip.
law emit_accepted:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  {Trace.TraceState.parse(limits, Trace.Emission.tracestate(Trace.OutgoingContext.emit(limits, outgoing))) ==
    Done{Trace.Truncation.kept(Trace.TraceState.truncate(limits, Trace.OutgoingContext.state(outgoing)))} :
    Result<&2, &2, Trace.StateError, Trace.TraceState>}

# 12. Extraction
# ==============
#
# Context.extract reads the trace context of a received message from its
# carrier: the message's fields in their order, each a name and a value (W3C
# Level 2, sections 3.2, 3.3 and 4.1; spec #1, "Wire values, carriers and
# emission"). Field names are compared without regard to ASCII case. A single
# traceparent field is read by TraceParent.read: version 00 strictly, version
# ff never, and any later version by its known prefix. When the traceparent is
# accepted, the message gives an incoming context with the state of its
# tracestate fields; otherwise the base context the caller passed is kept and
# the tracestate is not read. These laws state that policy for every carrier,
# value, state and limits, and what an incoming context built from parts
# with IncomingContext.from_remote keeps (spec #41). The corpus,
# tests/EXTRACT.bend, covers the pinned W3C harness's inputs, the offsets in
# diagnostics, exact budget boundaries, whitespace inside unknown fields and
# names that differ from the field names by other than ASCII case.

# The values of the fields of `carrier` whose name, with its ASCII letters in
# lowercase (Base's String.to_lower), is `name`, in their order. This is the
# file's own statement of the rule of W3C 3.2.1 and 3.3.1; the package
# compares names one character at a time instead.
def named(+name: String, carrier: List<&2, Trace.Header>) -> List<&2, String>:
  match carrier:
    case Nil{}:
      Nil{}
    case Con{+header, +rest}:
      Bool.pick(List<&2, String>, String.eq(String.to_lower(Trace.Header.name(header)), name),
        Con{Trace.Header.value(header), named(name, rest)}, named(name, rest))

# What extraction reports about tracestate fields it does not read: absent
# when there are none, ignored when there are some. Their text plays no part.
def ignored(fields: List<&2, String>) -> Trace.StateOutcome:
  match fields:
    case Nil{}:
      Trace.StateAbsent{}
    case Con{field, rest}:
      Trace.StateIgnored{}

# LAW extract_absent
#   Claim: a message without a traceparent field keeps the base context, and
#     its tracestate fields are not read: only whether there are any is
#     reported.
#   Requirement: W3C Level 2, section 3.3: "If the vendor failed to parse
#     traceparent, it MUST NOT attempt to parse tracestate"; section 4.1.1 on
#     a tracestate received without a traceparent. Spec #1: "absent or
#     invalid traceparent preserves the supplied base context and reports the
#     outcome. Do not interpret tracestate without eligible traceparent" (user
#     story 25).
#   Why: extraction must never erase a context the application already holds,
#     and a tracestate without its traceparent must not be attached to it.
#   Reading: named and ignored are defined just above. The conclusion depends
#     on the tracestate fields only through whether there are any.
#   Proof: Laws.extract_absent, via proofs/extract.bend.
law extract_absent:
  for +limits: Trace.Limits
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for absent: {named("traceparent", carrier) == Nil{} : List<&2, String>}
  {Trace.Context.extract(limits, carrier, base) ==
    Trace.Extraction{base, Trace.TraceParentAbsent{}, ignored(named("tracestate", carrier))} : Trace.Extraction}

# LAW extract_repeated
#   Claim: a message with more than one traceparent field is refused with
#     RepeatedTraceParent, whatever the values; the base is kept and the
#     tracestate is not read.
#   Requirement: spec #1, "Multiple traceparent fields are invalid" (user
#     story 15); the pinned harness's test_traceparent_duplicated.
#   Why: choosing one of several parents would continue a trace the sender may
#     not have meant.
#   Reading: `repeated` says that the carrier has at least two traceparent
#     fields, `first` and `second`, and possibly `more`.
#   Proof: Laws.extract_repeated, via proofs/extract.bend.
law extract_repeated:
  for +limits: Trace.Limits
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for first: String
  for second: String
  for more: List<&2, String>
  for repeated: {named("traceparent", carrier) == Con{first, Con{second, more}} : List<&2, String>}
  {Trace.Context.extract(limits, carrier, base) == Trace.Extraction{base,
    Trace.TraceParentRejected{Trace.RepeatedTraceParent{}}, ignored(named("tracestate", carrier))} : Trace.Extraction}

# LAW extract_refused
#   Claim: a message whose only traceparent value TraceParent.read refuses
#     keeps the base context and reports the reason, and its tracestate is not
#     read.
#   Requirement: W3C Level 2, sections 3.3 and 4.1.2; spec #1, as for
#     extract_absent.
#   Why: an invalid header must neither erase the application's context nor
#     smuggle in the tracestate that came with it.
#   Reading: the laws on TraceParent.read below say which values it refuses.
#   Proof: Laws.extract_refused, via proofs/extract.bend.
law extract_refused:
  for +limits: Trace.Limits
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for +value: String
  for error: Trace.TraceParentError
  for single: {named("traceparent", carrier) == Con{value, Nil{}} : List<&2, String>}
  for refused: {Trace.TraceParent.read(limits, value) == Fail{error} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}
  {Trace.Context.extract(limits, carrier, base) ==
    Trace.Extraction{base, Trace.TraceParentRejected{error}, ignored(named("tracestate", carrier))} : Trace.Extraction}

# The text without the optional whitespace at its start: spaces and
# horizontal tabs.
def ows_start(text: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{+first, +rest}:
      Bool.pick(String, Bool.or(Char.is_eq(first, ' '), Char.is_eq(first, '\t')), ows_start(rest), SCon{first, rest})

# The text without the optional whitespace at its end: a character stays
# unless it and every character after it are whitespace (all_ows, section
# 10).
def ows_end(text: String) -> String:
  match text:
    case SNil{}:
      SNil{}
    case SCon{+first, +rest}:
      Bool.pick(String, all_ows(SCon{first, rest}), SNil{}, SCon{first, ows_end(rest)})

# The text without the optional whitespace around it. RFC 9110, section 5.5:
# "A field value does not include leading or trailing whitespace".
def trimmed(text: String) -> String:
  ows_end(ows_start(text))

# The extraction of a message whose tracestate fields were parsed, given the
# result of parsing them (see `accepted`).
def accepted.parsed(parsed: Result<&2, &2, Trace.StateError, Trace.TraceState>, remote: Trace.RemoteContext,
  text: String, fields: List<&2, String>) -> Trace.Extraction:
  match parsed:
    case Fail{error}:
      Trace.Extraction{Some{Trace.IncomingBase{Trace.IncomingContext{remote, Trace.TraceState.empty(), None{}}}},
        Trace.TraceParentAccepted{}, Trace.StateDiscarded{error}}
    case Done{state}:
      Trace.Extraction{Some{Trace.IncomingBase{Trace.IncomingContext{remote, state,
        Some{Trace.ReceivedPair{text, fields}}}}}, Trace.TraceParentAccepted{}, Trace.StateAccepted{}}

# The extraction of a message whose traceparent was accepted: `remote` is the
# sender's operation, `text` the traceparent value kept for forwarding and
# `fields` the values of the tracestate fields. Without a tracestate field
# the context has no state and the pair keeps no tracestate. With fields,
# they are parsed together in arrival order: a state they parse to is kept
# with the pair, and when they are refused the context has no state, the
# discard is reported with its error, and no pair is kept, since the pair was
# not accepted whole. This is the case split of spec #1's policy for an
# accepted message; the parsing itself is TraceState.parse_fields, which
# section 10 states.
def accepted(+limits: Trace.Limits, remote: Trace.RemoteContext, text: String, +fields: List<&2, String>) ->
  Trace.Extraction:
  match fields:
    case Nil{}:
      Trace.Extraction{Some{Trace.IncomingBase{Trace.IncomingContext{remote, Trace.TraceState.empty(),
        Some{Trace.ReceivedPair{text, Nil{}}}}}}, Trace.TraceParentAccepted{}, Trace.StateAbsent{}}
    case Con{field, rest}:
      accepted.parsed(Trace.TraceState.parse_fields(limits, Con{field, rest}), remote, text, Con{field, rest})

# LAW extract_read
#   Claim: a message whose only traceparent value TraceParent.read accepts
#     gives an incoming context: the sender's operation from the value's
#     known fields; the state its tracestate fields parse to, together, in
#     arrival order, or no state when there is none or when they are refused,
#     the refusal being reported; and, unless the state was refused, the
#     received pair: the value without the whitespace around it and the
#     tracestate fields exactly as they came. The base plays no part.
#   Requirement: W3C Level 2, section 3.3: "failure to parse tracestate MUST
#     NOT affect the parsing of traceparent"; section 3.3.2: multiple
#     tracestate fields "MUST be combined". Spec #1: "Valid incoming
#     traceparent yields remote context", "Other syntax or member-limit
#     errors discard the entire tracestate while keeping a valid
#     traceparent" and "Distinguish remote context, local context and the
#     accepted original header pair needed for transparent forwarding".
#   Why: a valid traceparent is never lost to an invalid tracestate; the
#     pair kept for forwarding is exactly what was accepted, and only a pair
#     accepted whole can be forwarded (section 13).
#   Reading: `accepted` and `trimmed` are defined just above.
#     RemoteContext.from_traceparent keeps the sampled and random-trace-id
#     flags (received_flags) and drops the reserved bits.
#   Proof: Laws.extract_read, via proofs/extract.bend.
law extract_read:
  for +limits: Trace.Limits
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for +value: String
  for +known: Trace.TraceParentV00
  for single: {named("traceparent", carrier) == Con{value, Nil{}} : List<&2, String>}
  for read: {Trace.TraceParent.read(limits, value) == Done{known} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}
  {Trace.Context.extract(limits, carrier, base) == accepted(limits, Trace.RemoteContext.from_traceparent(known),
    trimmed(value), named("tracestate", carrier)) : Trace.Extraction}

# The operation of an incoming context, if there is one.
def sender.of(incoming: Maybe<&2, Trace.IncomingContext>) -> Maybe<&2, Trace.RemoteContext>:
  match incoming:
    case None{}:
      None{}
    case Some{context}:
      Some{Trace.IncomingContext.context(context)}

# The sender's operation of an extraction whose message's own traceparent was
# accepted, None{} otherwise. It observes the extraction through the public
# accessor Extraction.incoming; it restates no rule.
def sender(extraction: Trace.Extraction) -> Maybe<&2, Trace.RemoteContext>:
  sender.of(Trace.Extraction.incoming(extraction))

# LAW state_independent
#   Claim: two messages with the same traceparent fields give the same
#     traceparent outcome and the same sender's operation, whatever their
#     tracestate fields.
#   Requirement: spec #1, formal proof obligations: "Discarding invalid state
#     does not change extraction of a valid traceparent" (user story 24). W3C
#     Level 2, section 3.3: "failure to parse tracestate MUST NOT affect the
#     parsing of traceparent".
#   Why: a vendor's broken or oversized tracestate never costs the trace its
#     continuity.
#   Reading: `same` says that both carriers have the same traceparent values
#     in the same order; their other fields, tracestate included, may differ.
#     sender, defined just above, gives the operation of the incoming context.
#   Proof: Laws.state_independent, via proofs/extract.bend.
law state_independent:
  for +limits: Trace.Limits
  for +first: List<&2, Trace.Header>
  for +second: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for same: {named("traceparent", first) == named("traceparent", second) : List<&2, String>}
  {Trace.Extraction.parent(Trace.Context.extract(limits, first, base)) ==
    Trace.Extraction.parent(Trace.Context.extract(limits, second, base)) : Trace.TraceParentOutcome} &
  {sender(Trace.Context.extract(limits, first, base)) == sender(Trace.Context.extract(limits, second, base)) :
    Maybe<&2, Trace.RemoteContext>}

# LAW received_bounds
#   Claim: the pair an incoming context keeps fits the input budgets it was
#     accepted with: the traceparent value within the traceparent budget, and
#     the tracestate fields, joined by commas, within the tracestate budget.
#   Requirement: ticket #9, "Retain bounded original-pair information needed
#     for eligible intact forwarding"; spec #1, "Default input budgets are 32
#     KiB per traceparent value and 32 KiB for the combined tracestate value".
#   Why: what is kept for forwarding (section 13) is bounded by the
#     configuration, whatever the message held.
#   Reading: `extracted` says that the message's traceparent was accepted as
#     `incoming`, and `kept` that the incoming context kept `pair`.
#   Proof: Laws.received_bounds, via proofs/extract.bend.
law received_bounds:
  for +limits: Trace.Limits
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for +incoming: Trace.IncomingContext
  for +pair: Trace.ReceivedPair
  for extracted: {Trace.Extraction.incoming(Trace.Context.extract(limits, carrier, base)) == Some{incoming} :
    Maybe<&2, Trace.IncomingContext>}
  for kept: {Trace.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, Trace.ReceivedPair>}
  {Nat.is_le(Trace.Utf8.length(Trace.ReceivedPair.traceparent(pair)), Trace.Limits.traceparent_input(limits)) ==
    True{} : Bool} &
  {Nat.is_le(Trace.Utf8.length(String.join(Trace.ReceivedPair.tracestate(pair), ",")),
    Trace.Limits.tracestate_input(limits)) == True{} : Bool}

# LAW incoming_from_remote
#   Claim: IncomingContext.from_remote keeps exactly the remote context and
#     the tracestate it is given, and keeps no received pair.
#   Requirement: spec #41, "Contexts from parts": IncomingContext.from_remote
#     builds an incoming context with no received pair (user stories 19 and
#     20).
#   Why: an OpenTelemetry SDK gives its remote span contexts one shape,
#     whatever format they came from. A context built from parts arrived in
#     no message, so a received pair would claim fields that nobody sent.
#   Proof: Laws.incoming_from_remote, by computation.
law incoming_from_remote:
  for context: Trace.RemoteContext
  for state: Trace.TraceState
  {Trace.IncomingContext.context(Trace.IncomingContext.from_remote(context, state)) == context :
    Trace.RemoteContext} &
  {Trace.IncomingContext.state(Trace.IncomingContext.from_remote(context, state)) == state : Trace.TraceState} &
  {Trace.IncomingContext.received(Trace.IncomingContext.from_remote(context, state)) == None{} :
    Maybe<&2, Trace.ReceivedPair>}

# Whether the text has no comma, space or horizontal tab.
def plain(+text: String) -> Bool:
  Bool.and(lacks(',', text), Bool.and(lacks(' ', text), lacks('\t', text)))

# LAW read_v00
#   Claim: the text of every strict v00 value is read as that value, with any
#     optional whitespace around it, whenever the whole value fits the
#     traceparent input budget.
#   Requirement: W3C Level 2, sections 3.2.2 and 4.1.2: a vendor that
#     "supports the version number" validates the value. Spec #1: "Reuse the
#     strict v00 codec" and "Count UTF-8 octets, including whitespace". RFC
#     9110, section 5.5; the pinned harness's test_traceparent_ows_handling.
#   Why: a participant continues every valid version 00 header it receives,
#     whether or not its host removed the whitespace around it.
#   Reading: the result keeps the whole flag byte of the value;
#     RemoteContext.from_traceparent then keeps its known flags
#     (received_flags). `fits` measures the whitespace too, as the package
#     does.
#   Proof: Laws.read_v00, via proofs/extract.bend.
law read_v00:
  for +limits: Trace.Limits
  for +known: Trace.TraceParentV00
  for +before: String
  for +after: String
  for before_ows: {all_ows(before) == True{} : Bool}
  for after_ows: {all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(before ++ Trace.TraceParentV00.format(known) ++ after),
    Trace.Limits.traceparent_input(limits)) == True{} : Bool}
  {Trace.TraceParent.read(limits, before ++ Trace.TraceParentV00.format(known) ++ after) == Done{known} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# LAW read_v00_exact
#   Claim: the text of a strict v00 value followed by more characters is
#     refused: version 00 has no fields after its flags.
#   Requirement: spec #1, "Keep strict-v00 parsing separate from the
#     future-version known-prefix rule"; W3C Level 2, section 3.2.2, where
#     the version-format of version 00 ends with the flags; the pinned
#     harness's test_traceparent_version_0x00.
#   Why: a 00 value with a suffix is malformed, not a newer format. Accepting
#     it would apply the rule of later versions to the one version whose
#     format is known in full.
#   Reading: Result.is_done(...) == False{} says that reading fails. `more`
#     has no comma, which would make the value repeated fields (read_comma),
#     and no whitespace, which could be removed as optional whitespace.
#   Scope: the corpus checks the error, TrailingInput.
#   Proof: Laws.read_v00_exact, via proofs/extract.bend: by law inverse, a
#     value read back would format to its 55 characters alone.
law read_v00_exact:
  for +limits: Trace.Limits
  for +known: Trace.TraceParentV00
  for +more: String
  for nonempty: {String.is_empty(more) == False{} : Bool}
  for plain_more: {plain(more) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(Trace.TraceParentV00.format(known) ++ more),
    Trace.Limits.traceparent_input(limits)) == True{} : Bool}
  {Result.is_done(&2, &2, Trace.TraceParentError, Trace.TraceParentV00,
    Trace.TraceParent.read(limits, Trace.TraceParentV00.format(known) ++ more)) == False{} : Bool}

# Whether two version digits name a version after 00 other than the
# forbidden ff (W3C Level 2, section 3.2.2.1).
def later_version(+version: Digits.Digits(2n)) -> Bool:
  Bool.and(Bool.not(String.eq(Digits.Digits.to_string(2n, version), "00")),
    Bool.not(String.eq(Digits.Digits.to_string(2n, version), "ff")))

# Whether the text has no control character other than a horizontal tab,
# which no field value may hold (RFC 9110, section 5.5): the characters
# Trace.Text.is_control names, U+0000 to U+0008, U+000A to U+001F and
# U+007F.
def clean(text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{first, rest}:
      Bool.and(Bool.not(Trace.Text.is_control(first)), clean(rest))

# Whether `text` may follow the flags of a later version in these laws:
# nothing, or a dash and characters other than a comma, a space, a tab or a
# control character.
def unknown_fields(text: String) -> Bool:
  match text:
    case SNil{}:
      True{}
    case SCon{+first, +rest}:
      Bool.and(Char.is_eq(first, '-'), Bool.and(plain(rest), clean(rest)))

# The text of a value of version `version` with the known fields of `known`,
# from its first dash, followed by `unknown`.
def future(+version: Digits.Digits(2n), known: Trace.TraceParentV00, unknown: String) -> String:
  Digits.Digits.to_string(2n, version) ++ String.drop(Trace.TraceParentV00.format(known), 2n) ++ unknown

# LAW read_future
#   Claim: a value of a later version, 01 to fe, is read by its known prefix:
#     its trace ID, parent ID and flags are read as those of version 00, and
#     what follows the flags after a dash is not read. Optional whitespace
#     around the value makes no difference.
#   Requirement: W3C Level 2, section 3.2.4: "If a higher version is
#     detected, the implementation SHOULD try to parse it" and "Vendors MUST
#     NOT parse or assume anything about unknown fields"; section 4.1.2. Spec
#     #1: "For 01 through fe, use the valid known prefix, followed by end of
#     value or a dash introducing an opaque extension".
#   Why: a participant keeps continuing the traces of newer participants from
#     the fields it knows.
#   Reading: `future`, `later_version` and `unknown_fields` are defined just
#     above; String.drop(..., 2n) removes the version 00 from the text of
#     `known`.
#   Scope: unknown fields holding whitespace or other characters are covered
#     by the corpus; a comma is refused (read_comma), and so is a control
#     character, with ControlCharacter at its offset (corpus).
#   Proof: Laws.read_future, via proofs/extract.bend.
law read_future:
  for +limits: Trace.Limits
  for +version: Digits.Digits(2n)
  for +known: Trace.TraceParentV00
  for +unknown: String
  for +before: String
  for +after: String
  for later: {later_version(version) == True{} : Bool}
  for plain_unknown: {unknown_fields(unknown) == True{} : Bool}
  for before_ows: {all_ows(before) == True{} : Bool}
  for after_ows: {all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(before ++ future(version, known, unknown) ++ after),
    Trace.Limits.traceparent_input(limits)) == True{} : Bool}
  {Trace.TraceParent.read(limits, before ++ future(version, known, unknown) ++ after) == Done{known} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# LAW read_ff
#   Claim: a value of version ff is refused with ForbiddenVersion, whatever
#     follows.
#   Requirement: W3C Level 2, section 3.2.2.1: "Version 255 ("ff") is
#     invalid"; spec #1, "Participating extraction rejects version ff"; the
#     pinned harness's test_traceparent_version_0xff.
#   Why: ff is reserved as invalid, so no participant may read it as a later
#     version.
#   Reading: `rest` has no comma, space or tab, as in read_v00_exact.
#   Proof: Laws.read_ff, via proofs/extract.bend.
law read_ff:
  for +limits: Trace.Limits
  for +rest: String
  for plain_rest: {plain(rest) == True{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length("ff" ++ rest), Trace.Limits.traceparent_input(limits)) == True{} : Bool}
  {Trace.TraceParent.read(limits, "ff" ++ rest) == Fail{Trace.InvalidTraceParent{Trace.ForbiddenVersion{}}} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# LAW read_comma
#   Claim: a value that fits the budget and contains a comma is refused with
#     RepeatedTraceParent, whatever else it contains.
#   Requirement: spec #1, "Multiple traceparent fields are invalid". RFC 9110,
#     section 5.3: a recipient may combine repeated fields into one value,
#     separated by commas. No traceparent of version 00 contains a comma.
#   Why: a host that joined two traceparent fields must not make extraction
#     choose one of them (see extract_repeated).
#   Reading: lacks, defined in section 8, is False when the value has a
#     comma.
#   Proof: Laws.read_comma, via proofs/extract.bend.
law read_comma:
  for +limits: Trace.Limits
  for +value: String
  for joined: {lacks(',', value) == False{} : Bool}
  for fits: {Nat.is_le(Trace.Utf8.length(value), Trace.Limits.traceparent_input(limits)) == True{} : Bool}
  {Trace.TraceParent.read(limits, value) == Fail{Trace.RepeatedTraceParent{}} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# LAW read_over_budget
#   Claim: a traceparent value whose UTF-8 octets, whitespace included,
#     exceed the traceparent input budget is refused with TraceParentTooLarge,
#     whatever it contains.
#   Requirement: spec #1, "Default input budgets are 32 KiB per traceparent
#     value ... Count UTF-8 octets, including whitespace and extension data"
#     and "Stop bounded processing once the relevant budget is exceeded".
#   Why: a received header must not make a service do unbounded work, and the
#     outcome must not depend on where in an oversized value a problem is.
#   Scope: that measuring stops at the first character past the budget
#     follows from Utf8.left, as for tracestate; the corpus refuses a
#     mebibyte value.
#   Proof: Laws.read_over_budget, via proofs/extract.bend.
law read_over_budget:
  for +limits: Trace.Limits
  for +value: String
  for larger: {Nat.is_le(Trace.Utf8.length(value), Trace.Limits.traceparent_input(limits)) == False{} : Bool}
  {Trace.TraceParent.read(limits, value) == Fail{Trace.TraceParentTooLarge{}} :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# LAW read_within_budgets
#   Claim: for a value that fits two traceparent input budgets, reading with
#     either gives the same result.
#   Requirement: spec #1: budgets only refuse input, and the traceparent
#     budget is independent of the tracestate budgets.
#   Why: with read_over_budget, the traceparent budget either refuses a value
#     or has no effect, and the tracestate budgets never change how a
#     traceparent is read.
#   Proof: Laws.read_within_budgets, via proofs/extract.bend.
law read_within_budgets:
  for +first: Trace.Limits
  for +second: Trace.Limits
  for +value: String
  for first_fits: {Nat.is_le(Trace.Utf8.length(value), Trace.Limits.traceparent_input(first)) == True{} : Bool}
  for second_fits: {Nat.is_le(Trace.Utf8.length(value), Trace.Limits.traceparent_input(second)) == True{} : Bool}
  {Trace.TraceParent.read(first, value) == Trace.TraceParent.read(second, value) :
    Result<&2, &2, Trace.TraceParentError, Trace.TraceParentV00>}

# 13. Injection and forwarding
# ============================
#
# Context.inject writes the context of an operation of this participant into
# the carrier of an outgoing message, and Context.clear removes the context
# fields of a message sent without context (spec #1, "Participant
# injection"). Context.forward sends a received context on unchanged (W3C
# Level 2, section 3.4, "Unmodified header propagation"). All three remove
# every old traceparent and tracestate field, whatever the ASCII case of its
# name, and keep the other fields in their order. These laws state the
# carriers written, the names that injection writes, which Context.field_names
# publishes (spec #41, "Context field names"), the diagnostics apart from the
# carriers, and what a receiver extracts from them. The corpus,
# tests/INJECT.bend, covers names in every case, empty and truncated states,
# all flags, a later version with unknown fields, spec #1's 600-octet state,
# pairs built directly and carriers of 100000 fields.

# Whether a field name, with its ASCII letters in lowercase, is "traceparent"
# or "tracestate".
def context_name(+name: String) -> Bool:
  Bool.or(String.eq(String.to_lower(name), "traceparent"), String.eq(String.to_lower(name), "tracestate"))

# The fields of `carrier` that are not context fields, in their order.
def unrelated(carrier: List<&2, Trace.Header>) -> List<&2, Trace.Header>:
  match carrier:
    case Nil{}:
      Nil{}
    case Con{+header, +rest}:
      Bool.pick(List<&2, Trace.Header>, context_name(Trace.Header.name(header)), unrelated(rest),
        Con{header, unrelated(rest)})

# The context fields written for a traceparent value and a tracestate value,
# with lowercase names: the tracestate field only when its value is not
# empty.
def written(traceparent: String, tracestate: String) -> List<&2, Trace.Header>:
  match tracestate:
    case SNil{}:
      Con{Trace.Header{"traceparent", traceparent}, Nil{}}
    case SCon{first, rest}:
      Con{Trace.Header{"traceparent", traceparent}, Con{Trace.Header{"tracestate", SCon{first, rest}}, Nil{}}}

# LAW clear_carrier
#   Claim: cleanup removes every traceparent and tracestate field, whatever
#     the case of its name, and keeps every other field in its order.
#   Requirement: spec #1, "Provide explicit context-field cleanup for the
#     no-context path, including differently cased old fields" and "preserve
#     unrelated headers and their relative order".
#   Why: a reused request container must not send a stale context, and
#     tracing must not change the application's fields.
#   Reading: unrelated is defined just above.
#   Proof: Laws.clear_carrier, via proofs/inject.bend.
law clear_carrier:
  for +carrier: List<&2, Trace.Header>
  {Trace.Context.clear(carrier) == unrelated(carrier) : List<&2, Trace.Header>}

# LAW inject_carrier
#   Claim: injection writes the carrier's other fields, in their order,
#     followed by the emitted traceparent and, unless it is empty, the
#     emitted tracestate, with lowercase names.
#   Requirement: spec #1, "Replace all existing traceparent/tracestate
#     occurrences, write lowercase names and preserve unrelated headers and
#     their relative order. Omit empty tracestate"; W3C Level 2, sections
#     3.2.1 and 3.3.1: names SHOULD be sent in lowercase.
#   Why: exactly one context goes out and the application's fields are
#     untouched. The laws of section 11 say what the emitted values are:
#     version 00 with only the known flags (emit_traceparent), and the state
#     truncated to the output budget (emit_tracestate).
#   Reading: unrelated and written are defined above.
#   Proof: Laws.inject_carrier, via proofs/inject.bend.
law inject_carrier:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  for +carrier: List<&2, Trace.Header>
  {Trace.Injection.carrier(Trace.Context.inject(limits, outgoing, carrier)) ==
    List.append(&2, Trace.Header, unrelated(carrier),
      written(Trace.Emission.traceparent(Trace.OutgoingContext.emit(limits, outgoing)),
        Trace.Emission.tracestate(Trace.OutgoingContext.emit(limits, outgoing)))) : List<&2, Trace.Header>}

# The names of the fields of a carrier, in their order.
def names(carrier: List<&2, Trace.Header>) -> List<&2, String>:
  match carrier:
    case Nil{}:
      Nil{}
    case Con{header, rest}:
      Con{Trace.Header.name(header), names(rest)}

# The names, among `published`, of the fields that injection writes for an
# emitted tracestate value: all of them, or only the first when the value is
# empty, since an empty tracestate is not written.
def written_names(published: List<&2, String>, tracestate: String) -> List<&2, String>:
  match tracestate:
    case SNil{}:
      List.take(&2, String, published, 1n)
    case SCon{first, rest}:
      published

# LAW inject_names
#   Claim: injection writes its fields under the published names of the
#     context fields, in their order: after the carrier's other fields, a
#     field named by the first published name, then one named by the second
#     unless the emitted tracestate is empty.
#   Requirement: spec #41, "Context field names": "A public list gives the
#     names of the context fields as injection writes them: traceparent, then
#     tracestate" (user stories 22 and 23).
#   Why: a propagator lists the fields that it writes, as OpenTelemetry's
#     propagators do, so that a carrier can be cleared of them before it is
#     reused, and an SDK's propagator that writes the emitted values through
#     OpenTelemetry's setter writes them under these names. Both must be the
#     names that injection writes.
#   Reading: names and written_names are defined just above, and unrelated at
#     the start of this section. inject_carrier gives the names themselves,
#     traceparent and tracestate in lowercase, so the published list is
#     exactly those two names.
#   Proof: Laws.inject_names, via proofs/inject.bend, from inject_carrier.
law inject_names:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  for +carrier: List<&2, Trace.Header>
  {names(Trace.Injection.carrier(Trace.Context.inject(limits, outgoing, carrier))) ==
    List.append(&2, String, names(unrelated(carrier)), written_names(Trace.Context.field_names(),
      Trace.Emission.tracestate(Trace.OutgoingContext.emit(limits, outgoing)))) : List<&2, String>}

# LAW inject_dropped
#   Claim: the keys an injection reports dropped are those of the emission:
#     the diagnostics of truncation, kept apart from the carrier.
#   Requirement: spec #1, "Diagnostic metadata is tested separately, not
#     silently included in this equality".
#   Why: a service learns which vendors' entries were not sent without
#     reading the carrier.
#   Proof: Laws.inject_dropped, via proofs/inject.bend.
law inject_dropped:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  for carrier: List<&2, Trace.Header>
  {Trace.Injection.dropped(Trace.Context.inject(limits, outgoing, carrier)) ==
    Trace.Emission.dropped(Trace.OutgoingContext.emit(limits, outgoing)) : List<&2, Trace.StateKey>}

# LAW inject_idempotent
#   Claim: injecting a context into the carrier that an injection of it
#     wrote gives that carrier again.
#   Requirement: spec #1, "Injection is idempotent on the resulting carrier
#     for a fixed context/configuration and preserves unrelated fields and
#     their relative order".
#   Why: a client may inject into a container it reuses, retries a request
#     with, or injected into already, without accumulating fields.
#   Proof: Laws.inject_idempotent, via proofs/inject.bend, from
#     inject_carrier.
law inject_idempotent:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  for +carrier: List<&2, Trace.Header>
  {Trace.Injection.carrier(Trace.Context.inject(limits, outgoing,
    Trace.Injection.carrier(Trace.Context.inject(limits, outgoing, carrier)))) ==
    Trace.Injection.carrier(Trace.Context.inject(limits, outgoing, carrier)) : List<&2, Trace.Header>}

# The remotely observable projection of a local context: its trace ID, with
# its randomness assertion, its span ID and its sampled indication, as the
# remote context a receiver would hold.
def projection(+context: Trace.LocalContext) -> Trace.RemoteContext:
  Trace.RemoteContext{Trace.LocalContext.trace_id(context), Trace.LocalContext.span_id(context),
    Trace.LocalContext.is_sampled(context)}

# The entries of the state of an incoming context, if there is one.
def received_entries.of(incoming: Maybe<&2, Trace.IncomingContext>) -> List<&2, Trace.StateEntry>:
  match incoming:
    case None{}:
      Nil{}
    case Some{context}:
      Trace.TraceState.entries(Trace.IncomingContext.state(context))

# The entries of the state that an extraction's own context received; none
# when the message's traceparent was not accepted.
def received_entries(extraction: Trace.Extraction) -> List<&2, Trace.StateEntry>:
  received_entries.of(Trace.Extraction.incoming(extraction))

# The extraction of the carrier that an injection wrote, with the same
# limits.
def reinjected(+limits: Trace.Limits, outgoing: Trace.OutgoingContext, carrier: List<&2, Trace.Header>,
  base: Maybe<&2, Trace.BaseContext>) -> Trace.Extraction:
  Trace.Context.extract(limits, Trace.Injection.carrier(Trace.Context.inject(limits, outgoing, carrier)), base)

# LAW inject_extracted
#   Claim: a receiver that extracts, with the same limits, a carrier that an
#     injection wrote accepts its traceparent, finds the projection of the
#     injected local context as the sender's operation, and receives the
#     entries of the injected state truncated to the output budget.
#   Requirement: spec #1, "Extraction after participant injection recovers
#     the normalized remotely observable projection of the local context,
#     including emitted flags and truncated state. It does not promise
#     original-wire equality across normalization".
#   Why: this is the promise of propagation between two services that use
#     the package: the next one continues exactly the operation that sent the
#     request, with the state it sent.
#   Reading: projection, received_entries and reinjected are defined just
#     above; sender is defined in section 12. The base plays no part: the
#     message's own context replaces it.
#   Proof: Laws.inject_extracted, via proofs/inject.bend.
law inject_extracted:
  for +limits: Trace.Limits
  for +outgoing: Trace.OutgoingContext
  for +carrier: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  {Trace.Extraction.parent(reinjected(limits, outgoing, carrier, base)) == Trace.TraceParentAccepted{} :
    Trace.TraceParentOutcome} &
  {sender(reinjected(limits, outgoing, carrier, base)) == Some{projection(Trace.OutgoingContext.context(outgoing))} :
    Maybe<&2, Trace.RemoteContext>} &
  {received_entries(reinjected(limits, outgoing, carrier, base)) == Trace.TraceState.entries(
    Trace.Truncation.kept(Trace.TraceState.truncate(limits, Trace.OutgoingContext.state(outgoing)))) :
    List<&2, Trace.StateEntry>}

# LAW forward_carrier
#   Claim: when forwarding succeeds, it writes the carrier's other fields, in
#     their order, followed by the received traceparent value and the
#     received tracestate fields joined by commas, left out when empty:
#     exactly the accepted text, with no normalization.
#   Requirement: spec #1, "Forwarding preserves the accepted original
#     context pair's field values without normalizing flags, downgrading
#     versions or editing/truncating tracestate"; W3C Level 2, section 3.4,
#     and section 3.3.2: tracestate "SHOULD be sent as a single field when
#     possible".
#   Why: a service that does not take part in a trace passes it on as the
#     sender wrote it, a later version and reserved flag bits included.
#   Reading: `kept` names the received pair of the incoming context, and
#     `done` says that forwarding succeeded with `forwarded`.
#   Proof: Laws.forward_carrier, via proofs/inject.bend.
law forward_carrier:
  for +limits: Trace.Limits
  for +incoming: Trace.IncomingContext
  for +carrier: List<&2, Trace.Header>
  for +pair: Trace.ReceivedPair
  for +forwarded: List<&2, Trace.Header>
  for kept: {Trace.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, Trace.ReceivedPair>}
  for done: {Trace.Context.forward(limits, incoming, carrier) == Done{forwarded} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}
  {forwarded == List.append(&2, Trace.Header, unrelated(carrier), written(Trace.ReceivedPair.traceparent(pair),
    String.join(Trace.ReceivedPair.tracestate(pair), ","))) : List<&2, Trace.Header>}

# LAW forward_nothing
#   Claim: a context that keeps no received pair is not forwarded: forwarding
#     fails with NothingToForward.
#   Requirement: spec #1: the convenience path "may forward only an entirely
#     accepted original pair".
#   Why: a context whose tracestate was discarded cannot be sent on
#     unchanged, and sending its traceparent without that state would edit
#     the pair (W3C 3.4).
#   Proof: Laws.forward_nothing, via proofs/inject.bend.
law forward_nothing:
  for +limits: Trace.Limits
  for +incoming: Trace.IncomingContext
  for +carrier: List<&2, Trace.Header>
  for none: {Trace.IncomingContext.received(incoming) == None{} : Maybe<&2, Trace.ReceivedPair>}
  {Trace.Context.forward(limits, incoming, carrier) == Fail{Trace.NothingToForward{}} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}

# LAW forward_from_parts
#   Claim: an incoming context built from parts is not forwarded: forwarding
#     fails with NothingToForward, whatever its remote context, its
#     tracestate, the limits and the carrier.
#   Requirement: spec #41, "Forwarding a remote context": without a received
#     pair nothing is written (user stories 20 and 24); W3C Level 2, section
#     3.4.
#   Why: a relay must never send a traceparent written again from parts,
#     with a tracestate of its choosing; it learns that there is nothing to
#     forward.
#   Reading: with incoming_from_remote (section 12), this is forward_nothing
#     for the contexts that IncomingContext.from_remote builds.
#   Proof: Laws.forward_from_parts, via proofs/inject.bend.
law forward_from_parts:
  for +limits: Trace.Limits
  for context: Trace.RemoteContext
  for state: Trace.TraceState
  for +carrier: List<&2, Trace.Header>
  {Trace.Context.forward(limits, Trace.IncomingContext.from_remote(context, state), carrier) ==
    Fail{Trace.NothingToForward{}} : Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}

# LAW forward_too_large
#   Claim: a received pair whose tracestate fields, joined by commas, exceed
#     the output budget is not forwarded: forwarding fails with
#     ForwardTooLarge, whatever the rest.
#   Requirement: spec #1, "If intact forwarding cannot meet bounds, return a
#     diagnostic so the caller can create a child or handle the failure" and
#     "Never edit or truncate a remote context's tracestate while retaining
#     its traceparent unchanged", including its 600-byte example; W3C Level 2,
#     section 3.4.
#   Why: the caller learns that the pair cannot be sent whole, instead of
#     having its state truncated under the sender's traceparent.
#   Proof: Laws.forward_too_large, via proofs/inject.bend.
law forward_too_large:
  for +limits: Trace.Limits
  for +incoming: Trace.IncomingContext
  for +carrier: List<&2, Trace.Header>
  for +pair: Trace.ReceivedPair
  for kept: {Trace.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, Trace.ReceivedPair>}
  for larger: {Nat.is_le(Trace.Utf8.length(String.join(Trace.ReceivedPair.tracestate(pair), ",")),
    Trace.Limits.tracestate_output(limits)) == False{} : Bool}
  {Trace.Context.forward(limits, incoming, carrier) == Fail{Trace.ForwardTooLarge{}} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}

# LAW forward_extracted
#   Claim: the received pair of a context that extraction accepted is
#     forwarded, with the same limits, whenever its tracestate fits the output
#     budget: the checks that refuse a pair built directly always pass for
#     it.
#   Requirement: ticket #10, "Forward accepted fields without downgrade, flag
#     normalization or state edits; diagnose an intact pair that cannot fit
#     the limits".
#   Why: with forward_too_large, the output budget is the only reason an
#     extracted context cannot be forwarded.
#   Reading: `extracted` says that extracting `received` accepted its
#     traceparent as `incoming`, and `kept` that the pair was kept.
#   Proof: Laws.forward_extracted, via proofs/inject.bend.
law forward_extracted:
  for +limits: Trace.Limits
  for +received: List<&2, Trace.Header>
  for +base: Maybe<&2, Trace.BaseContext>
  for +incoming: Trace.IncomingContext
  for +pair: Trace.ReceivedPair
  for +carrier: List<&2, Trace.Header>
  for extracted: {Trace.Extraction.incoming(Trace.Context.extract(limits, received, base)) == Some{incoming} :
    Maybe<&2, Trace.IncomingContext>}
  for kept: {Trace.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, Trace.ReceivedPair>}
  for fits: {Nat.is_le(Trace.Utf8.length(String.join(Trace.ReceivedPair.tracestate(pair), ",")),
    Trace.Limits.tracestate_output(limits)) == True{} : Bool}
  {Trace.Context.forward(limits, incoming, carrier) == Done{List.append(&2, Trace.Header, unrelated(carrier),
    written(Trace.ReceivedPair.traceparent(pair), String.join(Trace.ReceivedPair.tracestate(pair), ",")))} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}

# LAW forward_idempotent
#   Claim: forwarding a context into the carrier that a forwarding of it
#     wrote gives that carrier again.
#   Requirement: ticket #10, "Prove carrier idempotence"; spec #1, as for
#     inject_idempotent, on the forwarding path.
#   Why: a proxy may forward into a container it reuses without accumulating
#     fields.
#   Proof: Laws.forward_idempotent, via proofs/inject.bend.
law forward_idempotent:
  for +limits: Trace.Limits
  for +incoming: Trace.IncomingContext
  for +carrier: List<&2, Trace.Header>
  for +forwarded: List<&2, Trace.Header>
  for done: {Trace.Context.forward(limits, incoming, carrier) == Done{forwarded} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}
  {Trace.Context.forward(limits, incoming, forwarded) == Done{forwarded} :
    Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>}

# 14. Continuing or starting, and sending
# =======================================
#
# Context.continue_or_start_with gives a service its own operation for a
# received message, and Context.send_with gives each message it sends a
# child of it (spec #1, "Context lifecycle and flags" and "Generation and
# failure contracts"; ticket #11). Like the laws of section 6, these laws
# quantify over every tape a replayed source returns, errors included, and
# over both failure policies. Five of them state each operation's result:
# the outcome of the one generation it performs, or the fallback of a
# service without an operation, turned into a service or a message by the
# rules defined below, which restate the ticket's rules on their own.
# restart_keeps_nothing and send_reports_generated state properties the
# ticket asks for without those rules: a restart keeps nothing of the
# context it replaces, and a message reports a new operation only when one
# was generated for it. With the laws of section 6, they give the
# lifecycle: a usable context is continued by a child that keeps its trace,
# without one a root starts the trace, a boundary restarts it, and each
# message sent gets an operation of its own. Context.continue_or_start_with
# applies the default of new traces, not sampled, itself: it passes root and
# restart generation the indication that its `sampling` resolves from that
# default (spec #41, "Sampling decision when starting a trace").
# Context.send_with generates only children, whose indication its own
# `sampling` resolves from the service's operation. The corpus,
# tests/CONTINUE.bend, covers every case with literal tapes, including source
# failures and exhausted candidates.

# The result a service operation returns under `policy`, as a tape law
# observes it: the unread rest of the tape with the service.
def TapeService(policy: Trace.FailurePolicy) -> Type:
  Tape() & Trace.FailurePolicy.result(policy, Trace.Service)

# The same for a message sent.
def TapeSent(policy: Trace.FailurePolicy) -> Type:
  Tape() & Trace.FailurePolicy.result(policy, Trace.Sent)

# A service under `policy`: itself with Lenient{}; with Strict{}, Done{} of it
# when it has an operation, and Fail{} with the error when it has none.
def service_by(policy: Trace.FailurePolicy, service: Trace.Service) ->
  Trace.FailurePolicy.result(policy, Trace.Service):
  match policy:
    case Trace.Lenient{}:
      service
    case Trace.Strict{}:
      match service:
        case Trace.Operating{origin, outgoing, received}:
          Done{Trace.Operating{origin, outgoing, received}}
        case Trace.Untraced{error, received}:
          Fail{error}

# A message sent under `policy`: itself with Lenient{}; with Strict{}, Done{}
# of it when it carries a new operation, and Fail{} with the error
# otherwise.
def sent_by(policy: Trace.FailurePolicy, sent: Trace.Sent) -> Trace.FailurePolicy.result(policy, Trace.Sent):
  match policy:
    case Trace.Lenient{}:
      sent
    case Trace.Strict{}:
      match sent:
        case Trace.Fresh{operation, injection}:
          Done{Trace.Fresh{operation, injection}}
        case Trace.Forwarded{carrier, error}:
          Fail{error}
        case Trace.NoContext{carrier, error, reason}:
          Fail{error}

# The service that continuing a context gives: the generated child with the
# continued context's state, or no operation with the error. The message's
# incoming context, `received`, is kept either way.
def continued(state: Trace.TraceState, received: Maybe<&2, Trace.IncomingContext>,
  result: Result<&2, &2, Trace.GenerationError, Trace.LocalContext>) -> Trace.Service:
  match result:
    case Fail{error}:
      Trace.Untraced{error, received}
    case Done{context}:
      Trace.Operating{Trace.Continued{}, Trace.OutgoingContext.with_state(context, state), received}

# The service that a new trace gives: the generated operation, as it was
# generated, without state and without a received pair, or no operation with
# the error.
def begun(origin: Trace.Origin, result: Result<&2, &2, Trace.GenerationError, Trace.LocalContext>) ->
  Trace.Service:
  match result:
    case Fail{error}:
      Trace.Untraced{error, None{}}
    case Done{context}:
      Trace.Operating{origin, Trace.OutgoingContext.new(context), None{}}

# The observed result of continuing, from the generation's outcome.
def continuing(+policy: Trace.FailurePolicy, state: Trace.TraceState, received: Maybe<&2, Trace.IncomingContext>,
  outcome: TapeOutcome()) -> TapeService(policy):
  (rest, result) = outcome
  (rest, service_by(policy, continued(state, received, result)))

# The observed result of a new trace, from the generation's outcome.
def starting(+policy: Trace.FailurePolicy, origin: Trace.Origin, outcome: TapeOutcome()) -> TapeService(policy):
  (rest, result) = outcome
  (rest, service_by(policy, begun(origin, result)))

# The context whose trace ID a restart must not reuse: the received context
# of an incoming base, or the operation of an outgoing base as another
# participant receives it (RemoteContext.from_traceparent of its
# traceparent).
def replaced(base: Trace.BaseContext) -> Trace.RemoteContext:
  match base:
    case Trace.IncomingBase{incoming}:
      Trace.IncomingContext.context(incoming)
    case Trace.OutgoingBase{outgoing}:
      Trace.RemoteContext.from_traceparent(Trace.LocalContext.to_traceparent(Trace.OutgoingContext.context(outgoing)))

# The fallback of a forwarding that was tried.
def fallback.forwarded(result: Result<&2, &2, Trace.ForwardError, List<&2, Trace.Header>>,
  error: Trace.GenerationError, carrier: List<&2, Trace.Header>) -> Trace.Sent:
  match result:
    case Done{forwarded}:
      Trace.Forwarded{forwarded, error}
    case Fail{reason}:
      Trace.NoContext{Trace.Context.clear(carrier), error, Trace.ForwardFailed{reason}}

# What a message carries when no operation could be generated (`error`): the
# received pair forwarded unchanged, when the service keeps one and
# Context.forward sends it, and no context fields otherwise.
def fallback(+limits: Trace.Limits, received: Maybe<&2, Trace.IncomingContext>, error: Trace.GenerationError,
  +carrier: List<&2, Trace.Header>) -> Trace.Sent:
  match received:
    case None{}:
      Trace.NoContext{Trace.Context.clear(carrier), error, Trace.NothingKept{}}
    case Some{incoming}:
      fallback.forwarded(Trace.Context.forward(limits, incoming, carrier), error, carrier)

# The message that a generated child of the service's operation gives: the
# child, injected with the service's state, or the fallback.
def child_sent(+limits: Trace.Limits, +outgoing: Trace.OutgoingContext, received: Maybe<&2, Trace.IncomingContext>,
  +carrier: List<&2, Trace.Header>, result: Result<&2, &2, Trace.GenerationError, Trace.LocalContext>) ->
  Trace.Sent:
  match result:
    case Fail{error}:
      fallback(limits, received, error, carrier)
    case Done{+operation}:
      Trace.Fresh{operation, Trace.Context.inject(limits,
        Trace.OutgoingContext.with_state(operation, Trace.OutgoingContext.state(outgoing)), carrier)}

# The observed result of sending, from the generation's outcome.
def sending(+policy: Trace.FailurePolicy, +limits: Trace.Limits, +outgoing: Trace.OutgoingContext,
  received: Maybe<&2, Trace.IncomingContext>, +carrier: List<&2, Trace.Header>, outcome: TapeOutcome()) ->
  TapeSent(policy):
  (rest, result) = outcome
  (rest, sent_by(policy, child_sent(limits, outgoing, received, carrier, result)))

# The context that a generation's outcome created, if any.
def generated.result(result: Result<&2, &2, Trace.GenerationError, Trace.LocalContext>) ->
  Maybe<&2, Trace.LocalContext>:
  match result:
    case Fail{error}:
      None{}
    case Done{context}:
      Some{context}

def generated(outcome: TapeOutcome()) -> Maybe<&2, Trace.LocalContext>:
  (rest, result) = outcome
  generated.result(result)

# The new operation that a message sent reports: the one it carries under
# Lenient{}; under Strict{}, the one a success carries, and none for a
# failure.
def reported.strict(result: Result<&2, &2, Trace.GenerationError, Trace.Sent>) -> Maybe<&2, Trace.LocalContext>:
  match result:
    case Fail{error}:
      None{}
    case Done{sent}:
      Trace.Sent.operation(sent)

def reported.result(policy: Trace.FailurePolicy, result: Trace.FailurePolicy.result(policy, Trace.Sent)) ->
  Maybe<&2, Trace.LocalContext>:
  match policy:
    case Trace.Lenient{}:
      Trace.Sent.operation(result)
    case Trace.Strict{}:
      reported.strict(result)

def reported(+policy: Trace.FailurePolicy, done: TapeSent(policy)) -> Maybe<&2, Trace.LocalContext>:
  (rest, result) = done
  reported.result(policy, result)

# The operation that a message sent by `service` is to report: the child of
# the service's operation that the tape generates, if one is generated, and
# none for a service without an operation.
def sent_child(tape: Tape(), service: Trace.Service, sampling: Trace.Sampling) -> Maybe<&2, Trace.LocalContext>:
  match service:
    case Trace.Operating{origin, outgoing, received}:
      generated(Trace.Draw.outcome(Tape(), Trace.Draw.run(16n,
        (tape, Trace.Draw.child(Trace.LocalParent{Trace.OutgoingContext.context(outgoing)}, sampling)))))
    case Trace.Untraced{error, received}:
      None{}

# Whether a service keeps no received pair.
def unkept(received: Maybe<&2, Trace.IncomingContext>) -> Bool:
  match received:
    case None{}:
      True{}
    case Some{incoming}:
      False{}

# Whether a list of entries is empty.
def no_entries(entries: List<&2, Trace.StateEntry>) -> Bool:
  match entries:
    case Nil{}:
      True{}
    case Con{entry, rest}:
      False{}

# Whether a service keeps nothing of a received context: no received pair,
# and an operation, if it has one, that sends no state.
def keeps_nothing(service: Trace.Service) -> Bool:
  match service:
    case Trace.Operating{origin, outgoing, received}:
      Bool.and(unkept(received), no_entries(Trace.TraceState.entries(Trace.OutgoingContext.state(outgoing))))
    case Trace.Untraced{error, received}:
      unkept(received)

# The same for a result under `policy`; a strict failure keeps nothing.
def kept_nothing.strict(result: Result<&2, &2, Trace.GenerationError, Trace.Service>) -> Bool:
  match result:
    case Fail{error}:
      True{}
    case Done{service}:
      keeps_nothing(service)

def kept_nothing.result(policy: Trace.FailurePolicy, result: Trace.FailurePolicy.result(policy, Trace.Service)) ->
  Bool:
  match policy:
    case Trace.Lenient{}:
      keeps_nothing(result)
    case Trace.Strict{}:
      kept_nothing.strict(result)

def kept_nothing(+policy: Trace.FailurePolicy, done: TapeService(policy)) -> Bool:
  (rest, result) = done
  kept_nothing.result(policy, result)

# LAW continue_usable
#   Claim: when extraction keeps a usable context, the message's own or the
#     base, continuing it generates a child of it, as Context.child_with
#     does with at most 16 words. The service's operation is that child,
#     with the context's state, and it keeps the message's incoming context
#     for forwarding. When the child cannot be generated, a lenient service
#     has no operation and says why, and a strict one fails with the error.
#   Requirement: spec #1, "Continue-or-start creates a child when extraction
#     or the retained base supplies a usable context" and "Never report a
#     newly created operation after generation failed"; ticket #11,
#     "Continue extraction/base context through a new child".
#   Why: a traced request stays in its trace, and a failed generation never
#     pretends to have created an operation.
#   Reading: `usable` says that extraction keeps `base`. continuing,
#     continued and service_by are defined above; with generated_child
#     (section 6), the child keeps the trace ID with its randomness
#     assertion, resolves sampled and never reuses the parent's span ID.
#   Proof: Laws.continue_usable, via proofs/continue.bend.
law continue_usable:
  for tape: Tape()
  for +extraction: Trace.Extraction
  for +base: Trace.BaseContext
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for usable: {Trace.Extraction.context(extraction) == Some{base} : Maybe<&2, Trace.BaseContext>}
  {Observe(TapeService(policy), Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape, extraction,
    Trace.Continue{}, sampling, policy)) ==
    Emit{continuing(policy, Trace.BaseContext.state(base), Trace.Extraction.incoming(extraction),
      Trace.Draw.outcome(Tape(), Trace.Draw.run(16n, (tape, Trace.Draw.child(Trace.BaseContext.parent(base), sampling)))))} :
    IO.OP<TapeService(policy)>}

# LAW restart_usable
#   Claim: at a trust boundary (Restart{}), the context that extraction
#     keeps, the message's own or the base, is not continued: a new trace
#     replaces it, as Context.restart_with does with at most 48 words, so its
#     trace ID is not reused. Its state is discarded, the restart is generated
#     with the sampled indication that `sampling` resolves from the root
#     default, not sampled, and no received pair is kept, so that nothing
#     crosses the boundary.
#   Requirement: spec #1, "Explicit restart creates a new trace identity,
#     discards previous tracestate and applies root defaults, including
#     sampled 0, unless the caller explicitly supplies a new policy/state";
#     ticket #11; spec #41, "Sampling decision when starting a trace": the
#     documented default lives in the ready path, here in
#     Context.continue_or_start_with, which keeps its Sampling parameter and
#     its behavior (user story 28).
#   Why: a trust boundary starts its own trace without disguising it as a
#     continuation of the caller's.
#   Reading: `usable` says that extraction keeps `base`, and `replaced`,
#     defined above, is the context whose trace ID the new trace avoids; with
#     generated_restart (section 6), the new trace ID differs from it and the
#     restart has the indication that it is given.
#     Sampling.resolve(sampling, False{}) is that indication: the root
#     default, False, for InheritSampled{}, and the value of SetSampled{}
#     otherwise (law sampling).
#   Proof: Laws.restart_usable, via proofs/continue.bend.
law restart_usable:
  for tape: Tape()
  for +extraction: Trace.Extraction
  for +base: Trace.BaseContext
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for usable: {Trace.Extraction.context(extraction) == Some{base} : Maybe<&2, Trace.BaseContext>}
  {Observe(TapeService(policy), Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape, extraction,
    Trace.Restart{}, sampling, policy)) ==
    Emit{starting(policy, Trace.Restarted{}, Trace.Draw.outcome(Tape(), Trace.Draw.run(48n,
      (tape, Trace.Draw.restart(replaced(base), Trace.Sampling.resolve(sampling, False{}))))))} :
    IO.OP<TapeService(policy)>}

# LAW start_unusable
#   Claim: when extraction keeps no context, neither the message's nor a
#     base, the service starts the trace with a root, as Context.root_with
#     does with at most 48 words, whether it continues or restarts. The root
#     is generated with the sampled indication that `sampling` resolves from
#     the root default, not sampled, and it has no state and no received pair.
#   Requirement: spec #1, "and creates a root otherwise" and "New roots
#     default to sampled 0"; spec #41, "Sampling decision when starting a
#     trace": the documented default lives in the ready path, here in
#     Context.continue_or_start_with, which keeps its Sampling parameter and
#     its behavior (user story 28).
#   Why: an untraced request still gets an operation that later services can
#     continue, and it is not sampled unless the application says so.
#   Reading: `none` says that extraction keeps no context; starting and begun
#     are defined above, and Sampling.resolve(sampling, False{}) is the
#     indication, as in restart_usable, that generated_root says the root
#     has.
#   Proof: Laws.start_unusable, via proofs/continue.bend.
law start_unusable:
  for tape: Tape()
  for +extraction: Trace.Extraction
  for reception: Trace.Reception
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for none: {Trace.Extraction.context(extraction) == None{} : Maybe<&2, Trace.BaseContext>}
  {Observe(TapeService(policy), Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape, extraction,
    reception, sampling, policy)) ==
    Emit{starting(policy, Trace.Started{}, Trace.Draw.outcome(Tape(),
      Trace.Draw.run(48n, (tape, Trace.Draw.root(Trace.Sampling.resolve(sampling, False{}))))))} :
    IO.OP<TapeService(policy)>}

# LAW restart_keeps_nothing
#   Claim: at a trust boundary, whatever the message and the base, and
#     whatever the words, the service keeps nothing of a received context:
#     no received pair, and an operation that sends no state. A strict
#     failure keeps nothing either.
#   Requirement: spec #1, "Explicit restart ... discards previous
#     tracestate"; ticket #11, "Explicit restart discards previous state".
#   Why: this is the boundary's guarantee, stated without the rules of
#     starting and begun: no received state or pair crosses it.
#   Reading: kept_nothing and keeps_nothing, defined above, read the
#     observed result through the service's constructors only.
#   Proof: Laws.restart_keeps_nothing, via proofs/continue.bend.
law restart_keeps_nothing:
  for tape: Tape()
  for +extraction: Trace.Extraction
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  {Observe(Bool, IO.bind(TapeService(policy), Bool, Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape,
    tape, extraction, Trace.Restart{}, sampling, policy), done => IO.pure(Bool, kept_nothing(policy, done)))) ==
    Emit{True{}} : IO.OP<Bool>}

# LAW send_operating
#   Claim: a message sent by a service with an operation gets a child of
#     that operation, as Context.child_with does with at most 16 words,
#     injected with the service's state into its carrier. When the child
#     cannot be generated, no new operation is reported: the message
#     forwards the received pair unchanged when the service keeps one that
#     can be sent whole, and carries no context fields otherwise; a strict
#     send fails with the error.
#   Requirement: spec #1, "each distinct outgoing operation obtains its own
#     child before injection" and "It may forward only an entirely accepted
#     original pair that can be sent intact within bounds; otherwise clear
#     outgoing context fields"; ticket #11, "Generate a distinct operation
#     for each outgoing operation/fan-out branch" and "do not report a newly
#     generated operation or retain stale output fields".
#   Why: each request of a fan-out is an operation of its own, and a tracing
#     failure leaves no stale or invented context in a request.
#   Reading: sending, child_sent and fallback are defined above; with
#     generated_child (section 6), the child keeps the service's trace and
#     never reuses its span ID, and section 13's laws say what
#     Context.inject, Context.forward and Context.clear write.
#   Proof: Laws.send_operating, via proofs/continue.bend.
law send_operating:
  for tape: Tape()
  for +limits: Trace.Limits
  for origin: Trace.Origin
  for +outgoing: Trace.OutgoingContext
  for +received: Maybe<&2, Trace.IncomingContext>
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for +carrier: List<&2, Trace.Header>
  {Observe(TapeSent(policy), Trace.Context.send_with(~Tape(), ~Trace.Source.tape, tape, limits,
    Trace.Operating{origin, outgoing, received}, sampling, policy, carrier)) ==
    Emit{sending(policy, limits, outgoing, received, carrier, Trace.Draw.outcome(Tape(), Trace.Draw.run(16n,
      (tape, Trace.Draw.child(Trace.LocalParent{Trace.OutgoingContext.context(outgoing)}, sampling)))))} :
    IO.OP<TapeSent(policy)>}

# LAW send_untraced
#   Claim: a message sent by a service without an operation reads no word
#     from the source and carries the fallback: the received pair forwarded
#     unchanged when it can be, and no context fields otherwise; a strict
#     send fails with the service's error.
#   Requirement: as for send_operating; spec #1, "The convenience HTTP path
#     normally lets the business operation proceed on generation failure,
#     with explicit diagnostics".
#   Why: a service whose operation could not be generated still sends its
#     requests, without inventing a context.
#   Reading: the tape comes back whole; sent_by and fallback are defined
#     above.
#   Proof: Laws.send_untraced, via proofs/continue.bend.
law send_untraced:
  for tape: Tape()
  for +limits: Trace.Limits
  for +error: Trace.GenerationError
  for +received: Maybe<&2, Trace.IncomingContext>
  for sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for +carrier: List<&2, Trace.Header>
  {Observe(TapeSent(policy), Trace.Context.send_with(~Tape(), ~Trace.Source.tape, tape, limits,
    Trace.Untraced{error, received}, sampling, policy, carrier)) ==
    Emit{(tape, sent_by(policy, fallback(limits, received, error, carrier)))} : IO.OP<TapeSent(policy)>}

# LAW send_reports_generated
#   Claim: whatever the service, the words and the policy, a message sent
#     reports a new operation exactly when one was generated for it, and it
#     is that operation: the child of the service's operation that the tape
#     generates. After a failed generation, or for a service without an
#     operation, it reports none.
#   Requirement: spec #1, "Never report a newly created operation after
#     generation failed"; ticket #11, "do not report a newly generated
#     operation".
#   Why: this is the failure contract, stated without the rules of sending
#     and fallback: an application never mistakes a fallback for a new
#     operation.
#   Reading: reported reads the observed result through Sent.operation, and
#     sent_child and generated, defined above, give the generation's context.
#   Proof: Laws.send_reports_generated, via proofs/continue.bend.
law send_reports_generated:
  for tape: Tape()
  for +limits: Trace.Limits
  for +service: Trace.Service
  for +sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for +carrier: List<&2, Trace.Header>
  {Observe(Maybe<&2, Trace.LocalContext>, IO.bind(TapeSent(policy), Maybe<&2, Trace.LocalContext>,
    Trace.Context.send_with(~Tape(), ~Trace.Source.tape, tape, limits, service, sampling, policy, carrier),
    done => IO.pure(Maybe<&2, Trace.LocalContext>, reported(policy, done)))) ==
    Emit{sent_child(tape, service, sampling)} : IO.OP<Maybe<&2, Trace.LocalContext>>}

# What a host that drives a plan's generation itself makes of it, as
# JavaScript code calling the package does: the host's loop of section 6
# over the plan's generation (host.drive), ServicePlan.service or
# SendPlan.sent of the result, and the policy as Policy.apply takes it, the
# value itself under Lenient{} and Serve.strict or Send.strict of it under
# Strict{}.
def host_service.done(+policy: Trace.FailurePolicy, +plan: Trace.ServicePlan, outcome: TapeOutcome()) ->
  TapeService(policy):
  (rest, result) = outcome
  (rest, Trace.Policy.apply(policy, Trace.Service, Trace.Serve.strict, Trace.ServicePlan.service(plan, result)))

def host_service(+policy: Trace.FailurePolicy, tape: Tape(), +plan: Trace.ServicePlan) -> TapeService(policy):
  host_service.done(policy, plan, host.drive(tape, Trace.ServicePlan.generation(plan)))

def host_sent.done(+policy: Trace.FailurePolicy, +plan: Trace.SendPlan, outcome: TapeOutcome()) -> TapeSent(policy):
  (rest, result) = outcome
  (rest, Trace.Policy.apply(policy, Trace.Sent, Trace.Send.strict, Trace.SendPlan.sent(plan, result)))

def host_sent(+policy: Trace.FailurePolicy, tape: Tape(), +plan: Trace.SendPlan) -> TapeSent(policy):
  host_sent.done(policy, plan, host.drive(tape, Trace.SendPlan.generation(plan)))

# LAW hosted_service
#   Claim: for every tape, message, reception, sampling and policy, a host
#     that takes the plan of ServicePlan.new, drives its generation itself
#     and hands the result to ServicePlan.service gets the service that
#     Context.continue_or_start_with gives, reading the same words.
#   Requirement: ticket #13, "Deliver ready generation, extraction,
#     injection, forwarding and failure handling through the shared facade
#     without a second protocol implementation".
#   Why: every law of this section then holds of a host that drives the
#     plans itself. The JavaScript facade is such a host; that its code
#     follows this path is tested, not proved.
#   Reading: host_service is defined above.
#   Proof: Laws.hosted_service, via proofs/continue.bend.
law hosted_service:
  for tape: Tape()
  for +extraction: Trace.Extraction
  for reception: Trace.Reception
  for sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  {Observe(TapeService(policy), Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape, extraction,
    reception, sampling, policy)) ==
    Emit{host_service(policy, tape, Trace.ServicePlan.new(extraction, reception, sampling))} :
    IO.OP<TapeService(policy)>}

# LAW hosted_send
#   Claim: as hosted_service, for a message sent: a host that takes the plan
#     of SendPlan.new, drives its generation itself and hands the result to
#     SendPlan.sent gets the message that Context.send_with gives, reading
#     the same words, none for a service without an operation.
#   Requirement and Why: as for hosted_service.
#   Proof: Laws.hosted_send, via proofs/continue.bend.
law hosted_send:
  for tape: Tape()
  for +limits: Trace.Limits
  for service: Trace.Service
  for sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for +carrier: List<&2, Trace.Header>
  {Observe(TapeSent(policy), Trace.Context.send_with(~Tape(), ~Trace.Source.tape, tape, limits, service, sampling,
    policy, carrier)) ==
    Emit{host_sent(policy, tape, Trace.SendPlan.new(limits, service, sampling, carrier))} : IO.OP<TapeSent(policy)>}

# 15. Native HTTP headers
# =======================
#
# native_http.bend adapts the header maps of bend-kit's native HTTP package
# to the package (ticket #12): a Base Map from each field name to its
# values in arrival order. These laws state that the adapter adds no Trace
# Context behavior of its own. The carrier it reads from a map keeps every
# value of every name, the map it writes for a carrier holds every value of
# every name, and its two shortcuts are the package's operations on that
# carrier, so the laws of sections 12 to 14 say what they do. What Base's Map
# stores, lists and looks up is Base's behavior, which Base proves nothing
# about: http_carrier takes the map's list of entries as given, and
# http_headers assumes the two facts about Map.set and Map.get that the
# adapter relies on. The adapter's corpus, tests/NATIVE-HTTP.bend, and the
# HTTP qualification exercise Base's side.

# The values of the fields named exactly `name`, in order.
def http_values.kept(same: Bool, value: String, rest: List<&2, String>) -> List<&2, String>:
  match same:
    case True{}:
      Con{value, rest}
    case False{}:
      rest

def http_values(+name: String, carrier: List<&2, Trace.Header>) -> List<&2, String>:
  match carrier:
    case Nil{}:
      Nil{}
    case Con{Trace.Header{field, value}, rest}:
      http_values.kept(String.eq(field, name), value, http_values(name, rest))

# The values of the map entries named exactly `name`, entry by entry.
def entry_values.kept(same: Bool, values: List<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match same:
    case True{}:
      List.append(&2, String, values, rest)
    case False{}:
      rest

def entry_values(+name: String, entries: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>) ->
  List<&2, String>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{Tuple{key, values}, rest}:
      entry_values.kept(String.eq(key, name), values, entry_values(name, rest))

# LAW http_carrier
#   Claim: the carrier that the adapter reads from a header map holds, under
#     every name, exactly the values that the map's entries hold under it, in
#     the same order: no value is dropped, reordered or added.
#   Requirement: spec #1, "Preserve an ordered multi-value carrier" and "They
#     retain repeated context fields ... and perform only necessary host
#     translation"; W3C 3.2.1 and 3.3.1.
#   Why: extraction can only refuse a repeated traceparent, or combine
#     repeated tracestate fields in order, if the adapter hands it every field
#     as it came.
#   Reading: Map.to_list is Base's list of the map's entries; http_values and
#     entry_values, defined above, select values by exact name.
#   Proof: Laws.http_carrier, via proofs/http.bend.
law http_carrier:
  for headers: Map<&2, List<&2, String>>
  for +name: String
  {http_values(name, NativeHttp.carrier(headers)) == entry_values(name, Map.to_list(&2, List<&2, String>, headers)) :
    List<&2, String>}

# The values a map holds under `key`, none when it has no entry for it.
def map_values(+headers: Map<&2, List<&2, String>>, key: String) -> List<&2, String>:
  Pair.snd(Map<&2, List<&2, String>>, List<&2, String>, Map.get(List<&2, String>, Nil{}, headers, key))

# LAW http_headers
#   Claim: the map that the adapter writes for a carrier holds, under every
#     name, exactly the carrier's values of that name, in the same order,
#     provided Base's Map does what the adapter relies on: a list set under a
#     key is found under it, and setting another key leaves it as it was.
#   Requirement: spec #1, "They retain repeated context fields, replace old
#     outgoing fields and perform only necessary host translation".
#   Why: the fields that the package writes for a message to send, a
#     repeated one included, reach bend-kit as written and in order.
#   Reading: `found` and `kept` state Base's Map contract, which Base does
#     not prove. They are templates (`~`), so that a proof may use them at
#     every field; map_values and http_values are defined above.
#   Proof: Laws.http_headers, via proofs/http.bend.
law http_headers:
  for ~found: @headers: Map<&2, List<&2, String>> -> @key: String -> @values: List<&2, String> ->
    {map_values(Map.set(&2, List<&2, String>, headers, key, values), key) == values : List<&2, String>}
  for ~kept: @headers: Map<&2, List<&2, String>> -> @key: String -> @other: String -> @values: List<&2, String> ->
    {String.eq(other, key) == False{} : Bool} ->
    {map_values(Map.set(&2, List<&2, String>, headers, other, values), key) == map_values(headers, key) :
      List<&2, String>}
  for carrier: List<&2, Trace.Header>
  for +name: String
  {map_values(NativeHttp.headers(carrier), name) == http_values(name, carrier) : List<&2, String>}

# LAW http_continue
#   Claim: the adapter's continue-or-start is the package's, for every tape,
#     on the extraction of the carrier that it reads from the request's
#     header map.
#   Requirement: ticket #12, "Use only package behavior in the
#     service/adapter; do not reproduce parsing, normalization or generation
#     rules".
#   Why: the laws of sections 12 and 14 then say what a service built on the
#     adapter does with each request.
#   Proof: Laws.http_continue, via proofs/http.bend.
law http_continue:
  for tape: Tape()
  for +limits: Trace.Limits
  for headers: Map<&2, List<&2, String>>
  for base: Maybe<&2, Trace.BaseContext>
  for reception: Trace.Reception
  for sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  {Observe(TapeService(policy), NativeHttp.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape, limits, headers,
    base, reception, sampling, policy)) ==
    Observe(TapeService(policy), Trace.Context.continue_or_start_with(~Tape(), ~Trace.Source.tape, tape,
      Trace.Context.extract(limits, NativeHttp.carrier(headers), base), reception, sampling, policy)) :
    IO.OP<TapeService(policy)>}

# A request to send: the message sent with the header map of its carrier.
def http_outbound(+sent: Trace.Sent) -> NativeHttp.Outbound:
  NativeHttp.Outbound{sent, NativeHttp.headers(Trace.Sent.carrier(sent))}

# The same for a strict result: a failure stays a failure.
def http_strict(result: Result<&2, &2, Trace.GenerationError, Trace.Sent>) ->
  Result<&2, &2, Trace.GenerationError, NativeHttp.Outbound>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{sent}:
      Done{http_outbound(sent)}

# A request to send under `policy`.
def http_written(policy: Trace.FailurePolicy, result: Trace.FailurePolicy.result(policy, Trace.Sent)) ->
  Trace.FailurePolicy.result(policy, NativeHttp.Outbound):
  match policy:
    case Trace.Lenient{}:
      http_outbound(result)
    case Trace.Strict{}:
      http_strict(result)

# The result a send through the adapter returns under `policy`, as a tape law
# observes it.
def TapeOutbound(policy: Trace.FailurePolicy) -> Type:
  Tape() & Trace.FailurePolicy.result(policy, NativeHttp.Outbound)

def http_written.done(+policy: Trace.FailurePolicy, done: TapeSent(policy)) -> TapeOutbound(policy):
  (rest, result) = done
  (rest, http_written(policy, result))

# LAW http_send
#   Claim: the adapter's send is the package's, for every tape, on the
#     carrier of the request's own header map, followed by the header map of
#     the carrier that the package gives back. The request's old context
#     fields therefore go whatever the case of their names, and it carries
#     what section 14's laws say: a new operation, the forwarded pair or no
#     context.
#   Requirement: ticket #12, as for http_continue; spec #1, "replace old
#     outgoing fields".
#   Why: a stale context in a reused request container never reaches the
#     wire, and the adapter invents no context of its own.
#   Reading: http_written and http_outbound, defined above, pair the message
#     sent with NativeHttp.headers of its carrier, which http_headers
#     describes.
#   Proof: Laws.http_send, via proofs/http.bend.
law http_send:
  for tape: Tape()
  for +limits: Trace.Limits
  for service: Trace.Service
  for sampling: Trace.Sampling
  for +policy: Trace.FailurePolicy
  for +headers: Map<&2, List<&2, String>>
  {Observe(TapeOutbound(policy), NativeHttp.send_with(~Tape(), ~Trace.Source.tape, tape, limits, service, sampling,
    policy, headers)) ==
    Observe(TapeOutbound(policy), IO.bind(TapeSent(policy), TapeOutbound(policy),
      Trace.Context.send_with(~Tape(), ~Trace.Source.tape, tape, limits, service, sampling, policy,
        NativeHttp.carrier(headers)), done => IO.pure(TapeOutbound(policy), http_written.done(policy, done)))) :
    IO.OP<TapeOutbound(policy)>}

# 16. Identifiers as bytes
# ========================
#
# An exporter writes a trace ID as its 16 bytes and a span ID as its 8 in
# OTLP's protobuf encoding, and as their lowercase hexadecimal text in OTLP's
# JSON encoding. Spec #41 specifies both forms ("Identifier forms"), and
# ticket #43 the bytes. The text is TraceId.to_string and SpanId.to_string,
# whose laws are in section 2; the bytes are a List of U32 cells, one per
# byte, which TraceId.from_bytes and SpanId.from_bytes read back as the text
# readers read text.

# The values that Base gives the cells of a list, in order.
def cell_values(cells: List<&2, U32>) -> List<&2, Nat>:
  match cells:
    case Nil{}:
      Nil{}
    case Con{cell, rest}:
      Con{U32.to_nat(cell), cell_values(rest)}

# The value of each pair of hexadecimal digits of a text, in order, read with
# hex_numeral of section 5, the first digit of a pair the high one. A last
# digit without a pair would be dropped; the text of an ID has an even
# number of digits.
def hex_pairs(text: String) -> List<&2, Nat>:
  match text:
    case SNil{}:
      Nil{}
    case SCon{high, SNil{}}:
      Nil{}
    case SCon{high, SCon{low, rest}}:
      Con{hex_numeral(SCon{high, SCon{low, SNil{}}}, 0n), hex_pairs(rest)}

# LAW trace_bytes
#   Claim: the bytes of a trace ID are, in order, the numbers that the pairs
#     of digits of its text denote in hexadecimal: 16 bytes from 0 to 255,
#     the first byte made of the first two digits, the first digit high.
#   Requirement: spec #41, user story 11: "I want a trace ID as its 16 bytes
#     and a span ID as its 8 bytes, most significant first, so that I can
#     write OTLP protobuf fields"; Base's byte convention.
#   Why: a collector that reads the bytes must find the ID that traceparent
#     and OTLP's JSON text carry. A converter that swapped two bytes, or the
#     two digits of a byte, would pass the round trips below but fail this
#     law.
#   Reading: cell_values is Base's U32.to_nat of each cell, and hex_pairs,
#     above, reads the text two digits at a time with hex_numeral of section
#     5, independently of the package.
#   Proof: Laws.trace_bytes, via proofs/bytes.bend.
law trace_bytes:
  for id: Trace.TraceId
  {cell_values(Trace.TraceId.to_bytes(id)) == hex_pairs(Trace.TraceId.to_string(id)) : List<&2, Nat>}

# LAW span_bytes
#   Claim: as trace_bytes, for the 8 bytes of a span ID and its 16 digits.
#   Requirement and Why: as for trace_bytes.
#   Proof: Laws.span_bytes, via proofs/bytes.bend.
law span_bytes:
  for id: Trace.SpanId
  {cell_values(Trace.SpanId.to_bytes(id)) == hex_pairs(Trace.SpanId.to_string(id)) : List<&2, Nat>}

# LAW trace_bytes_roundtrip
#   Claim: reading back the bytes of any trace ID gives the same 32 digits,
#     with no randomness assertion.
#   Requirement: spec #41, user story 14: "I want the byte conversions to
#     round-trip in both directions, so that exporting and reading back an ID
#     never changes it"; and user story 10, which asks that an ID converted
#     from bytes carry no randomness assertion.
#   Why: a trace ID that an exporter writes and a collector or another SDK
#     reads back must name the same trace. The bytes do not carry the
#     assertion, so whoever reads them makes it again, or not.
#   Reading: `Trace.TraceId{value, random}` ranges over every trace ID: its
#     32 digits, with the proof that they are not all zero, and its
#     randomness assertion. The ID read back has the same `value`, proof
#     included, and `False{}`, whatever `random` was.
#   Proof: Laws.trace_bytes_roundtrip, via proofs/bytes.bend.
law trace_bytes_roundtrip:
  for value: Digits.NonZero<32n>
  for random: Bool
  {Trace.TraceId.from_bytes(Trace.TraceId.to_bytes(Trace.TraceId{value, random})) ==
    Done{Trace.TraceId{value, False{}}} : Result<&2, &2, Trace.Error, Trace.TraceId>}

# LAW span_bytes_roundtrip
#   Claim: reading back the bytes of any span ID gives that span ID.
#   Requirement and Why: as for trace_bytes_roundtrip. A span ID carries
#     nothing besides its digits, so it comes back whole.
#   Proof: Laws.span_bytes_roundtrip, via proofs/bytes.bend.
law span_bytes_roundtrip:
  for id: Trace.SpanId
  {Trace.SpanId.from_bytes(Trace.SpanId.to_bytes(id)) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}

# LAW trace_bytes_inverse
#   Claim: whenever TraceId.from_bytes accepts a list of cells, the bytes of
#     the trace ID it returns are exactly that list.
#   Requirement: spec #41, user story 14, the direction from bytes; and user
#     story 13, which asks that IDs from other systems be validated as parsed
#     ones are: like the codec's reader (law inverse), the byte reader accepts
#     no variant of an ID's bytes.
#   Why: with trace_bytes_roundtrip, it makes reading bytes and writing them
#     exact inverses, so an ID that an SDK reads from another system's bytes
#     is written back with the same bytes.
#   Reading: `for bytes: List<&2, U32>` ranges over every list of cells,
#     valid or not; the hypothesis `read` restricts the claim to the lists
#     that are accepted, and `id` is the trace ID read.
#   Proof: Laws.trace_bytes_inverse, via proofs/bytes.bend.
law trace_bytes_inverse:
  for bytes: List<&2, U32>
  for id: Trace.TraceId
  for read: {Trace.TraceId.from_bytes(bytes) == Done{id} : Result<&2, &2, Trace.Error, Trace.TraceId>}
  {Trace.TraceId.to_bytes(id) == bytes : List<&2, U32>}

# LAW span_bytes_inverse
#   Claim: as trace_bytes_inverse, for SpanId.from_bytes.
#   Requirement and Why: as for trace_bytes_inverse.
#   Proof: Laws.span_bytes_inverse, via proofs/bytes.bend.
law span_bytes_inverse:
  for bytes: List<&2, U32>
  for id: Trace.SpanId
  for read: {Trace.SpanId.from_bytes(bytes) == Done{id} : Result<&2, &2, Trace.Error, Trace.SpanId>}
  {Trace.SpanId.to_bytes(id) == bytes : List<&2, U32>}

# LAW trace_bytes_injective
#   Claim: two trace IDs with the same bytes have the same digits.
#   Requirement: spec #41, "Identifier forms": the bytes are a form of the
#     ID, as its text is. This law shows that the conversion loses no
#     information, as hex_injective shows for source words.
#   Why: if two trace IDs had the same bytes, a collector could not tell
#     their traces apart.
#   Reading: the conclusion compares texts, which name the trace; the
#     randomness assertion is not part of the bytes, and TraceId.is_eq
#     ignores it too.
#   Proof: Laws.trace_bytes_injective, via proofs/bytes.bend.
law trace_bytes_injective:
  for left: Trace.TraceId
  for right: Trace.TraceId
  for same: {Trace.TraceId.to_bytes(left) == Trace.TraceId.to_bytes(right) : List<&2, U32>}
  {Trace.TraceId.to_string(left) == Trace.TraceId.to_string(right) : String}

# LAW span_bytes_injective
#   Claim: two span IDs with the same bytes are the same span ID.
#   Requirement and Why: as for trace_bytes_injective; a span ID has nothing
#     besides its digits, so the IDs themselves are equal.
#   Proof: Laws.span_bytes_injective, via proofs/bytes.bend.
law span_bytes_injective:
  for left: Trace.SpanId
  for right: Trace.SpanId
  for same: {Trace.SpanId.to_bytes(left) == Trace.SpanId.to_bytes(right) : List<&2, U32>}
  {left == right : Trace.SpanId}

# LAW bytes_unasserted
#   Claim: a trace ID read from bytes makes no randomness assertion.
#   Requirement: spec #41, user story 10: "I want IDs converted from bytes or
#     hex to carry no randomness assertion, so that my SDK asserts
#     random-trace-id only when my generator declares it"; and "An ID
#     converted from words, hex or bytes makes no assertion, and a caller who
#     knows it is random uses TraceId.assert_random".
#   Why: bytes say nothing about how the ID was made. An SDK that read an ID
#     from another system and emitted random-trace-id with it would assert a
#     randomness that nobody established.
#   Scope: trace_id_parse states the same of hex text, and words_unasserted
#     of source words.
#   Proof: Laws.bytes_unasserted, via proofs/bytes.bend.
law bytes_unasserted:
  for bytes: List<&2, U32>
  for id: Trace.TraceId
  for read: {Trace.TraceId.from_bytes(bytes) == Done{id} : Result<&2, &2, Trace.Error, Trace.TraceId>}
  {Trace.TraceId.is_random(id) == False{} : Bool}

# The laws below state the error of each refusal, in reading order, and that
# every other list is accepted.

# Whether every cell is a byte: at most 255, as Base's TCP.send_bytes
# requires.
def all_bytes(cells: List<&2, U32>) -> Bool:
  match cells:
    case Nil{}:
      True{}
    case Con{cell, rest}:
      Bool.and(U32.is_le(cell, 255), all_bytes(rest))

# LAW trace_bytes_short
#   Claim: a list of fewer than 16 bytes is refused with UnexpectedEnd at its
#     length, the offset where the next byte is missing.
#   Requirement: spec #41, user story 13: "I want to build a trace ID from 16
#     bytes and a span ID from 8 bytes, refusing a wrong length, a value above
#     255 and all zeros, so that IDs from other systems are validated as
#     parsed ones are"; TraceId.parse reports a short text the same way.
#   Why: a truncated ID must not be completed with invented bytes, and the
#     error tells where the list stopped.
#   Reading: `cells` says that every cell is a byte, so that no earlier cell
#     is refused first (trace_bytes_above covers those).
#   Proof: Laws.trace_bytes_short, via proofs/bytes.bend.
law trace_bytes_short:
  for bytes: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, bytes), 16n) == True{} : Bool}
  {Trace.TraceId.from_bytes(bytes) == Fail{Trace.UnexpectedEnd{List.length(&2, U32, bytes)}} :
    Result<&2, &2, Trace.Error, Trace.TraceId>}

# LAW span_bytes_short
#   Claim: as trace_bytes_short, for fewer than 8 bytes and SpanId.from_bytes.
#   Requirement and Why: as for trace_bytes_short.
#   Proof: Laws.span_bytes_short, via proofs/bytes.bend.
law span_bytes_short:
  for bytes: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, bytes), 8n) == True{} : Bool}
  {Trace.SpanId.from_bytes(bytes) == Fail{Trace.UnexpectedEnd{List.length(&2, U32, bytes)}} :
    Result<&2, &2, Trace.Error, Trace.SpanId>}

# LAW trace_bytes_long
#   Claim: 16 bytes followed by any cell are refused with TrailingInput,
#     whatever that cell and the cells after it are.
#   Requirement: spec #41, user story 13, as for trace_bytes_short;
#     TraceId.parse refuses characters after 32 digits the same way.
#   Why: a longer list is not an ID, and taking its first 16 bytes would
#     accept a value that another system meant otherwise.
#   Reading: `extra` is the first cell after the 16 bytes and `more` the
#     cells after it.
#   Proof: Laws.trace_bytes_long, via proofs/bytes.bend.
law trace_bytes_long:
  for bytes: List<&2, U32>
  for extra: U32
  for more: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for sixteen: {List.length(&2, U32, bytes) == 16n : Nat}
  {Trace.TraceId.from_bytes(List.append(&2, U32, bytes, Con{extra, more})) == Fail{Trace.TrailingInput{}} :
    Result<&2, &2, Trace.Error, Trace.TraceId>}

# LAW span_bytes_long
#   Claim: as trace_bytes_long, for 8 bytes and SpanId.from_bytes.
#   Requirement and Why: as for trace_bytes_long.
#   Proof: Laws.span_bytes_long, via proofs/bytes.bend.
law span_bytes_long:
  for bytes: List<&2, U32>
  for extra: U32
  for more: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for eight: {List.length(&2, U32, bytes) == 8n : Nat}
  {Trace.SpanId.from_bytes(List.append(&2, U32, bytes, Con{extra, more})) == Fail{Trace.TrailingInput{}} :
    Result<&2, &2, Trace.Error, Trace.SpanId>}

# LAW trace_bytes_above
#   Claim: a cell above 255 among the first 16 is refused with InvalidByte at
#     its offset, when the cells before it are bytes.
#   Requirement: spec #41, user story 13, as for trace_bytes_short; Base's
#     TCP.send_bytes refuses such a cell too.
#   Why: such a cell is not a byte, so the list is not an ID's bytes;
#     keeping only its low eight bits would read another ID than the one
#     meant.
#   Reading: `before` holds the cells before the refused `cell`, fewer than
#     16 and each a byte, and `after` the cells after it, which are not read.
#   Proof: Laws.trace_bytes_above, via proofs/bytes.bend.
law trace_bytes_above:
  for before: List<&2, U32>
  for cell: U32
  for after: List<&2, U32>
  for cells: {all_bytes(before) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, before), 16n) == True{} : Bool}
  for above: {U32.is_gt(cell, 255) == True{} : Bool}
  {Trace.TraceId.from_bytes(List.append(&2, U32, before, Con{cell, after})) ==
    Fail{Trace.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, Trace.Error, Trace.TraceId>}

# LAW span_bytes_above
#   Claim: as trace_bytes_above, among the first 8 cells and for
#     SpanId.from_bytes.
#   Requirement and Why: as for trace_bytes_above.
#   Proof: Laws.span_bytes_above, via proofs/bytes.bend.
law span_bytes_above:
  for before: List<&2, U32>
  for cell: U32
  for after: List<&2, U32>
  for cells: {all_bytes(before) == True{} : Bool}
  for short: {Nat.is_lt(List.length(&2, U32, before), 8n) == True{} : Bool}
  for above: {U32.is_gt(cell, 255) == True{} : Bool}
  {Trace.SpanId.from_bytes(List.append(&2, U32, before, Con{cell, after})) ==
    Fail{Trace.InvalidByte{List.length(&2, U32, before)}} : Result<&2, &2, Trace.Error, Trace.SpanId>}

# Whether every cell is zero.
def all_zero(cells: List<&2, U32>) -> Bool:
  match cells:
    case Nil{}:
      True{}
    case Con{cell, rest}:
      Bool.and(U32.is_zero(cell), all_zero(rest))

# LAW trace_bytes_accepts
#   Claim: every list of exactly 16 bytes that are not all zero is accepted
#     as a trace ID.
#   Requirement: spec #41, user story 13: the refusals above are the only
#     ones, so bytes from another system are refused exactly when their text
#     would be.
#   Why: with the refusals, it says which lists TraceId.from_bytes accepts:
#     an SDK that checks the length and the cells itself agrees with it.
#   Proof: Laws.trace_bytes_accepts, via proofs/bytes.bend.
law trace_bytes_accepts:
  for bytes: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for sixteen: {List.length(&2, U32, bytes) == 16n : Nat}
  for nonzero: {all_zero(bytes) == False{} : Bool}
  {Result.is_done(&2, &2, Trace.Error, Trace.TraceId, Trace.TraceId.from_bytes(bytes)) == True{} : Bool}

# LAW span_bytes_accepts
#   Claim: as trace_bytes_accepts, for exactly 8 bytes and SpanId.from_bytes.
#   Requirement and Why: as for trace_bytes_accepts.
#   Proof: Laws.span_bytes_accepts, via proofs/bytes.bend.
law span_bytes_accepts:
  for bytes: List<&2, U32>
  for cells: {all_bytes(bytes) == True{} : Bool}
  for eight: {List.length(&2, U32, bytes) == 8n : Nat}
  for nonzero: {all_zero(bytes) == False{} : Bool}
  {Result.is_done(&2, &2, Trace.Error, Trace.SpanId, Trace.SpanId.from_bytes(bytes)) == True{} : Bool}

# LAW zero_bytes
#   Claim: 16 zero bytes are refused as a trace ID with
#     ZeroId{TraceIdField{}}, and 8 zero bytes as a span ID with
#     ZeroId{SpanIdField{}}.
#   Requirement: spec #41, user story 13; W3C Level 2, sections 3.2.2.3 and
#     3.2.2.4: an all-zero trace ID or parent ID is invalid.
#   Why: an all-zero ID is not an ID, whatever form it arrives in.
#   Reading: List.replicate(U32, n, 0) is Base's list of n zero cells, the
#     only all-zero list of the right length.
#   Proof: Laws.zero_bytes, by computation.
law zero_bytes:
  {Trace.TraceId.from_bytes(List.replicate(U32, 16n, 0)) == Fail{Trace.ZeroId{Trace.TraceIdField{}}} :
    Result<&2, &2, Trace.Error, Trace.TraceId>} &
  {Trace.SpanId.from_bytes(List.replicate(U32, 8n, 0)) == Fail{Trace.ZeroId{Trace.SpanIdField{}}} :
    Result<&2, &2, Trace.Error, Trace.SpanId>}
