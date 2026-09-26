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
# prints "All terms check." only when every law in this file is proved.
# scripts/validate.sh runs that gate on every backend and also refuses proofs
# that rely on `@unsafe`. By Bend's convention the project owner reviews and
# owns these statements; the proofs may change freely as long as the
# statements hold.
#
# Every law is documented with the same headings:
#
#   Claim        what the law says, in plain words.
#   Requirement  the rule it enforces: a section of the pinned W3C Trace
#                Context Level 2 publication (Candidate Recommendation Draft
#                of 2024-03-28), or a decision of the approved specification
#                (issue #1) or of a ticket.
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
#    3. Local contexts and flags       from_ids ... received_flags
#    4. Children and restarts          sampling ... restart_accepts
#    5. Identifiers from source words  trace_words ... words_unasserted
#    6. Generation from a source       feed_failure ... generated_restart
#    7. Limits                         limits_bounds ... default_limits
#    8. Tracestate keys and values     key_parse ... value_separators
#    9. Tracestate states and lookups  state_valid, get_entry, get_absent
#   10. Tracestate parsing             state_roundtrip ... first_wins
#   11. Tracestate updates and         set_entries ... emit_accepted
#       emission

import Base
import ./trace_context.bend as Trace

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
#   Proof: Laws.formatted_length in PROOF.bend, from the encoded length of each
#     digit sequence (proofs/digits.bend) and of joined strings
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
# sends a header. A RemoteContext identifies the sender's operation in a
# received header. They are separate types, so a received context cannot be
# sent as if it were the participant's own operation (spec #1, "Distinguish
# remote context, local context and the accepted original header pair"). The
# flags of W3C Level 2, section 3.2.2.5, are bit 0 (sampled) and bit 1
# (random-trace-id); the other six bits are reserved.

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
#     IDs with sampled 0.
#   Requirement: spec #1, "New roots default to sampled 0" (user story 10).
#   Why: starting a trace, with generated or supplied IDs, must not by itself
#     ask downstream services to record it; sampling stays an explicit
#     decision of the application.
#   Proof: Laws.root, by computation.
law root:
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  {Trace.Context.root_from_ids(trace_id, span_id) == Trace.Context.from_ids(trace_id, span_id, False{}) : Trace.LocalContext}

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
#     conversions. The same law over whole header carriers belongs to
#     extraction and injection (#9 and #10).
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
#   Claim: a successful restart is the root of its supplied IDs (sampled 0,
#     random as asserted by the new trace ID), and its trace ID differs from
#     the received one.
#   Requirement: spec #1, "Explicit restart creates a new trace identity,
#     discards previous tracestate and applies root defaults, including sampled
#     0" (user story 46).
#   Why: a restart that kept the received trace ID would be a continuation in
#     disguise.
#   Scope: discarding the previous tracestate belongs to the continue-or-start
#     operation (#11).
#   Proof: Laws.restart, via proofs/lifecycle.bend.
law restart:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for restarted: Trace.LocalContext
  for accepted: {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Done{restarted} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}
  {restarted == Trace.Context.root_from_ids(trace_id, span_id) : Trace.LocalContext} &
  {Trace.TraceId.to_string(trace_id) != Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}

# LAW restart_reuse
#   Claim: a restart whose trace ID equals the received one is refused with
#     ReusedTraceId, whatever its randomness assertion.
#   Requirement: as for `restart`; the decision to refuse the received trace ID
#     was recorded on #5.
#   Why: see `restart`.
#   Proof: Laws.restart_reuse, via proofs/lifecycle.bend.
law restart_reuse:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for reused: {Trace.TraceId.to_string(trace_id) ==
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) == Fail{Trace.ReusedTraceId{}} :
    Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

# LAW restart_accepts
#   Claim: every other trace ID is accepted, and the restart is exactly the
#     root of the supplied IDs.
#   Why: with restart_reuse it makes reuse the only reason a restart can be
#     refused.
#   Proof: Laws.restart_accepts, via proofs/lifecycle.bend.
law restart_accepts:
  for previous: Trace.RemoteContext
  for trace_id: Trace.TraceId
  for span_id: Trace.SpanId
  for distinct: {Trace.TraceId.to_string(trace_id) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String}
  {Trace.Context.restart_from_ids(previous, trace_id, span_id) ==
    Done{Trace.Context.root_from_ids(trace_id, span_id)} : Result<&2, &2, Trace.ContextError, Trace.LocalContext>}

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
# source one at a time and feed them to the generation machine (Draw and Step
# in trace_context.bend). Context.root, child and restart in generation.bend
# do the same with the host's cryptographic source. The laws quantify over
# every "tape": a list of word results, errors included, that a deterministic
# source replays. The rules come from spec #1, "Generation and failure
# contracts": the trace ID before the span ID, at most eight candidates per
# ID, zero rejected, a child's candidate equal to the parent's span ID
# rejected, the first source error ends generation, and there is no time or
# counter fallback. The quality of a real host source is outside every law.

