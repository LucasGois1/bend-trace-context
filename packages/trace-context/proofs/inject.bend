# Proofs: injection and forwarding
# ================================
#
# What Context.clear, Context.inject and Context.forward of trace_context.bend
# write into a carrier, and what a receiver extracts from it. PROOF.bend
# proves the laws of section 13 of LAWS.bend with the lemmas of the same
# names. The module has five parts:
#
#   Carriers             The package keeps the unrelated fields in a loop,
#                        most recent first, and reverses them onto the fields
#                        it adds (Carrier.replace); LAWS.bend states them with
#                        a plain recursion (Laws.unrelated). replace_law shows
#                        that they agree, which gives the cleanup and
#                        injection carriers, and unrelated_again that a
#                        written carrier keeps the same unrelated fields.
#   Injection: what a    The values a receiver selects from a written carrier
#   receiver extracts    are the written ones (carrier_named), its
#                        traceparent value reads back under every limits
#                        (ExtractProof.read_formatted), the emitted state
#                        parses back (EmitProof.emit_accepted), and the
#                        remote context read is the local context's
#                        (ContextProof.emitted_remote).
#   Forwarding: the      The package joins the tracestate fields by loops;
#   carrier written      joined_law shows that they write String.join(fields,
#                        ","), so forwarding writes Laws.written of the
#                        received values (forward_fields).
#   Forwarding: the      Forwarding checks the pair, never the carrier: the
#   checks               *_moved lemmas follow a success into one carrier to
#                        a success into any other, which gives the carrier
#                        written and idempotence.
#   Forwarding: pairs    The pair an extraction keeps reads back
#   that extraction      (ExtractProof.extracted_view), so the *_forwarded
#   keeps                lemmas pass its checks and only the output budget
#                        can refuse it.
#
# As elsewhere, a step lemma receives a value the proof must match on (a
# Bool, a Maybe, a Result) as a parameter, with an equation or a hypothesis
# saying what it is.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ./bools.bend as BoolsProof
import ./strings.bend as StringsProof
import ./lists.bend as ListsProof
import ./tracestate.bend as StateProof
import ./emit.bend as EmitProof
import ./context.bend as ContextProof
import ./extract.bend as ExtractProof

# Carriers
# ========

# The package's test for a context field is Laws.context_name: both compare
# the field name, with its ASCII letters lowered, with the two names
# (ExtractProof.named_step).
law is_context_law:
  for +name: String
  {TC.Carrier.is_context(name) == Laws.context_name(name) : Bool}

def is_context_law(name):
  %Equal.sym(Bool, TC.Carrier.named("traceparent", name), String.eq(String.to_lower(name), "traceparent"),
    ExtractProof.named_step("traceparent", name)) :
    {Bool.or(_, TC.Carrier.named("tracestate", name)) == Laws.context_name(name) : Bool}
  %Equal.sym(Bool, TC.Carrier.named("tracestate", name), String.eq(String.to_lower(name), "tracestate"),
    ExtractProof.named_step("tracestate", name)) :
    {Bool.or(String.eq(String.to_lower(name), "traceparent"), _) == Laws.context_name(name) : Bool}
  {==}

# One step of the loop matches one step of Laws.unrelated: a kept field goes
# in front of what was kept, which reversing turns into its place in order.
law unrelated_step:
  for +kept_rest: List<&2, TC.Header>
  for +header: TC.Header
  for +kept: List<&2, TC.Header>
  for context_field: Bool
  {List.reverse.go(&2, TC.Header, kept_rest, TC.Carrier.keep_unrelated(context_field, header, kept)) ==
    List.reverse.go(&2, TC.Header, Bool.pick(List<&2, TC.Header>, context_field, kept_rest, Con{header, kept_rest}), kept) :
    List<&2, TC.Header>}

def unrelated_step(kept_rest, header, kept, context_field):
  match context_field:
    case True{}:
      {==}
    case False{}:
      {==}

# The loop of Carrier.unrelated.go, from the fields `kept` so far, gives the
# fields Laws.unrelated keeps, reversed, before `kept`. Induction on the
# carrier.
law unrelated_go:
  for +carrier: List<&2, TC.Header>
  for +kept: List<&2, TC.Header>
  {TC.Carrier.unrelated.go(carrier, kept) == List.reverse.go(&2, TC.Header, Laws.unrelated(carrier), kept) :
    List<&2, TC.Header>}

def unrelated_go(carrier, kept):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      %Equal.sym(List<&2, TC.Header>,
        TC.Carrier.unrelated.go(rest, TC.Carrier.keep_unrelated(TC.Carrier.is_context(TC.Header.name(header)), header, kept)),
        List.reverse.go(&2, TC.Header, Laws.unrelated(rest),
          TC.Carrier.keep_unrelated(TC.Carrier.is_context(TC.Header.name(header)), header, kept)),
        unrelated_go(rest, TC.Carrier.keep_unrelated(TC.Carrier.is_context(TC.Header.name(header)), header, kept))) :
        {_ == List.reverse.go(&2, TC.Header, Laws.unrelated(Con{header, rest}), kept) : List<&2, TC.Header>}
      %Equal.sym(Bool, TC.Carrier.is_context(TC.Header.name(header)), Laws.context_name(TC.Header.name(header)),
        is_context_law(TC.Header.name(header))) :
        {List.reverse.go(&2, TC.Header, Laws.unrelated(rest), TC.Carrier.keep_unrelated(_, header, kept)) ==
          List.reverse.go(&2, TC.Header, Laws.unrelated(Con{header, rest}), kept) : List<&2, TC.Header>}
      unrelated_step(Laws.unrelated(rest), header, kept, Laws.context_name(TC.Header.name(header)))

# Replacing the context fields of a carrier with `fields` keeps the other
# fields, in their order, and adds `fields` after them
# (ListsProof.reverse_onto).
law replace_law:
  for +carrier: List<&2, TC.Header>
  for +fields: List<&2, TC.Header>
  {TC.Carrier.replace(carrier, fields) == List.append(&2, TC.Header, Laws.unrelated(carrier), fields) :
    List<&2, TC.Header>}

def replace_law(carrier, fields):
  %Equal.sym(List<&2, TC.Header>, TC.Carrier.unrelated.go(carrier, Nil{}),
    List.reverse.go(&2, TC.Header, Laws.unrelated(carrier), Nil{}), unrelated_go(carrier, Nil{})) :
    {List.reverse.go(&2, TC.Header, _, fields) == List.append(&2, TC.Header, Laws.unrelated(carrier), fields) :
      List<&2, TC.Header>}
  ListsProof.reverse_onto(TC.Header, Laws.unrelated(carrier), Nil{}, fields)

# Law clear_carrier: cleanup replaces the context fields with none.
law clear_carrier:
  for +carrier: List<&2, TC.Header>
  {TC.Context.clear(carrier) == Laws.unrelated(carrier) : List<&2, TC.Header>}

def clear_carrier(carrier):
  Equal.trans(List<&2, TC.Header>, TC.Context.clear(carrier),
    List.append(&2, TC.Header, Laws.unrelated(carrier), Nil{}),
    Laws.unrelated(carrier), replace_law(carrier, Nil{}), ListsProof.append_nil(TC.Header, Laws.unrelated(carrier)))

