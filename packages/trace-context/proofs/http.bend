# Proofs: native HTTP headers
# ===========================
#
# What native_http.bend does with a header map. PROOF.bend proves the laws of
# section 15 of LAWS.bend with the lemmas of the same names.
#
# http_carrier follows the carrier's construction: the map's entries, each
# pushed onto the fields gathered so far, most recent first, then reversed.
# Selecting a name commutes with reversing (values_reverse); pushing one
# entry's fields puts its values, reversed, onto the selection when the entry
# has that name (push_values); so the gathered fields hold the entries'
# values reversed (gather_values), and reversing again gives them in order.
# http_headers follows the map's construction the same way: the carrier
# reversed and written into an empty map, each value first among its name's.
# Writing one field puts its value first under its own name and leaves the
# others as they were (add_values), which is where Base's Map contract comes
# in: the law takes it as the templates `found` and `kept`, so that the
# induction can use them at every field (write_values).
# http_continue holds by computation: the shortcut is the package's
# operation on the extraction of the carrier. http_send is the package's
# send followed by the adapter's translation, which agrees with LAWS.bend's
# http_written.done on every result (written_same); with an operation, both
# sides read the same child's words, and GenerationProof.read_tape_same
# carries that agreement through the reading.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ../native_http.bend as NativeHttp
import ./generation.bend as GenerationProof
import ./lists.bend as ListsProof
import ./strings.bend as StringsProof

# A field put first in both lists: reversing `a` onto the selection kept
# from `b` is reversing that selection kept from `a` onto `b`. By cases on
# `same`; each computes.
law kept_reverse:
  for same: Bool
  for +value: String
  for a: List<&2, String>
  for b: List<&2, String>
  {List.reverse.go(&2, String, a, Laws.http_values.kept(same, value, b)) ==
    List.reverse.go(&2, String, Laws.http_values.kept(same, value, a), b) : List<&2, String>}

def kept_reverse(same, value, a, b):
  match same:
    case True{}:
      {==}
    case False{}:
      {==}

# Selecting `name` commutes with reversing: the selection from `fields`
# reversed onto `acc` is the selection from `fields` reversed onto the
# selection from `acc`. Induction on the fields, with kept_reverse for each.
law values_reverse:
  for +name: String
  for fields: List<&2, TC.Header>
  for +acc: List<&2, TC.Header>
  {Laws.http_values(name, List.reverse.go(&2, TC.Header, fields, acc)) ==
    List.reverse.go(&2, String, Laws.http_values(name, fields), Laws.http_values(name, acc)) : List<&2, String>}

def values_reverse(name, fields, acc):
  match fields:
    case Nil{}:
      {==}
    case Con{TC.Header{+field, +value}, +rest}:
      Equal.trans(List<&2, String>,
        Laws.http_values(name, List.reverse.go(&2, TC.Header, rest, Con{TC.Header{field, value}, acc})),
        List.reverse.go(&2, String, Laws.http_values(name, rest),
          Laws.http_values.kept(String.eq(field, name), value, Laws.http_values(name, acc))),
        List.reverse.go(&2, String, Laws.http_values.kept(String.eq(field, name), value, Laws.http_values(name, rest)),
          Laws.http_values(name, acc)),
        values_reverse(name, rest, Con{TC.Header{field, value}, acc}),
        kept_reverse(String.eq(field, name), value, Laws.http_values(name, rest), Laws.http_values(name, acc)))

# The values of one entry, pushed onto `rest`, when its name is the one
# selected (`same`).
def pushed(same: Bool, values: List<&2, String>, rest: List<&2, String>) -> List<&2, String>:
  match same:
    case True{}:
      List.reverse.go(&2, String, values, rest)
    case False{}:
      rest

# Selecting `name` from an entry's fields pushed onto `fields` gives the
# entry's values pushed onto the selection from `fields` when the entry is
# named `name` (`same`), and that selection otherwise. Induction on the
# values; `holds` says what `same` is.
law push_values:
  for +name: String
  for +key: String
  for values: List<&2, String>
  for +fields: List<&2, TC.Header>
  for same: Bool
  for +holds: {String.eq(key, name) == same : Bool}
  {Laws.http_values(name, NativeHttp.Headers.push(key, values, fields)) ==
    pushed(same, values, Laws.http_values(name, fields)) : List<&2, String>}