# LAW feed_failure
#   Claim: a source error ends generation at once with SourceFailure, carrying
#     the source's own code and message, whatever the machine was drawing.
#   Requirement: spec #1, "A source error at any word ends generation
#     immediately" and "no time/counter fallback is permitted".
#   Why: continuing after a failed read, or filling in a predictable word,
#     would produce IDs that are not random while claiming they are.
#   Proof: Laws.feed_failure, by computation.
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
#   Claim: generating a root from a tape source does exactly what the pure tape
#     driver Draw.run does with a budget of 48 words: the same words are read,
#     in order, and the unread ones are handed back.
#   Requirement: spec #1, "Allow an explicit caller provider and deterministic
#     sources for tests"; the IO operation must follow the machine that the
#     other generation laws describe.
#   Why: it carries every generation law stated on the pure driver over to the
#     operation that applications call.
#   Reading: Observe runs the IO action; Emit{v} is its result.
#   Proof: Laws.root_tape, via proofs/generation.bend.
law root_tape:
  for tape: Tape()
  {Observe(TapeOutcome(), Trace.Context.root_with(~Tape(), ~Trace.Source.tape, tape)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.root())))} : IO.OP<TapeOutcome()>}

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
#   Claim: as root_tape, for a restart with a budget of 48 words.
#   Proof: Laws.restart_tape, via proofs/generation.bend.
law restart_tape:
  for tape: Tape()
  for previous: Trace.RemoteContext
  {Observe(TapeOutcome(), Trace.Context.restart_with(~Tape(), ~Trace.Source.tape, tape, previous)) ==
    Emit{Trace.Draw.outcome(Tape(), Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))))} :
    IO.OP<TapeOutcome()>}

# LAW root_ends
#   Claim: for every tape, a root generation has finished, with a context or a
#     failure, within 48 words.
#   Requirement: spec #1, "Allow at most eight candidates per ID": eight trace
#     ID candidates of four words and eight span ID candidates of two.
#   Why: generation always ends with an answer. The IO operation's word budget
#     is exactly this worst case, so it never gives up early either.
#   Reading: Draw.ended says the driver's step is Created or Failed.
#   Proof: Laws.root_ends, via proofs/generation.bend.
law root_ends:
  for tape: Tape()
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.root()))) == True{} : Bool}

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
#   Claim: for every tape, a restart has finished within 48 words.
#   Requirement and Why: as for root_ends.
#   Proof: Laws.restart_ends, via proofs/generation.bend.
law restart_ends:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  {Trace.Draw.ended(Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous)))) == True{} : Bool}

# LAW root_exhaustion
#   Claim: eight all-zero trace ID candidates (32 zero words) make a root fail
#     with ExhaustedTraceId, and the words after them are not read.
#   Requirement: spec #1, "Allow at most eight candidates per ID. Reject zero",
#     and the test decision "prevention of a ninth attempt".
#   Why: a source stuck on zeros must produce a structured error instead of
#     looping or accepting an invalid ID; not reading a ninth candidate bounds
#     the work.
#   Scope: proved for all-zero candidates. Exhaustion through reused IDs is
#     tested in tests/GENERATION.bend.
#   Proof: Laws.root_exhaustion, by computation.
law root_exhaustion:
  for rest: Tape()
  {Trace.Draw.run(48n, (List.append(&1, Result<&1, &1, U32 & String, U32>, zeros(32n), rest), Trace.Draw.root())) ==
    (rest, Trace.Failed{Trace.ExhaustedTraceId{}}) : TapeStep()}

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
#   Claim: a root created from any tape asserts random-trace-id and is not
#     sampled, so it is emitted with flags 02.
#   Requirement: spec #1, "a default internally generated root has flags 02,
#     despite sampled being 0".
#   Why: receivers may rely on the random flag of IDs this package generates,
#     and new roots never ask for recording by default.
#   Scope: the source is trusted to be random; no law speaks about the quality
#     of a real source.
#   Proof: Laws.generated_root, via proofs/generation.bend.
law generated_root:
  for tape: Tape()
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.root())) == (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}

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
#     received one, asserts random-trace-id and is not sampled.
#   Requirement: as for `restart` and generated_root.
#   Proof: Laws.generated_restart, via proofs/generation.bend.
law generated_restart:
  for tape: Tape()
  for +previous: Trace.RemoteContext
  for rest: Tape()
  for created: Trace.LocalContext
  for generated: {Trace.Draw.run(48n, (tape, Trace.Draw.restart(previous))) ==
    (rest, Trace.Created{created}) : TapeStep()}
  {Trace.TraceId.to_string(Trace.LocalContext.trace_id(created)) !=
    Trace.TraceId.to_string(Trace.RemoteContext.trace_id(previous)) : String} &
  {Trace.TraceId.is_random(Trace.LocalContext.trace_id(created)) == True{} : Bool} &
  {Trace.LocalContext.is_sampled(created) == False{} : Bool}

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
#     11) and injection (#10), can rely on these invariants without checking
#     them again.
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