# The context fields the package writes are those of Laws.written: by cases on
# whether the tracestate value is empty.
law fields_law:
  for traceparent: String
  for +tracestate: String
  {TC.Carrier.context_fields(traceparent, tracestate) == Laws.written(traceparent, tracestate) : List<&2, TC.Header>}

def fields_law(traceparent, tracestate):
  match tracestate:
    case SNil{}:
      {==}
    case SCon{first, rest}:
      {==}

# The carrier an injection of an emission writes, for every emission.
law of_carrier:
  for +carrier: List<&2, TC.Header>
  for +emission: TC.Emission
  {TC.Injection.carrier(TC.Injection.of(carrier, emission)) == List.append(&2, TC.Header, Laws.unrelated(carrier),
    Laws.written(TC.Emission.traceparent(emission), TC.Emission.tracestate(emission))) : List<&2, TC.Header>}

def of_carrier(carrier, emission):
  match emission:
    case TC.Emission{+traceparent, +tracestate, dropped}:
      %Equal.sym(List<&2, TC.Header>, TC.Carrier.context_fields(traceparent, tracestate),
        Laws.written(traceparent, tracestate), fields_law(traceparent, tracestate)) :
        {TC.Carrier.replace(carrier, _) == List.append(&2, TC.Header, Laws.unrelated(carrier),
          Laws.written(traceparent, tracestate)) : List<&2, TC.Header>}
      replace_law(carrier, Laws.written(traceparent, tracestate))

# Law inject_carrier: injection is the injection of the outgoing context's
# emission.
law inject_carrier:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for +carrier: List<&2, TC.Header>
  {TC.Injection.carrier(TC.Context.inject(limits, outgoing, carrier)) ==
    List.append(&2, TC.Header, Laws.unrelated(carrier),
      Laws.written(TC.Emission.traceparent(TC.OutgoingContext.emit(limits, outgoing)),
        TC.Emission.tracestate(TC.OutgoingContext.emit(limits, outgoing)))) : List<&2, TC.Header>}

def inject_carrier(limits, outgoing, carrier):
  of_carrier(carrier, TC.OutgoingContext.emit(limits, outgoing))

# The keys an injection of an emission reports are the emission's.
law of_dropped:
  for carrier: List<&2, TC.Header>
  for emission: TC.Emission
  {TC.Injection.dropped(TC.Injection.of(carrier, emission)) == TC.Emission.dropped(emission) : List<&2, TC.StateKey>}

def of_dropped(carrier, emission):
  match emission:
    case TC.Emission{traceparent, tracestate, dropped}:
      {==}

# Law inject_dropped.
law inject_dropped:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for carrier: List<&2, TC.Header>
  {TC.Injection.dropped(TC.Context.inject(limits, outgoing, carrier)) ==
    TC.Emission.dropped(TC.OutgoingContext.emit(limits, outgoing)) : List<&2, TC.StateKey>}

def inject_dropped(limits, outgoing, carrier):
  of_dropped(carrier, TC.OutgoingContext.emit(limits, outgoing))

# The step of unrelated_append for a first field, with `context_field`
# standing for whether it is a context field and `later` the lemma for the
# rest.
law unrelated_append_step:
  for +header: TC.Header
  for +rest: List<&2, TC.Header>
  for +after: List<&2, TC.Header>
  for context_field: Bool
  for later: {Laws.unrelated(List.append(&2, TC.Header, rest, after)) ==
    List.append(&2, TC.Header, Laws.unrelated(rest), Laws.unrelated(after)) : List<&2, TC.Header>}
  {Bool.pick(List<&2, TC.Header>, context_field, Laws.unrelated(List.append(&2, TC.Header, rest, after)),
    Con{header, Laws.unrelated(List.append(&2, TC.Header, rest, after))}) ==
    List.append(&2, TC.Header, Bool.pick(List<&2, TC.Header>, context_field, Laws.unrelated(rest),
      Con{header, Laws.unrelated(rest)}), Laws.unrelated(after)) : List<&2, TC.Header>}

def unrelated_append_step(header, rest, after, context_field, later):
  match context_field:
    case True{}:
      later
    case False{}:
      %Equal.sym(List<&2, TC.Header>, Laws.unrelated(List.append(&2, TC.Header, rest, after)),
        List.append(&2, TC.Header, Laws.unrelated(rest), Laws.unrelated(after)), later) :
        {Con{header, _} == Con{header, List.append(&2, TC.Header, Laws.unrelated(rest), Laws.unrelated(after))} :
          List<&2, TC.Header>}
      {==}

# The unrelated fields of two carriers joined are those of each, joined.
# Induction on the first carrier.
law unrelated_append:
  for +carrier: List<&2, TC.Header>
  for +after: List<&2, TC.Header>
  {Laws.unrelated(List.append(&2, TC.Header, carrier, after)) ==
    List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.unrelated(after)) : List<&2, TC.Header>}

def unrelated_append(carrier, after):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      unrelated_append_step(header, rest, after, Laws.context_name(TC.Header.name(header)),
        unrelated_append(rest, after))

# The step of unrelated_twice for a first field.
law unrelated_twice_step:
  for +header: TC.Header
  for +rest: List<&2, TC.Header>
  for context_field: Bool
  for evidence: {Laws.context_name(TC.Header.name(header)) == context_field : Bool}
  for later: {Laws.unrelated(Laws.unrelated(rest)) == Laws.unrelated(rest) : List<&2, TC.Header>}
  {Laws.unrelated(Bool.pick(List<&2, TC.Header>, context_field, Laws.unrelated(rest), Con{header, Laws.unrelated(rest)})) ==
    Bool.pick(List<&2, TC.Header>, context_field, Laws.unrelated(rest), Con{header, Laws.unrelated(rest)}) :
    List<&2, TC.Header>}

def unrelated_twice_step(header, rest, context_field, evidence, later):
  match context_field:
    case True{}:
      later
    case False{}:
      %Equal.sym(Bool, Laws.context_name(TC.Header.name(header)), False{}, evidence) :
        {Bool.pick(List<&2, TC.Header>, _, Laws.unrelated(Laws.unrelated(rest)),
          Con{header, Laws.unrelated(Laws.unrelated(rest))}) == Con{header, Laws.unrelated(rest)} : List<&2, TC.Header>}
      %Equal.sym(List<&2, TC.Header>, Laws.unrelated(Laws.unrelated(rest)), Laws.unrelated(rest), later) :
        {Con{header, _} == Con{header, Laws.unrelated(rest)} : List<&2, TC.Header>}
      {==}

# The fields Laws.unrelated keeps have none to remove. Induction on the
# carrier.
law unrelated_twice:
  for +carrier: List<&2, TC.Header>
  {Laws.unrelated(Laws.unrelated(carrier)) == Laws.unrelated(carrier) : List<&2, TC.Header>}

def unrelated_twice(carrier):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      unrelated_twice_step(header, rest, Laws.context_name(TC.Header.name(header)), {==}, unrelated_twice(rest))