def push_values(name, key, values, fields, same, holds):
  match values same:
    case Nil{} True{}:
      {==}
    case Nil{} False{}:
      {==}
    case Con{+value, +tail} True{}:
      Equal.trans(List<&2, String>,
        Laws.http_values(name, NativeHttp.Headers.push(key, tail, Con{TC.Header{key, value}, fields})),
        pushed(True{}, tail, Laws.http_values.kept(String.eq(key, name), value, Laws.http_values(name, fields))),
        pushed(True{}, tail, Laws.http_values.kept(True{}, value, Laws.http_values(name, fields))),
        push_values(name, key, tail, Con{TC.Header{key, value}, fields}, True{}, holds),
        Equal.cong(Bool, List<&2, String>,
          selected => pushed(True{}, tail, Laws.http_values.kept(selected, value, Laws.http_values(name, fields))),
          String.eq(key, name), True{}, holds))
    case Con{+value, +tail} False{}:
      Equal.trans(List<&2, String>,
        Laws.http_values(name, NativeHttp.Headers.push(key, tail, Con{TC.Header{key, value}, fields})),
        pushed(False{}, tail, Laws.http_values.kept(String.eq(key, name), value, Laws.http_values(name, fields))),
        pushed(False{}, tail, Laws.http_values.kept(False{}, value, Laws.http_values(name, fields))),
        push_values(name, key, tail, Con{TC.Header{key, value}, fields}, False{}, holds),
        Equal.cong(Bool, List<&2, String>,
          selected => pushed(False{}, tail, Laws.http_values.kept(selected, value, Laws.http_values(name, fields))),
          String.eq(key, name), False{}, holds))

# Reversing the entries still to come onto an entry's pushed values is
# reversing that entry's selection, followed by theirs, onto the rest. By
# cases on `same`: reverse_go_append joins the two reversals.
law gathered:
  for same: Bool
  for +values: List<&2, String>
  for +fields: List<&2, String>
  for +rest: List<&2, String>
  {List.reverse.go(&2, String, rest, pushed(same, values, fields)) ==
    List.reverse.go(&2, String, Laws.entry_values.kept(same, values, rest), fields) : List<&2, String>}

def gathered(same, values, fields, rest):
  match same:
    case True{}:
      Equal.sym(List<&2, String>, List.reverse.go(&2, String, List.append(&2, String, values, rest), fields),
        List.reverse.go(&2, String, rest, List.reverse.go(&2, String, values, fields)),
        ListsProof.reverse_go_append(String, values, rest, fields))
    case False{}:
      {==}

# Selecting `name` from the fields that every entry pushes onto `fields`
# gives the values of the entries named `name` reversed onto the selection
# from `fields`. Induction on the entries, with push_values and gathered for
# each.
law gather_values:
  for +name: String
  for entries: List<&2, Sigma<&2, &2, String, _ => List<&2, String>>>
  for +fields: List<&2, TC.Header>
  {Laws.http_values(name, NativeHttp.Headers.gather(entries, fields)) ==
    List.reverse.go(&2, String, Laws.entry_values(name, entries), Laws.http_values(name, fields)) : List<&2, String>}

def gather_values(name, entries, fields):
  match entries:
    case Nil{}:
      {==}
    case Con{Tuple{+key, +values}, +rest}:
      Equal.trans(List<&2, String>,
        Laws.http_values(name, NativeHttp.Headers.gather(rest, NativeHttp.Headers.push(key, values, fields))),
        List.reverse.go(&2, String, Laws.entry_values(name, rest),
          pushed(String.eq(key, name), values, Laws.http_values(name, fields))),
        List.reverse.go(&2, String, Laws.entry_values.kept(String.eq(key, name), values, Laws.entry_values(name, rest)),
          Laws.http_values(name, fields)),
        Equal.trans(List<&2, String>,
          Laws.http_values(name, NativeHttp.Headers.gather(rest, NativeHttp.Headers.push(key, values, fields))),
          List.reverse.go(&2, String, Laws.entry_values(name, rest),
            Laws.http_values(name, NativeHttp.Headers.push(key, values, fields))),
          List.reverse.go(&2, String, Laws.entry_values(name, rest),
            pushed(String.eq(key, name), values, Laws.http_values(name, fields))),
          gather_values(name, rest, NativeHttp.Headers.push(key, values, fields)),
          Equal.cong(List<&2, String>, List<&2, String>,
            selected => List.reverse.go(&2, String, Laws.entry_values(name, rest), selected),
            Laws.http_values(name, NativeHttp.Headers.push(key, values, fields)),
            pushed(String.eq(key, name), values, Laws.http_values(name, fields)),
            push_values(name, key, values, fields, String.eq(key, name), {==}))),
        gathered(String.eq(key, name), values, Laws.http_values(name, fields), Laws.entry_values(name, rest)))