# The context fields that are written are all context fields. By cases on
# whether the tracestate value is empty; each case computes.
law unrelated_written:
  for traceparent: String
  for tracestate: String
  {Laws.unrelated(Laws.written(traceparent, tracestate)) == Nil{} : List<&2, TC.Header>}

def unrelated_written(traceparent, tracestate):
  match tracestate:
    case SNil{}:
      {==}
    case SCon{first, rest}:
      {==}

# A carrier of unrelated fields followed by written context fields keeps the
# unrelated fields when its context fields are replaced.
law unrelated_again:
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: String
  {Laws.unrelated(List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))) ==
    Laws.unrelated(carrier) : List<&2, TC.Header>}

def unrelated_again(carrier, traceparent, tracestate):
  %Equal.sym(List<&2, TC.Header>,
    Laws.unrelated(List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))),
    List.append(&2, TC.Header, Laws.unrelated(Laws.unrelated(carrier)),
      Laws.unrelated(Laws.written(traceparent, tracestate))),
    unrelated_append(Laws.unrelated(carrier), Laws.written(traceparent, tracestate))) :
    {_ == Laws.unrelated(carrier) : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, Laws.unrelated(Laws.unrelated(carrier)), Laws.unrelated(carrier),
    unrelated_twice(carrier)) :
    {List.append(&2, TC.Header, _, Laws.unrelated(Laws.written(traceparent, tracestate))) == Laws.unrelated(carrier) :
      List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, Laws.unrelated(Laws.written(traceparent, tracestate)), Nil{},
    unrelated_written(traceparent, tracestate)) :
    {List.append(&2, TC.Header, Laws.unrelated(carrier), _) == Laws.unrelated(carrier) : List<&2, TC.Header>}
  ListsProof.append_nil(TC.Header, Laws.unrelated(carrier))

# Law inject_idempotent: by inject_carrier, the second injection writes the
# unrelated fields of the first carrier, which are those of the original
# (unrelated_again), followed by the same context fields.
law inject_idempotent:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for +carrier: List<&2, TC.Header>
  {TC.Injection.carrier(TC.Context.inject(limits, outgoing,
    TC.Injection.carrier(TC.Context.inject(limits, outgoing, carrier)))) ==
    TC.Injection.carrier(TC.Context.inject(limits, outgoing, carrier)) : List<&2, TC.Header>}

def inject_idempotent(limits, outgoing, carrier):
  +traceparent = TC.Emission.traceparent(TC.OutgoingContext.emit(limits, outgoing))
  +tracestate = TC.Emission.tracestate(TC.OutgoingContext.emit(limits, outgoing))
  %Equal.sym(List<&2, TC.Header>, TC.Injection.carrier(TC.Context.inject(limits, outgoing, carrier)),
    List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate)),
    inject_carrier(limits, outgoing, carrier)) :
    {TC.Injection.carrier(TC.Context.inject(limits, outgoing, _)) == _ : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, TC.Injection.carrier(TC.Context.inject(limits, outgoing,
      List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate)))),
    List.append(&2, TC.Header, Laws.unrelated(List.append(&2, TC.Header, Laws.unrelated(carrier),
      Laws.written(traceparent, tracestate))), Laws.written(traceparent, tracestate)),
    inject_carrier(limits, outgoing,
      List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate)))) :
    {_ == List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate)) : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>,
    Laws.unrelated(List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))),
    Laws.unrelated(carrier), unrelated_again(carrier, traceparent, tracestate)) :
    {List.append(&2, TC.Header, _, Laws.written(traceparent, tracestate)) ==
      List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate)) : List<&2, TC.Header>}
  {==}

# Injection: what a receiver extracts
# ===================================
#
# The carrier an injection writes holds its unrelated fields, none of which
# is a context field, and exactly one traceparent field, followed by one
# tracestate field unless the state is empty. The receiver reads the
# traceparent value, which every budget admits, as the value injected
# (ExtractProof.read_formatted), and the tracestate value as the state
# emitted (EmitProof.emit_accepted).

# The step of named_append for a first field, with `hit` standing for
# whether its name is the one sought and `later` the lemma for the rest.
law named_append_step:
  for +name: String
  for +header: TC.Header
  for +rest: List<&2, TC.Header>
  for +after: List<&2, TC.Header>
  for hit: Bool
  for later: {Laws.named(name, List.append(&2, TC.Header, rest, after)) ==
    List.append(&2, String, Laws.named(name, rest), Laws.named(name, after)) : List<&2, String>}
  {Bool.pick(List<&2, String>, hit,
    Con{TC.Header.value(header), Laws.named(name, List.append(&2, TC.Header, rest, after))},
    Laws.named(name, List.append(&2, TC.Header, rest, after))) ==
    List.append(&2, String, Bool.pick(List<&2, String>, hit, Con{TC.Header.value(header), Laws.named(name, rest)},
      Laws.named(name, rest)), Laws.named(name, after)) : List<&2, String>}

def named_append_step(name, header, rest, after, hit, later):
  match hit:
    case True{}:
      %Equal.sym(List<&2, String>, Laws.named(name, List.append(&2, TC.Header, rest, after)),
        List.append(&2, String, Laws.named(name, rest), Laws.named(name, after)), later) :
        {Con{TC.Header.value(header), _} ==
          Con{TC.Header.value(header), List.append(&2, String, Laws.named(name, rest), Laws.named(name, after))} :
          List<&2, String>}
      {==}
    case False{}:
      later

# The values named in two carriers joined are those of each, joined.
# Induction on the first carrier.
law named_append:
  for +name: String
  for +carrier: List<&2, TC.Header>
  for +after: List<&2, TC.Header>
  {Laws.named(name, List.append(&2, TC.Header, carrier, after)) ==
    List.append(&2, String, Laws.named(name, carrier), Laws.named(name, after)) : List<&2, String>}

def named_append(name, carrier, after):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      named_append_step(name, header, rest, after, String.eq(String.to_lower(TC.Header.name(header)), name),
        named_append(name, rest, after))

# The step of parent_unrelated and state_unrelated for a first field, with
# `context_field` standing for whether it is a context field: a kept field is
# not one, so `excluded` says that its name is not the one sought.
law unrelated_named_step:
  for +name: String
  for +header: TC.Header
  for +rest: List<&2, TC.Header>
  for context_field: Bool
  for evidence: {Laws.context_name(TC.Header.name(header)) == context_field : Bool}
  for excluded: {Laws.context_name(TC.Header.name(header)) == False{} : Bool} ->
    {String.eq(String.to_lower(TC.Header.name(header)), name) == False{} : Bool}
  for later: {Laws.named(name, Laws.unrelated(rest)) == Nil{} : List<&2, String>}
  {Laws.named(name, Bool.pick(List<&2, TC.Header>, context_field, Laws.unrelated(rest), Con{header, Laws.unrelated(rest)})) ==
    Nil{} : List<&2, String>}

def unrelated_named_step(name, header, rest, context_field, evidence, excluded, later):
  match context_field:
    case True{}:
      later
    case False{}:
      %Equal.sym(Bool, String.eq(String.to_lower(TC.Header.name(header)), name), False{}, excluded(evidence)) :
        {Bool.pick(List<&2, String>, _, Con{TC.Header.value(header), Laws.named(name, Laws.unrelated(rest))},
          Laws.named(name, Laws.unrelated(rest))) == Nil{} : List<&2, String>}
      later

# The unrelated fields hold no traceparent field. Induction on the carrier.
law parent_unrelated:
  for +carrier: List<&2, TC.Header>
  {Laws.named("traceparent", Laws.unrelated(carrier)) == Nil{} : List<&2, String>}

def parent_unrelated(carrier):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      unrelated_named_step("traceparent", header, rest, Laws.context_name(TC.Header.name(header)), {==},
        other => BoolsProof.or_left_false(String.eq(String.to_lower(TC.Header.name(header)), "traceparent"),
          String.eq(String.to_lower(TC.Header.name(header)), "tracestate"), other),
        parent_unrelated(rest))

# The unrelated fields hold no tracestate field. Induction on the carrier.
law state_unrelated:
  for +carrier: List<&2, TC.Header>
  {Laws.named("tracestate", Laws.unrelated(carrier)) == Nil{} : List<&2, String>}

def state_unrelated(carrier):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      unrelated_named_step("tracestate", header, rest, Laws.context_name(TC.Header.name(header)), {==},
        other => BoolsProof.or_right_false(String.eq(String.to_lower(TC.Header.name(header)), "traceparent"),
          String.eq(String.to_lower(TC.Header.name(header)), "tracestate"), other),
        state_unrelated(rest))

# The values of a context field in a written carrier are those of the
# written context fields, when the unrelated fields hold none (`none`).
law carrier_named:
  for +name: String
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: String
  for none: {Laws.named(name, Laws.unrelated(carrier)) == Nil{} : List<&2, String>}
  {Laws.named(name, List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))) ==
    Laws.named(name, Laws.written(traceparent, tracestate)) : List<&2, String>}

def carrier_named(name, carrier, traceparent, tracestate, none):
  %Equal.sym(List<&2, String>,
    Laws.named(name, List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))),
    List.append(&2, String, Laws.named(name, Laws.unrelated(carrier)),
      Laws.named(name, Laws.written(traceparent, tracestate))),
    named_append(name, Laws.unrelated(carrier), Laws.written(traceparent, tracestate))) :
    {_ == Laws.named(name, Laws.written(traceparent, tracestate)) : List<&2, String>}
  %Equal.sym(List<&2, String>, Laws.named(name, Laws.unrelated(carrier)), Nil{}, none) :
    {List.append(&2, String, _, Laws.named(name, Laws.written(traceparent, tracestate))) ==
      Laws.named(name, Laws.written(traceparent, tracestate)) : List<&2, String>}
  {==}

# The written context fields hold one traceparent value. By cases on
# whether the tracestate value is empty; each case computes.
law written_parent:
  for traceparent: String
  for +tracestate: String
  {Laws.named("traceparent", Laws.written(traceparent, tracestate)) == Con{traceparent, Nil{}} : List<&2, String>}

def written_parent(traceparent, tracestate):
  match tracestate:
    case SNil{}:
      {==}
    case SCon{first, rest}:
      {==}

# What a receiver finds in an extraction: an accepted traceparent, the
# sender's operation `remote`, and the received entries `entries`.
def Found(+extraction: TC.Extraction, remote: TC.RemoteContext, entries: List<&2, TC.StateEntry>) -> Type:
  {TC.Extraction.parent(extraction) == TC.TraceParentAccepted{} : TC.TraceParentOutcome} &
  {Laws.sender(extraction) == Some{remote} : Maybe<&2, TC.RemoteContext>} &
  {Laws.received_entries(extraction) == entries : List<&2, TC.StateEntry>}

# An accepted traceparent with the written tracestate field, if any, whose
# value parses as `state`: without one, the empty value parses as a state
# without entries, so `state` has none.
law state_found:
  for +limits: TC.Limits
  for traceparent: String
  for +text: String
  for +state: TC.TraceState
  for +remote: TC.RemoteContext
  for kept: String
  for accepted: {TC.TraceState.parse(limits, text) == Done{state} : Result<&2, &2, TC.StateError, TC.TraceState>}
  Found(TC.Extract.state(limits, Laws.named("tracestate", Laws.written(traceparent, text)), remote, kept), remote,
    TC.TraceState.entries(state))

def state_found(limits, traceparent, text, state, remote, kept, accepted):
  match text:
    case SNil{}:
      ({==}, ({==}, Equal.cong(Result<&2, &2, TC.StateError, TC.TraceState>, List<&2, TC.StateEntry>,
        result => TC.TraceState.entries(Result.default(&2, &2, TC.StateError, TC.TraceState, result,
          TC.TraceState.empty())), TC.TraceState.parse(limits, SNil{}), Done{state}, accepted)))
    case SCon{+first, +rest}:
      %Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>, TC.TraceState.parse(limits, SCon{first, rest}),
        Done{state}, accepted) :
        Found(TC.Extract.parsed(_, remote, kept, Con{SCon{first, rest}, Nil{}}), remote, TC.TraceState.entries(state))
      ({==}, ({==}, {==}))

# A receiver of a written carrier finds the injected value's operation and
# the state whose text was written: the selected values are the written
# ones (carrier_named, parent_unrelated, state_unrelated, written_parent), and
# the traceparent value reads as `known` (read_formatted).
law carrier_found:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +known: TC.TraceParentV00
  for +text: String
  for +state: TC.TraceState
  for +base: Maybe<&2, TC.BaseContext>
  for accepted: {TC.TraceState.parse(limits, text) == Done{state} : Result<&2, &2, TC.StateError, TC.TraceState>}
  Found(TC.Context.extract(limits, List.append(&2, TC.Header, Laws.unrelated(carrier),
    Laws.written(TC.TraceParentV00.format(known), text)), base), TC.RemoteContext.from_traceparent(known),
    TC.TraceState.entries(state))

def carrier_found(limits, carrier, known, text, state, base, accepted):
  +traceparent = TC.TraceParentV00.format(known)
  +written_carrier = List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, text))
  +remote = TC.RemoteContext.from_traceparent(known)
  +entries = TC.TraceState.entries(state)
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, written_carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", written_carrier), Laws.named("tracestate", written_carrier), base),
    ExtractProof.extract_named(limits, written_carrier, base)) :
    Found(_, remote, entries)
  %Equal.sym(List<&2, String>, Laws.named("traceparent", written_carrier),
    Laws.named("traceparent", Laws.written(traceparent, text)),
    carrier_named("traceparent", carrier, traceparent, text, parent_unrelated(carrier))) :
    Found(TC.Extract.parents(limits, _, Laws.named("tracestate", written_carrier), base), remote, entries)
  %Equal.sym(List<&2, String>, Laws.named("traceparent", Laws.written(traceparent, text)), Con{traceparent, Nil{}},
    written_parent(traceparent, text)) :
    Found(TC.Extract.parents(limits, _, Laws.named("tracestate", written_carrier), base), remote, entries)
  %Equal.sym(List<&2, String>, Laws.named("tracestate", written_carrier),
    Laws.named("tracestate", Laws.written(traceparent, text)),
    carrier_named("tracestate", carrier, traceparent, text, state_unrelated(carrier))) :
    Found(TC.Extract.parents(limits, Con{traceparent, Nil{}}, _, base), remote, entries)
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, traceparent),
    Done{known}, ExtractProof.read_formatted(limits, known)) :
    Found(TC.Extract.read(_, traceparent, limits, Laws.named("tracestate", Laws.written(traceparent, text)), base), remote,
      entries)
  state_found(limits, traceparent, text, state, remote, TC.Text.trim_ows(traceparent), accepted)