# Law http_carrier: the carrier is the gathered fields reversed, so the
# selection is the entries' values reversed twice (values_reverse,
# gather_values, ListsProof.reverse_twice).
law http_carrier:
  for headers: Map<&2, List<&2, String>>
  for +name: String
  {Laws.http_values(name, NativeHttp.carrier(headers)) ==
    Laws.entry_values(name, Map.to_list(&2, List<&2, String>, headers)) : List<&2, String>}

def http_carrier(headers, name):
  +entries = Map.to_list(&2, List<&2, String>, headers)
  +gathered = NativeHttp.Headers.gather(entries, Nil{})
  Equal.trans(List<&2, String>,
    Laws.http_values(name, List.reverse.go(&2, TC.Header, gathered, Nil{})),
    List.reverse.go(&2, String, Laws.http_values(name, gathered), Nil{}),
    Laws.entry_values(name, entries),
    values_reverse(name, gathered, Nil{}),
    Equal.trans(List<&2, String>,
      List.reverse.go(&2, String, Laws.http_values(name, gathered), Nil{}),
      List.reverse.go(&2, String, List.reverse.go(&2, String, Laws.entry_values(name, entries), Nil{}), Nil{}),
      Laws.entry_values(name, entries),
      Equal.cong(List<&2, String>, List<&2, String>, selected => List.reverse.go(&2, String, selected, Nil{}),
        Laws.http_values(name, gathered), List.reverse.go(&2, String, Laws.entry_values(name, entries), Nil{}),
        gather_values(name, entries, Nil{})),
      ListsProof.reverse_twice(String, Laws.entry_values(name, entries), Nil{})))

# Base's Map contract as the adapter relies on it: a list set under a key is
# found under it, and setting another key leaves it as it was. Base proves
# neither, so law http_headers takes both as hypotheses.
def Found() -> Type:
  @headers: Map<&2, List<&2, String>> -> @key: String -> @values: List<&2, String> ->
    {Laws.map_values(Map.set(&2, List<&2, String>, headers, key, values), key) == values : List<&2, String>}

def Kept() -> Type:
  @headers: Map<&2, List<&2, String>> -> @key: String -> @other: String -> @values: List<&2, String> ->
    {String.eq(other, key) == False{} : Bool} ->
    {Laws.map_values(Map.set(&2, List<&2, String>, headers, other, values), key) == Laws.map_values(headers, key) :
      List<&2, String>}

# Putting one field first among its name's values: under the name selected,
# the value comes first when the field has that name (`same`), and nothing
# changes otherwise. eq_sound turns a true comparison into the equality of
# the names, and `found` or `kept` gives the rest.
law add_values:
  for ~found: Found()
  for ~kept: Kept()
  for +headers: Map<&2, List<&2, String>>
  for +key: String
  for +value: String
  for +name: String
  for same: Bool
  for holds: {String.eq(key, name) == same : Bool}
  {Laws.map_values(NativeHttp.Headers.add(headers, TC.Header{key, value}), name) ==
    Laws.http_values.kept(same, value, Laws.map_values(headers, name)) : List<&2, String>}

def add_values(found, kept, headers, key, value, name, same, holds):
  match same:
    case True{}:
      %StringsProof.eq_sound(key, name, holds) :
        {Laws.map_values(Map.set(&2, List<&2, String>, headers, key,
          Con{value, NativeHttp.Headers.values(headers, key)}), _) == Con{value, Laws.map_values(headers, _)} :
          List<&2, String>}
      found(headers, key, Con{value, NativeHttp.Headers.values(headers, key)})
    case False{}:
      kept(headers, name, key, Con{value, NativeHttp.Headers.values(headers, key)}, holds)

# Writing `fields` into `headers` puts, under the name selected, the
# selection from `fields` reversed before the values that `headers` holds.
# Induction on the fields, with add_values and kept_reverse for each.
law write_values:
  for ~found: Found()
  for ~kept: Kept()
  for fields: List<&2, TC.Header>
  for +headers: Map<&2, List<&2, String>>
  for +name: String
  {Laws.map_values(NativeHttp.Headers.write(fields, headers), name) ==
    List.reverse.go(&2, String, Laws.http_values(name, fields), Laws.map_values(headers, name)) : List<&2, String>}

def write_values(found, kept, fields, headers, name):
  match fields:
    case Nil{}:
      {==}
    case Con{TC.Header{+key, +value}, +rest}:
      Equal.trans(List<&2, String>,
        Laws.map_values(NativeHttp.Headers.write(rest, NativeHttp.Headers.add(headers, TC.Header{key, value})), name),
        List.reverse.go(&2, String, Laws.http_values(name, rest),
          Laws.map_values(NativeHttp.Headers.add(headers, TC.Header{key, value}), name)),
        List.reverse.go(&2, String, Laws.http_values.kept(String.eq(key, name), value, Laws.http_values(name, rest)),
          Laws.map_values(headers, name)),
        write_values(~found, ~kept, rest, NativeHttp.Headers.add(headers, TC.Header{key, value}), name),
        Equal.trans(List<&2, String>,
          List.reverse.go(&2, String, Laws.http_values(name, rest),
            Laws.map_values(NativeHttp.Headers.add(headers, TC.Header{key, value}), name)),
          List.reverse.go(&2, String, Laws.http_values(name, rest),
            Laws.http_values.kept(String.eq(key, name), value, Laws.map_values(headers, name))),
          List.reverse.go(&2, String, Laws.http_values.kept(String.eq(key, name), value, Laws.http_values(name, rest)),
            Laws.map_values(headers, name)),
          Equal.cong(List<&2, String>, List<&2, String>,
            selected => List.reverse.go(&2, String, Laws.http_values(name, rest), selected),
            Laws.map_values(NativeHttp.Headers.add(headers, TC.Header{key, value}), name),
            Laws.http_values.kept(String.eq(key, name), value, Laws.map_values(headers, name)),
            add_values(~found, ~kept, headers, key, value, name, String.eq(key, name), {==})),
          kept_reverse(String.eq(key, name), value, Laws.http_values(name, rest), Laws.map_values(headers, name))))

# Law http_headers: the map is the carrier reversed and written into an
# empty map, so under each name it holds the selection reversed twice
# (write_values, values_reverse, ListsProof.reverse_twice).
law http_headers:
  for ~found: Found()
  for ~kept: Kept()
  for carrier: List<&2, TC.Header>
  for +name: String
  {Laws.map_values(NativeHttp.headers(carrier), name) == Laws.http_values(name, carrier) : List<&2, String>}

def http_headers(found, kept, carrier, name):
  +fields = carrier
  Equal.trans(List<&2, String>,
    Laws.map_values(NativeHttp.Headers.write(List.reverse.go(&2, TC.Header, fields, Nil{}), Map.new(&2, List<&2, String>)),
      name),
    List.reverse.go(&2, String, Laws.http_values(name, List.reverse.go(&2, TC.Header, fields, Nil{})), Nil{}),
    Laws.http_values(name, fields),
    write_values(~found, ~kept, List.reverse.go(&2, TC.Header, fields, Nil{}), Map.new(&2, List<&2, String>), name),
    Equal.trans(List<&2, String>,
      List.reverse.go(&2, String, Laws.http_values(name, List.reverse.go(&2, TC.Header, fields, Nil{})), Nil{}),
      List.reverse.go(&2, String, List.reverse.go(&2, String, Laws.http_values(name, fields), Nil{}), Nil{}),
      Laws.http_values(name, fields),
      Equal.cong(List<&2, String>, List<&2, String>, selected => List.reverse.go(&2, String, selected, Nil{}),
        Laws.http_values(name, List.reverse.go(&2, TC.Header, fields, Nil{})),
        List.reverse.go(&2, String, Laws.http_values(name, fields), Nil{}),
        values_reverse(name, fields, Nil{})),
      ListsProof.reverse_twice(String, Laws.http_values(name, fields), Nil{})))

# Law http_continue: by computation.
law http_continue:
  for tape: Laws.Tape()
  for +limits: TC.Limits
  for headers: Map<&2, List<&2, String>>
  for base: Maybe<&2, TC.BaseContext>
  for reception: TC.Reception
  for sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  {Laws.Observe(Laws.TapeService(policy), NativeHttp.continue_or_start_with(~Laws.Tape(), ~TC.Source.tape, tape,
    limits, headers, base, reception, sampling, policy)) ==
    Laws.Observe(Laws.TapeService(policy), TC.Context.continue_or_start_with(~Laws.Tape(), ~TC.Source.tape, tape,
      TC.Context.extract(limits, NativeHttp.carrier(headers), base), reception, sampling, policy)) :
    IO.OP<Laws.TapeService(policy)>}

def http_continue(tape, limits, headers, base, reception, sampling, policy):
  {==}