# Law inject_extracted: the carrier is the unrelated fields and the emitted
# ones (inject_carrier), whose receiver finds the injected operation
# (carrier_found, ContextProof.emitted_remote) and the truncated state, which
# the emitted value parses as (EmitProof.emit_accepted).
law inject_extracted:
  for +limits: TC.Limits
  for +outgoing: TC.OutgoingContext
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  {TC.Extraction.parent(Laws.reinjected(limits, outgoing, carrier, base)) == TC.TraceParentAccepted{} :
    TC.TraceParentOutcome} &
  {Laws.sender(Laws.reinjected(limits, outgoing, carrier, base)) ==
    Some{Laws.projection(TC.OutgoingContext.context(outgoing))} : Maybe<&2, TC.RemoteContext>} &
  {Laws.received_entries(Laws.reinjected(limits, outgoing, carrier, base)) == TC.TraceState.entries(
    TC.Truncation.kept(TC.TraceState.truncate(limits, TC.OutgoingContext.state(outgoing)))) :
    List<&2, TC.StateEntry>}

def inject_extracted(limits, outgoing, carrier, base):
  match outgoing:
    case TC.OutgoingContext{+context, +state}:
      +kept = TC.Truncation.kept(TC.TraceState.truncate(limits, state))
      +known = TC.LocalContext.to_traceparent(context)
      %ContextProof.emitted_remote(context) :
        Found(Laws.reinjected(limits, TC.OutgoingContext{context, state}, carrier, base), _,
          TC.TraceState.entries(kept))
      %Equal.sym(List<&2, TC.Header>,
        TC.Injection.carrier(TC.Context.inject(limits, TC.OutgoingContext{context, state}, carrier)),
        List.append(&2, TC.Header, Laws.unrelated(carrier),
          Laws.written(TC.TraceParentV00.format(known), TC.TraceState.format(kept))),
        inject_carrier(limits, TC.OutgoingContext{context, state}, carrier)) :
        Found(TC.Context.extract(limits, _, base), TC.RemoteContext.from_traceparent(known),
          TC.TraceState.entries(kept))
      carrier_found(limits, carrier, known, TC.TraceState.format(kept), kept, base,
        EmitProof.emit_accepted(limits, TC.OutgoingContext{context, state}))

# Forwarding: the carrier written
# ===============================

# The loop of Text.joined, from `first` reversed onto `done`, gives `first`
# and the fields of `rest`, joined by commas, reversed onto `done`. Induction
# on `rest`, with StringsProof.reverse_append at each comma.
law joined_go:
  for +rest: List<&2, String>
  for +first: String
  for +done: String
  {TC.Text.joined.go(rest, String.reverse.go(first, done)) ==
    String.reverse.go(String.join.go(rest, first, ","), done) : String}

def joined_go(rest, first, done):
  match rest:
    case Nil{}:
      {==}
    case Con{+next, +later}:
      Equal.trans(String, TC.Text.joined.go(Con{next, later}, String.reverse.go(first, done)),
        String.reverse.go(String.join.go(later, next, ","), SCon{',', String.reverse.go(first, done)}),
        String.reverse.go(String.join.go(Con{next, later}, first, ","), done),
        joined_go(later, next, SCon{',', String.reverse.go(first, done)}),
        Equal.sym(String, String.reverse.go(String.join.go(Con{next, later}, first, ","), done),
          String.reverse.go(String.join.go(later, next, ","), SCon{',', String.reverse.go(first, done)}),
          StringsProof.reverse_append(first, "," ++ String.join.go(later, next, ","), done)))

# The package joins the tracestate fields by loops, and String.join by a
# plain recursion; both write the fields joined by commas. Reversing the
# loop's result gives the joined text back (StringsProof.reverse_twice).
law joined_law:
  for +fields: List<&2, String>
  {TC.Text.joined(fields) == String.join(fields, ",") : String}

def joined_law(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{+first, +rest}:
      %Equal.sym(String, TC.Text.joined.go(rest, String.reverse.go(first, SNil{})),
        String.reverse.go(String.join.go(rest, first, ","), SNil{}), joined_go(rest, first, SNil{})) :
        {String.reverse(_) == String.join.go(rest, first, ",") : String}
      StringsProof.reverse_twice(String.join.go(rest, first, ","), SNil{})

# The carrier forwarding writes: the unrelated fields, followed by the fields
# of Laws.written for the traceparent value and the joined tracestate fields.
law forward_fields:
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  {TC.Forward.carrier(carrier, traceparent, tracestate) == List.append(&2, TC.Header, Laws.unrelated(carrier),
    Laws.written(traceparent, String.join(tracestate, ","))) : List<&2, TC.Header>}

def forward_fields(carrier, traceparent, tracestate):
  %Equal.sym(String, TC.Text.joined(tracestate), String.join(tracestate, ","), joined_law(tracestate)) :
    {TC.Carrier.replace(carrier, TC.Carrier.context_fields(traceparent, _)) == List.append(&2, TC.Header,
      Laws.unrelated(carrier), Laws.written(traceparent, String.join(tracestate, ","))) : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, TC.Carrier.context_fields(traceparent, String.join(tracestate, ",")),
    Laws.written(traceparent, String.join(tracestate, ",")), fields_law(traceparent, String.join(tracestate, ","))) :
    {TC.Carrier.replace(carrier, _) == List.append(&2, TC.Header, Laws.unrelated(carrier),
      Laws.written(traceparent, String.join(tracestate, ","))) : List<&2, TC.Header>}
  replace_law(carrier, Laws.written(traceparent, String.join(tracestate, ",")))

# Forwarding the same fields into the carrier forwarding wrote writes that
# carrier again: its unrelated fields are those of the first carrier
# (unrelated_again), followed by the same fields.
law carrier_again:
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  {TC.Forward.carrier(TC.Forward.carrier(carrier, traceparent, tracestate), traceparent, tracestate) ==
    TC.Forward.carrier(carrier, traceparent, tracestate) : List<&2, TC.Header>}

def carrier_again(carrier, traceparent, tracestate):
  +joined = String.join(tracestate, ",")
  +once = List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, joined))
  %Equal.sym(List<&2, TC.Header>, TC.Forward.carrier(carrier, traceparent, tracestate), once,
    forward_fields(carrier, traceparent, tracestate)) :
    {TC.Forward.carrier(_, traceparent, tracestate) == _ : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, TC.Forward.carrier(once, traceparent, tracestate),
    List.append(&2, TC.Header, Laws.unrelated(once), Laws.written(traceparent, joined)),
    forward_fields(once, traceparent, tracestate)) :
    {_ == once : List<&2, TC.Header>}
  %Equal.sym(List<&2, TC.Header>, Laws.unrelated(once), Laws.unrelated(carrier),
    unrelated_again(carrier, traceparent, joined)) :
    {List.append(&2, TC.Header, _, Laws.written(traceparent, joined)) == once : List<&2, TC.Header>}
  {==}