# The Lenient{} case of written_same.
law written_same.lenient:
  for done: Laws.Tape() & TC.Sent
  {NativeHttp.Headers.written.done(Laws.Tape(), TC.Lenient{}, done) == Laws.http_written.done(TC.Lenient{}, done) :
    Laws.TapeOutbound(TC.Lenient{})}

def written_same.lenient(done):
  match done:
    case Tuple{rest, sent}:
      {==}

# The Strict{} case of written_same: a failure stays a failure.
law written_same.strict:
  for done: Laws.Tape() & Result<&2, &2, TC.GenerationError, TC.Sent>
  {NativeHttp.Headers.written.done(Laws.Tape(), TC.Strict{}, done) == Laws.http_written.done(TC.Strict{}, done) :
    Laws.TapeOutbound(TC.Strict{})}

def written_same.strict(done):
  match done:
    case Tuple{rest, Fail{error}}:
      {==}
    case Tuple{rest, Done{sent}}:
      {==}

# The adapter's translation of a message sent is http_written.done, for
# every result under either policy. By cases on the policy, then on the
# result; each case computes.
law written_same:
  for +policy: TC.FailurePolicy
  for done: Laws.TapeSent(policy)
  {NativeHttp.Headers.written.done(Laws.Tape(), policy, done) == Laws.http_written.done(policy, done) :
    Laws.TapeOutbound(policy)}

def written_same(policy, done):
  match policy:
    case TC.Lenient{}:
      written_same.lenient(done)
    case TC.Strict{}:
      written_same.strict(done)

# The tape with the first step of a generation, as Draw.read takes them.
# http_send takes a child's step from its plan, since its law takes
# `sampling` once.
def generation_start(tape: Laws.Tape(), generation: TC.Generation) -> Laws.TapeStep():
  match generation:
    case TC.Generation{fuel, step}:
      (tape, step)

# Law http_send: by cases on the service. With an operation, both sides read
# the same child's words and agree on every outcome (written_same,
# GenerationProof.read_tape_same); without one, both emit the fallback at
# once, translated alike.
law http_send:
  for tape: Laws.Tape()
  for +limits: TC.Limits
  for service: TC.Service
  for sampling: TC.Sampling
  for +policy: TC.FailurePolicy
  for +headers: Map<&2, List<&2, String>>
  {Laws.Observe(Laws.TapeOutbound(policy), NativeHttp.send_with(~Laws.Tape(), ~TC.Source.tape, tape, limits, service,
    sampling, policy, headers)) ==
    Laws.Observe(Laws.TapeOutbound(policy), IO.bind(Laws.TapeSent(policy), Laws.TapeOutbound(policy),
      TC.Context.send_with(~Laws.Tape(), ~TC.Source.tape, tape, limits, service, sampling, policy,
        NativeHttp.carrier(headers)), done => IO.pure(Laws.TapeOutbound(policy), Laws.http_written.done(policy, done)))) :
    IO.OP<Laws.TapeOutbound(policy)>}

def http_send(tape, limits, service, sampling, policy, headers):
  match service:
    case TC.Operating{origin, +outgoing, +received}:
      +plan : TC.SendPlan = TC.SendChild{TC.Generation.child(TC.LocalParent{TC.OutgoingContext.context(outgoing)}, sampling), limits,
        outgoing, received, NativeHttp.carrier(headers)}
      GenerationProof.read_tape_same(Laws.TapeOutbound(policy),
        outcome => NativeHttp.Headers.written.done(Laws.Tape(), policy, TC.Policy.apply.done(Laws.Tape(), policy,
          TC.Sent, TC.Send.strict, TC.Send.finish(Laws.Tape(), plan, outcome))),
        outcome => Laws.http_written.done(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
          TC.Send.finish(Laws.Tape(), plan, outcome))),
        outcome => written_same(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
          TC.Send.finish(Laws.Tape(), plan, outcome))),
        16n, generation_start(tape, TC.SendPlan.generation(plan)))
    case TC.Untraced{+error, +received}:
      Equal.cong(Laws.TapeOutbound(policy), IO.OP<Laws.TapeOutbound(policy)>, outbound => Emit{outbound},
        NativeHttp.Headers.written.done(Laws.Tape(), policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent,
          TC.Send.strict, (tape, TC.Send.fallback(limits, received, error, NativeHttp.carrier(headers))))),
        Laws.http_written.done(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
          (tape, TC.Send.fallback(limits, received, error, NativeHttp.carrier(headers))))),
        written_same(policy, TC.Policy.apply.done(Laws.Tape(), policy, TC.Sent, TC.Send.strict,
          (tape, TC.Send.fallback(limits, received, error, NativeHttp.carrier(headers))))))