# Forwarding: the checks
# ======================
#
# Forward.pair, Forward.fits, Forward.parent and Forward.state check the
# pair, never the carrier. The lemmas follow those checks, one per step, last
# first, from a success into one carrier to a success into any other
# (*_moved).

# Done is injective: when Done{value} equals Done{other}, so do the carriers.
law done_injective:
  for +value: List<&2, TC.Header>
  for -other: List<&2, TC.Header>
  for same: {Done{value} == Done{other} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {value == other : List<&2, TC.Header>}

# Equal.cong with Result.default, which takes the carrier out of both sides.
def done_injective(value, other, same):
  Equal.cong(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, List<&2, TC.Header>,
    result => Result.default(&2, &2, TC.ForwardError, List<&2, TC.Header>, result, value), Done{value}, Done{other},
    same)

# A refusal is not a success: from {Fail{error} == Done{forwarded}}, anything
# follows (ExtractProof.done_ne_fail).
def refused(-A: Type, -error: TC.ForwardError, -forwarded: List<&2, TC.Header>,
  clash: {Fail{error} == Done{forwarded} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}) -> A:
  Empty.absurd(A, ExtractProof.done_ne_fail(TC.ForwardError, List<&2, TC.Header>, forwarded, error,
    Equal.sym(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, Fail{error}, Done{forwarded}, clash)))

# The last check passes into any carrier once it passes into one.
law state_moved:
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for carrier: List<&2, TC.Header>
  for +other: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for -forwarded: List<&2, TC.Header>
  for done: {TC.Forward.state(parsed, carrier, traceparent, tracestate) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.state(parsed, other, traceparent, tracestate) ==
    Done{TC.Forward.carrier(other, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def state_moved(parsed, carrier, other, traceparent, tracestate, forwarded, done):
  match parsed:
    case Fail{error}:
      refused({TC.Forward.state(Fail{error}, other, traceparent, tracestate) ==
        Done{TC.Forward.carrier(other, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, TC.InvalidForwardState{error}, forwarded, done)
    case Done{state}:
      {==}

# The traceparent check, then the last one.
law parent_moved:
  for read: Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>
  for +limits: TC.Limits
  for carrier: List<&2, TC.Header>
  for +other: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for -forwarded: List<&2, TC.Header>
  for done: {TC.Forward.parent(read, limits, carrier, traceparent, tracestate) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.parent(read, limits, other, traceparent, tracestate) ==
    Done{TC.Forward.carrier(other, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def parent_moved(read, limits, carrier, other, traceparent, tracestate, forwarded, done):
  match read:
    case Fail{error}:
      refused({TC.Forward.parent(Fail{error}, limits, other, traceparent, tracestate) ==
        Done{TC.Forward.carrier(other, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, TC.InvalidForwardParent{error}, forwarded, done)
    case Done{known}:
      state_moved(TC.TraceState.parse_fields(limits, tracestate), carrier, other, traceparent, tracestate, forwarded,
        done)

# The budget check, then the others.
law fits_moved:
  for fits: Maybe<&2, Nat>
  for +limits: TC.Limits
  for carrier: List<&2, TC.Header>
  for +other: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for -forwarded: List<&2, TC.Header>
  for done: {TC.Forward.fits(fits, limits, carrier, traceparent, tracestate) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.fits(fits, limits, other, traceparent, tracestate) ==
    Done{TC.Forward.carrier(other, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def fits_moved(fits, limits, carrier, other, traceparent, tracestate, forwarded, done):
  match fits:
    case None{}:
      refused({TC.Forward.fits(None{}, limits, other, traceparent, tracestate) ==
        Done{TC.Forward.carrier(other, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, TC.ForwardTooLarge{}, forwarded, done)
    case Some{left}:
      parent_moved(TC.TraceParent.read(limits, traceparent), limits, carrier, other, traceparent, tracestate,
        forwarded, done)

# A received pair that is forwarded into one carrier is forwarded into any
# other, which gets the same fields.
law pair_moved:
  for +limits: TC.Limits
  for +pair: TC.ReceivedPair
  for carrier: List<&2, TC.Header>
  for +other: List<&2, TC.Header>
  for -forwarded: List<&2, TC.Header>
  for done: {TC.Forward.pair(limits, Some{pair}, carrier) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.pair(limits, Some{pair}, other) == Done{TC.Forward.carrier(other, TC.ReceivedPair.traceparent(pair),
    TC.ReceivedPair.tracestate(pair))} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def pair_moved(limits, pair, carrier, other, forwarded, done):
  match pair:
    case TC.ReceivedPair{+traceparent, +tracestate}:
      fits_moved(TC.Utf8.left_fields(tracestate, Some{TC.Limits.tracestate_output(limits)}), limits, carrier, other,
        traceparent, tracestate, forwarded, done)

# When forwarding a pair succeeds with `forwarded`, `forwarded` is the
# carrier Forward.carrier writes: pair_moved into the same carrier gives it.
law pair_done:
  for +limits: TC.Limits
  for +pair: TC.ReceivedPair
  for +carrier: List<&2, TC.Header>
  for +forwarded: List<&2, TC.Header>
  for +done: {TC.Forward.pair(limits, Some{pair}, carrier) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.carrier(carrier, TC.ReceivedPair.traceparent(pair), TC.ReceivedPair.tracestate(pair)) == forwarded :
    List<&2, TC.Header>}

def pair_done(limits, pair, carrier, forwarded, done):
  +written = TC.Forward.carrier(carrier, TC.ReceivedPair.traceparent(pair), TC.ReceivedPair.tracestate(pair))
  done_injective(written, forwarded,
    Equal.trans(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, Done{written},
      TC.Forward.pair(limits, Some{pair}, carrier), Done{forwarded},
      Equal.sym(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, TC.Forward.pair(limits, Some{pair}, carrier),
        Done{written}, pair_moved(limits, pair, carrier, carrier, forwarded, done)),
      done))

# Law forward_carrier: `kept` turns `done` into the forwarding of the pair
# (Equal.cong), which writes Forward.carrier (pair_done), the unrelated
# fields and the received fields (forward_fields).
law forward_carrier:
  for +limits: TC.Limits
  for +incoming: TC.IncomingContext
  for +carrier: List<&2, TC.Header>
  for +pair: TC.ReceivedPair
  for +forwarded: List<&2, TC.Header>
  for kept: {TC.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, TC.ReceivedPair>}
  for done: {TC.Context.forward(limits, incoming, carrier) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {forwarded == List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(TC.ReceivedPair.traceparent(pair),
    String.join(TC.ReceivedPair.tracestate(pair), ","))) : List<&2, TC.Header>}

def forward_carrier(limits, incoming, carrier, pair, forwarded, kept, done):
  +traceparent = TC.ReceivedPair.traceparent(pair)
  +tracestate = TC.ReceivedPair.tracestate(pair)
  +forwarding = Equal.trans(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>,
    TC.Forward.pair(limits, Some{pair}, carrier), TC.Context.forward(limits, incoming, carrier), Done{forwarded},
    Equal.cong(Maybe<&2, TC.ReceivedPair>, Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>,
      received => TC.Forward.pair(limits, received, carrier), Some{pair}, TC.IncomingContext.received(incoming),
      Equal.sym(Maybe<&2, TC.ReceivedPair>, TC.IncomingContext.received(incoming), Some{pair}, kept)),
    done)
  Equal.trans(List<&2, TC.Header>, forwarded, TC.Forward.carrier(carrier, traceparent, tracestate),
    List.append(&2, TC.Header, Laws.unrelated(carrier), Laws.written(traceparent, String.join(tracestate, ","))),
    Equal.sym(List<&2, TC.Header>, TC.Forward.carrier(carrier, traceparent, tracestate), forwarded,
      pair_done(limits, pair, carrier, forwarded, forwarding)),
    forward_fields(carrier, traceparent, tracestate))

# Law forward_nothing: without a received pair, Forward.pair refuses at once.
law forward_nothing:
  for +limits: TC.Limits
  for +incoming: TC.IncomingContext
  for +carrier: List<&2, TC.Header>
  for none: {TC.IncomingContext.received(incoming) == None{} : Maybe<&2, TC.ReceivedPair>}
  {TC.Context.forward(limits, incoming, carrier) == Fail{TC.NothingToForward{}} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def forward_nothing(limits, incoming, carrier, none):
  %Equal.sym(Maybe<&2, TC.ReceivedPair>, TC.IncomingContext.received(incoming), None{}, none) :
    {TC.Forward.pair(limits, _, carrier) == Fail{TC.NothingToForward{}} :
      Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {==}

# Measuring the tracestate fields against a budget succeeds exactly when
# their comma-joined text fits it (StateProof.fields_left and within).
law fields_within:
  for +fields: List<&2, String>
  for +budget: Nat
  {Maybe.is_some(&2, Nat, TC.Utf8.left_fields(fields, Some{budget})) ==
    Nat.is_le(TC.Utf8.length(String.join(fields, ",")), budget) : Bool}

def fields_within(fields, budget):
  %Equal.sym(Maybe<&2, Nat>, TC.Utf8.left_fields(fields, Some{budget}),
    TC.Utf8.left(String.join(fields, ","), Some{budget}), StateProof.fields_left(fields, budget)) :
    {Maybe.is_some(&2, Nat, _) == Nat.is_le(TC.Utf8.length(String.join(fields, ",")), budget) : Bool}
  StateProof.within(String.join(fields, ","), budget)

# A measurement over the budget refuses the pair, whatever the rest. The Some
# case contradicts `larger`.
law fits_over:
  for fits: Maybe<&2, Nat>
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for larger: {Maybe.is_some(&2, Nat, fits) == False{} : Bool}
  {TC.Forward.fits(fits, limits, carrier, traceparent, tracestate) == Fail{TC.ForwardTooLarge{}} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def fits_over(fits, limits, carrier, traceparent, tracestate, larger):
  match fits:
    case None{}:
      {==}
    case Some{left}:
      Empty.absurd({TC.Forward.fits(Some{left}, limits, carrier, traceparent, tracestate) ==
        Fail{TC.ForwardTooLarge{}} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>},
        BoolsProof.true_ne_false(larger))

# A pair whose joined tracestate is over the output budget is refused.
law pair_too_large:
  for +limits: TC.Limits
  for +pair: TC.ReceivedPair
  for +carrier: List<&2, TC.Header>
  for larger: {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")),
    TC.Limits.tracestate_output(limits)) == False{} : Bool}
  {TC.Forward.pair(limits, Some{pair}, carrier) == Fail{TC.ForwardTooLarge{}} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def pair_too_large(limits, pair, carrier, larger):
  match pair:
    case TC.ReceivedPair{+traceparent, +tracestate}:
      fits_over(TC.Utf8.left_fields(tracestate, Some{TC.Limits.tracestate_output(limits)}), limits, carrier,
        traceparent, tracestate,
        Equal.trans(Bool,
          Maybe.is_some(&2, Nat, TC.Utf8.left_fields(tracestate, Some{TC.Limits.tracestate_output(limits)})),
          Nat.is_le(TC.Utf8.length(String.join(tracestate, ",")), TC.Limits.tracestate_output(limits)), False{},
          fields_within(tracestate, TC.Limits.tracestate_output(limits)), larger))

# Law forward_too_large: `kept` names the pair, which pair_too_large refuses.
law forward_too_large:
  for +limits: TC.Limits
  for +incoming: TC.IncomingContext
  for +carrier: List<&2, TC.Header>
  for +pair: TC.ReceivedPair
  for kept: {TC.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, TC.ReceivedPair>}
  for larger: {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")),
    TC.Limits.tracestate_output(limits)) == False{} : Bool}
  {TC.Context.forward(limits, incoming, carrier) == Fail{TC.ForwardTooLarge{}} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def forward_too_large(limits, incoming, carrier, pair, kept, larger):
  %Equal.sym(Maybe<&2, TC.ReceivedPair>, TC.IncomingContext.received(incoming), Some{pair}, kept) :
    {TC.Forward.pair(limits, _, carrier) == Fail{TC.ForwardTooLarge{}} :
      Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  pair_too_large(limits, pair, carrier, larger)

# Forwarding what forwarding wrote writes it again: the pair is forwarded
# into any carrier (pair_moved), `forwarded` is Forward.carrier of the first
# one (pair_done), and carrier_again closes the loop. Without a pair, `done`
# is a refusal.
law pair_idempotent:
  for +limits: TC.Limits
  for received: Maybe<&2, TC.ReceivedPair>
  for +carrier: List<&2, TC.Header>
  for +forwarded: List<&2, TC.Header>
  for +done: {TC.Forward.pair(limits, received, carrier) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Forward.pair(limits, received, forwarded) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def pair_idempotent(limits, received, carrier, forwarded, done):
  match received:
    case None{}:
      refused({TC.Forward.pair(limits, None{}, forwarded) == Done{forwarded} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, TC.NothingToForward{}, forwarded, done)
    case Some{+pair}:
      +traceparent = TC.ReceivedPair.traceparent(pair)
      +tracestate = TC.ReceivedPair.tracestate(pair)
      %Equal.sym(Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>, TC.Forward.pair(limits, Some{pair}, forwarded),
        Done{TC.Forward.carrier(forwarded, traceparent, tracestate)},
        pair_moved(limits, pair, carrier, forwarded, forwarded, done)) :
        {_ == Done{forwarded} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
      %pair_done(limits, pair, carrier, forwarded, done) :
        {Done{TC.Forward.carrier(_, traceparent, tracestate)} == Done{_} :
          Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
      %Equal.sym(List<&2, TC.Header>, TC.Forward.carrier(TC.Forward.carrier(carrier, traceparent, tracestate),
        traceparent, tracestate), TC.Forward.carrier(carrier, traceparent, tracestate),
        carrier_again(carrier, traceparent, tracestate)) :
        {Done{_} == Done{TC.Forward.carrier(carrier, traceparent, tracestate)} :
          Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
      {==}

# Law forward_idempotent.
law forward_idempotent:
  for +limits: TC.Limits
  for +incoming: TC.IncomingContext
  for +carrier: List<&2, TC.Header>
  for +forwarded: List<&2, TC.Header>
  for done: {TC.Context.forward(limits, incoming, carrier) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  {TC.Context.forward(limits, incoming, forwarded) == Done{forwarded} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def forward_idempotent(limits, incoming, carrier, forwarded, done):
  pair_idempotent(limits, TC.IncomingContext.received(incoming), carrier, forwarded, done)

# Forwarding: pairs that extraction keeps
# =======================================
#
# The pair an extraction keeps fits the input budgets and reads back under the
# same limits (ExtractProof.extracted_view). The lemmas below follow the
# checks of forwarding, one per step, for such a pair: only the output budget
# is left to check.

# The last check passes for fields that parse.
law state_forwarded:
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for parse_ok: {Result.is_done(&2, &2, TC.StateError, TC.TraceState, parsed) == True{} : Bool}
  {TC.Forward.state(parsed, carrier, traceparent, tracestate) ==
    Done{TC.Forward.carrier(carrier, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def state_forwarded(parsed, carrier, traceparent, tracestate, parse_ok):
  match parsed:
    case Fail{error}:
      BoolsProof.absurd({TC.Forward.state(Fail{error}, carrier, traceparent, tracestate) ==
        Done{TC.Forward.carrier(carrier, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, parse_ok)
    case Done{state}:
      {==}

# The traceparent check passes for a value that reads.
law parent_forwarded:
  for read: Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for read_ok: {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00, read) == True{} : Bool}
  for parse_ok: {Result.is_done(&2, &2, TC.StateError, TC.TraceState, TC.TraceState.parse_fields(limits, tracestate)) ==
    True{} : Bool}
  {TC.Forward.parent(read, limits, carrier, traceparent, tracestate) ==
    Done{TC.Forward.carrier(carrier, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def parent_forwarded(read, limits, carrier, traceparent, tracestate, read_ok, parse_ok):
  match read:
    case Fail{error}:
      BoolsProof.absurd({TC.Forward.parent(Fail{error}, limits, carrier, traceparent, tracestate) ==
        Done{TC.Forward.carrier(carrier, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, read_ok)
    case Done{known}:
      state_forwarded(TC.TraceState.parse_fields(limits, tracestate), carrier, traceparent, tracestate, parse_ok)

# The budget check passes for a measurement within the budget.
law fits_forwarded:
  for fits: Maybe<&2, Nat>
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +traceparent: String
  for +tracestate: List<&2, String>
  for some: {Maybe.is_some(&2, Nat, fits) == True{} : Bool}
  for read_ok: {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
    TC.TraceParent.read(limits, traceparent)) == True{} : Bool}
  for parse_ok: {Result.is_done(&2, &2, TC.StateError, TC.TraceState, TC.TraceState.parse_fields(limits, tracestate)) ==
    True{} : Bool}
  {TC.Forward.fits(fits, limits, carrier, traceparent, tracestate) ==
    Done{TC.Forward.carrier(carrier, traceparent, tracestate)} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def fits_forwarded(fits, limits, carrier, traceparent, tracestate, some, read_ok, parse_ok):
  match fits:
    case None{}:
      BoolsProof.absurd({TC.Forward.fits(None{}, limits, carrier, traceparent, tracestate) ==
        Done{TC.Forward.carrier(carrier, traceparent, tracestate)} :
        Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}, some)
    case Some{left}:
      parent_forwarded(TC.TraceParent.read(limits, traceparent), limits, carrier, traceparent, tracestate, read_ok,
        parse_ok)

# A pair whose fields read back (`view`) and whose joined tracestate fits the
# output budget is forwarded (fields_within measures it).
law pair_forwarded:
  for +limits: TC.Limits
  for +pair: TC.ReceivedPair
  for +carrier: List<&2, TC.Header>
  for view: ExtractProof.PairView(limits, Some{pair})
  for fits: {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")),
    TC.Limits.tracestate_output(limits)) == True{} : Bool}
  {TC.Forward.pair(limits, Some{pair}, carrier) == Done{TC.Forward.carrier(carrier, TC.ReceivedPair.traceparent(pair),
    TC.ReceivedPair.tracestate(pair))} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def pair_forwarded(limits, pair, carrier, view, fits):
  match pair:
    case TC.ReceivedPair{+traceparent, +tracestate}:
      (traceparent_fits, rest) = view
      (tracestate_fits, reads) = rest
      (read_ok, parse_ok) = reads
      fits_forwarded(TC.Utf8.left_fields(tracestate, Some{TC.Limits.tracestate_output(limits)}), limits, carrier,
        traceparent, tracestate,
        Equal.trans(Bool,
          Maybe.is_some(&2, Nat, TC.Utf8.left_fields(tracestate, Some{TC.Limits.tracestate_output(limits)})),
          Nat.is_le(TC.Utf8.length(String.join(tracestate, ",")), TC.Limits.tracestate_output(limits)), True{},
          fields_within(tracestate, TC.Limits.tracestate_output(limits)), fits),
        read_ok, parse_ok)

# Law forward_extracted: the pair of an extracted context reads back
# (ExtractProof.extracted_view), so forwarding it within the budget succeeds
# (pair_forwarded) and writes the received fields (forward_fields).
law forward_extracted:
  for +limits: TC.Limits
  for +received: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for +incoming: TC.IncomingContext
  for +pair: TC.ReceivedPair
  for +carrier: List<&2, TC.Header>
  for extracted: {TC.Extraction.incoming(TC.Context.extract(limits, received, base)) == Some{incoming} :
    Maybe<&2, TC.IncomingContext>}
  for +kept: {TC.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, TC.ReceivedPair>}
  for fits: {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")),
    TC.Limits.tracestate_output(limits)) == True{} : Bool}
  {TC.Context.forward(limits, incoming, carrier) == Done{List.append(&2, TC.Header, Laws.unrelated(carrier),
    Laws.written(TC.ReceivedPair.traceparent(pair), String.join(TC.ReceivedPair.tracestate(pair), ",")))} :
    Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}

def forward_extracted(limits, received, base, incoming, pair, carrier, extracted, kept, fits):
  +traceparent = TC.ReceivedPair.traceparent(pair)
  +tracestate = TC.ReceivedPair.tracestate(pair)
  %Equal.sym(Maybe<&2, TC.ReceivedPair>, TC.IncomingContext.received(incoming), Some{pair}, kept) :
    {TC.Forward.pair(limits, _, carrier) == Done{List.append(&2, TC.Header, Laws.unrelated(carrier),
      Laws.written(traceparent, String.join(tracestate, ",")))} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  %forward_fields(carrier, traceparent, tracestate) :
    {TC.Forward.pair(limits, Some{pair}, carrier) == Done{_} : Result<&2, &2, TC.ForwardError, List<&2, TC.Header>>}
  pair_forwarded(limits, pair, carrier, ExtractProof.extracted_view(limits, received, base, incoming, pair, extracted,
    kept), fits)
