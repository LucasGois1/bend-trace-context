# Proofs: extraction
# ==================
#
# What Context.extract and TraceParent.read of trace_context.bend do with a
# received message. PROOF.bend proves the laws of section 12 of LAWS.bend
# with the lemmas of the same names. The module has six parts:
#
#   Selecting fields     The package compares each name with the field name
#                        one character at a time and collects the values in a
#                        loop, most recent first, then reverses them;
#                        LAWS.bend states the selection with Base's
#                        String.to_lower and a plain recursion (Laws.named).
#                        named_step, with StringsProof.eq_cons, shows that
#                        the comparisons agree, and `values` that the loop
#                        gives Laws.named.
#                        extract_named restates every extraction as
#                        Extract.parents of the selected values.
#   Messages without     extract_absent, extract_repeated and extract_refused
#   a usable             follow Extract.parents to the kept base.
#   traceparent
#   Budgets              TraceParent.read measures a value with Utf8.left,
#                        which StateProof.within relates to Utf8.length,
#                        before reading anything.
#   Whitespace           The package removes whitespace in loops and by
#                        reversing; LAWS.bend states it with plain recursions
#                        (Laws.ows_start, Laws.ows_end). trim_law shows that
#                        they agree, and extract_read follows an accepted
#                        message through Extract.state.
#   Reading a            Plain texts, without a comma, a space or a tab, pass
#   traceparent value    the whitespace and comma steps unchanged. The v00
#                        and later-version laws then follow the version rules
#                        to the strict codec, whose round trip
#                        (ContextProof.roundtrip) reads the known fields back;
#                        read_v00_exact uses law inverse instead.
#   The tracestate and   The traceparent outcome and the sender's operation
#   the kept pair        never depend on the tracestate fields
#                        (state_independent), and views over every extraction
#                        bound the pair it keeps (received_bounds).
#
# As elsewhere, a step lemma receives a value the proof must match on (a
# Bool, a Result) as a parameter, with an equation saying what it is, and
# the `*_result` defs repeat the package's do blocks so that a rewrite motive
# can mark one step's result with `_`.

import Base
import ../LAWS.bend as Laws
import ../trace_context.bend as TC
import ../src/hex.bend as Hex
import ../src/digits.bend as Digits
import ./chars.bend as CharsProof
import ./strings.bend as StringsProof
import ./bools.bend as BoolsProof
import ./nats.bend as NatsProof
import ./lists.bend as ListsProof
import ./digits.bend as DigitsProof
import ./parser.bend as ParserProof
import ./context.bend as ContextProof
import ./inverse.bend as InverseProof
import ./tracestate.bend as StateProof

# Selecting fields
# ================

# The package's comparison of a field name, Carrier.named, is the comparison
# of Laws.named: the name with its ASCII letters lowered equals the lowercase
# name sought. Induction on both strings.
law named_step:
  for +name: String
  for +text: String
  {TC.Carrier.named(name, text) == String.eq(String.to_lower(text), name) : Bool}

def named_step(name, text):
  match name text:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{char, rest}:
      {==}
    case SCon{expected, more} SNil{}:
      {==}
    case SCon{+expected, +more} SCon{+char, +rest}:
      %Equal.sym(Bool, TC.Carrier.named(more, rest), String.eq(String.to_lower(rest), more), named_step(more, rest)) :
        {Bool.and(Char.is_eq(Char.to_lower(char), expected), _) ==
          String.eq(SCon{Char.to_lower(char), String.to_lower(rest)}, SCon{expected, more}) : Bool}
      Equal.sym(Bool, String.eq(SCon{Char.to_lower(char), String.to_lower(rest)}, SCon{expected, more}),
        Bool.and(Char.is_eq(Char.to_lower(char), expected), String.eq(String.to_lower(rest), more)),
        StringsProof.eq_cons(Char.to_lower(char), expected, String.to_lower(rest), more))

# One step of the loop matches one step of Laws.named: a hit puts the value in
# front of what was found, which reversing turns into the value's place in
# order.
law values_step:
  for +selected: List<&2, String>
  for +value: String
  for +found: List<&2, String>
  for hit: Bool
  {List.reverse.go(&2, String, selected, TC.Carrier.keep(hit, value, found)) ==
    List.reverse.go(&2, String, Bool.pick(List<&2, String>, hit, Con{value, selected}, selected), found) :
    List<&2, String>}

def values_step(selected, value, found, hit):
  match hit:
    case True{}:
      {==}
    case False{}:
      {==}

# The loop of Carrier.values, from the values `found` so far, gives the
# values Laws.named selects, reversed, before `found`. Induction on the
# carrier.
law values_go:
  for +carrier: List<&2, TC.Header>
  for +name: String
  for +found: List<&2, String>
  {TC.Carrier.values.go(carrier, name, found) == List.reverse.go(&2, String, Laws.named(name, carrier), found) :
    List<&2, String>}

def values_go(carrier, name, found):
  match carrier:
    case Nil{}:
      {==}
    case Con{+header, +rest}:
      %Equal.sym(List<&2, String>,
        TC.Carrier.values.go(rest, name, TC.Carrier.keep(TC.Carrier.named(name, TC.Header.name(header)),
          TC.Header.value(header), found)),
        List.reverse.go(&2, String, Laws.named(name, rest), TC.Carrier.keep(TC.Carrier.named(name,
          TC.Header.name(header)), TC.Header.value(header), found)),
        values_go(rest, name, TC.Carrier.keep(TC.Carrier.named(name, TC.Header.name(header)), TC.Header.value(header),
          found))) :
        {_ == List.reverse.go(&2, String, Laws.named(name, Con{header, rest}), found) : List<&2, String>}
      %Equal.sym(Bool, TC.Carrier.named(name, TC.Header.name(header)),
        String.eq(String.to_lower(TC.Header.name(header)), name), named_step(name, TC.Header.name(header))) :
        {List.reverse.go(&2, String, Laws.named(name, rest), TC.Carrier.keep(_, TC.Header.value(header), found)) ==
          List.reverse.go(&2, String, Laws.named(name, Con{header, rest}), found) : List<&2, String>}
      values_step(Laws.named(name, rest), TC.Header.value(header), found,
        String.eq(String.to_lower(TC.Header.name(header)), name))

# Carrier.values gives exactly the values Laws.named selects, in order:
# reversing the loop's reversed values gives them back
# (ListsProof.reverse_twice).
law values:
  for +carrier: List<&2, TC.Header>
  for +name: String
  {TC.Carrier.values(carrier, name) == Laws.named(name, carrier) : List<&2, String>}

def values(carrier, name):
  %Equal.sym(List<&2, String>, TC.Carrier.values.go(carrier, name, Nil{}),
    List.reverse.go(&2, String, Laws.named(name, carrier), Nil{}), values_go(carrier, name, Nil{})) :
    {List.reverse(&2, String, _) == Laws.named(name, carrier) : List<&2, String>}
  ListsProof.reverse_twice(String, Laws.named(name, carrier), Nil{})

# Extraction is Extract.parents of the values Laws.named selects. Every
# extraction law starts here.
law extract_named:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  {TC.Context.extract(limits, carrier, base) == TC.Extract.parents(limits, Laws.named("traceparent", carrier),
    Laws.named("tracestate", carrier), base) : TC.Extraction}

def extract_named(limits, carrier, base):
  %Equal.sym(List<&2, String>, TC.Carrier.values(carrier, "traceparent"), Laws.named("traceparent", carrier),
    values(carrier, "traceparent")) :
    {TC.Extract.parents(limits, _, TC.Carrier.values(carrier, "tracestate"), base) ==
      TC.Extract.parents(limits, Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base) :
      TC.Extraction}
  %Equal.sym(List<&2, String>, TC.Carrier.values(carrier, "tracestate"), Laws.named("tracestate", carrier),
    values(carrier, "tracestate")) :
    {TC.Extract.parents(limits, Laws.named("traceparent", carrier), _, base) ==
      TC.Extract.parents(limits, Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base) :
      TC.Extraction}
  {==}

# The package reports unread tracestate fields as Laws.ignored does.
law ignored_law:
  for fields: List<&2, String>
  {TC.Extract.ignored(fields) == Laws.ignored(fields) : TC.StateOutcome}

def ignored_law(fields):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      {==}

# A message kept with the base: the extraction the package builds, with its
# unread tracestate fields reported by Extract.ignored, is the one the laws
# state with Laws.ignored.
law kept:
  for base: Maybe<&2, TC.BaseContext>
  for parent: TC.TraceParentOutcome
  for +fields: List<&2, String>
  {TC.Extract.kept(base, parent, fields) == TC.Extraction{base, parent, Laws.ignored(fields)} : TC.Extraction}

def kept(base, parent, fields):
  Equal.cong(TC.StateOutcome, TC.Extraction, outcome => TC.Extraction{base, parent, outcome},
    TC.Extract.ignored(fields), Laws.ignored(fields), ignored_law(fields))

# Messages without a usable traceparent
# =====================================

# Law extract_absent: with no traceparent value, Extract.parents keeps the
# base.
law extract_absent:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for absent: {Laws.named("traceparent", carrier) == Nil{} : List<&2, String>}
  {TC.Context.extract(limits, carrier, base) ==
    TC.Extraction{base, TC.TraceParentAbsent{}, Laws.ignored(Laws.named("tracestate", carrier))} : TC.Extraction}

def extract_absent(limits, carrier, base, absent):
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base),
    extract_named(limits, carrier, base)) :
    {_ == TC.Extraction{base, TC.TraceParentAbsent{}, Laws.ignored(Laws.named("tracestate", carrier))} :
      TC.Extraction}
  %Equal.sym(List<&2, String>, Laws.named("traceparent", carrier), Nil{}, absent) :
    {TC.Extract.parents(limits, _, Laws.named("tracestate", carrier), base) ==
      TC.Extraction{base, TC.TraceParentAbsent{}, Laws.ignored(Laws.named("tracestate", carrier))} : TC.Extraction}
  kept(base, TC.TraceParentAbsent{}, Laws.named("tracestate", carrier))

# Law extract_repeated: with two values or more, Extract.parents refuses them
# as repeated.
law extract_repeated:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for +first: String
  for +second: String
  for +more: List<&2, String>
  for repeated: {Laws.named("traceparent", carrier) == Con{first, Con{second, more}} : List<&2, String>}
  {TC.Context.extract(limits, carrier, base) == TC.Extraction{base,
    TC.TraceParentRejected{TC.RepeatedTraceParent{}}, Laws.ignored(Laws.named("tracestate", carrier))} :
    TC.Extraction}

def extract_repeated(limits, carrier, base, first, second, more, repeated):
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base),
    extract_named(limits, carrier, base)) :
    {_ == TC.Extraction{base, TC.TraceParentRejected{TC.RepeatedTraceParent{}},
      Laws.ignored(Laws.named("tracestate", carrier))} : TC.Extraction}
  %Equal.sym(List<&2, String>, Laws.named("traceparent", carrier), Con{first, Con{second, more}}, repeated) :
    {TC.Extract.parents(limits, _, Laws.named("tracestate", carrier), base) ==
      TC.Extraction{base, TC.TraceParentRejected{TC.RepeatedTraceParent{}},
        Laws.ignored(Laws.named("tracestate", carrier))} : TC.Extraction}
  kept(base, TC.TraceParentRejected{TC.RepeatedTraceParent{}}, Laws.named("tracestate", carrier))

# Law extract_refused: with one value, which TraceParent.read refuses,
# Extract.read keeps the base with the reason.
law extract_refused:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for +value: String
  for +error: TC.TraceParentError
  for single: {Laws.named("traceparent", carrier) == Con{value, Nil{}} : List<&2, String>}
  for refused: {TC.TraceParent.read(limits, value) == Fail{error} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {TC.Context.extract(limits, carrier, base) ==
    TC.Extraction{base, TC.TraceParentRejected{error}, Laws.ignored(Laws.named("tracestate", carrier))} :
    TC.Extraction}

def extract_refused(limits, carrier, base, value, error, single, refused):
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base),
    extract_named(limits, carrier, base)) :
    {_ == TC.Extraction{base, TC.TraceParentRejected{error}, Laws.ignored(Laws.named("tracestate", carrier))} :
      TC.Extraction}
  %Equal.sym(List<&2, String>, Laws.named("traceparent", carrier), Con{value, Nil{}}, single) :
    {TC.Extract.parents(limits, _, Laws.named("tracestate", carrier), base) ==
      TC.Extraction{base, TC.TraceParentRejected{error}, Laws.ignored(Laws.named("tracestate", carrier))} :
      TC.Extraction}
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, value),
    Fail{error}, refused) :
    {TC.Extract.read(_, value, limits, Laws.named("tracestate", carrier), base) ==
      TC.Extraction{base, TC.TraceParentRejected{error}, Laws.ignored(Laws.named("tracestate", carrier))} :
      TC.Extraction}
  kept(base, TC.TraceParentRejected{error}, Laws.named("tracestate", carrier))

# Budgets
# =======

# When the measurement `m` is None, the value exceeds its budget and
# Read.within refuses it without reading it. The Some case contradicts
# `larger`.
law within_over:
  for m: Maybe<&2, Nat>
  for value: String
  for larger: {Maybe.is_some(&2, Nat, m) == False{} : Bool}
  {TC.Read.within(m, value) == Fail{TC.TraceParentTooLarge{}} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def within_over(m, value, larger):
  match m:
    case None{}:
      {==}
    case Some{left}:
      Empty.absurd({TC.Read.within(Some{left}, value) == Fail{TC.TraceParentTooLarge{}} :
        Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}, BoolsProof.true_ne_false(larger))

# When the measurement `m` is Some, the value fits its budget and
# Read.within reads it without the whitespace around it, whatever
# octets are left. The None case contradicts `fits`.
law within_fits:
  for m: Maybe<&2, Nat>
  for value: String
  for fits: {Maybe.is_some(&2, Nat, m) == True{} : Bool}
  {TC.Read.within(m, value) == TC.Read.trimmed(TC.Text.trim_ows(value)) :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def within_fits(m, value, fits):
  match m:
    case None{}:
      BoolsProof.absurd({TC.Read.within(None{}, value) == TC.Read.trimmed(TC.Text.trim_ows(value)) :
        Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}, fits)
    case Some{left}:
      {==}

# A value that fits the traceparent input budget of `limits` is read as
# Read.trimmed of the value without its surrounding whitespace.
law read_fits:
  for +limits: TC.Limits
  for +value: String
  for fits: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {TC.TraceParent.read(limits, value) == TC.Read.trimmed(TC.Text.trim_ows(value)) :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_fits(limits, value, fits):
  within_fits(TC.Utf8.left(value, Some{TC.Limits.traceparent_input(limits)}), value,
    Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(value, Some{TC.Limits.traceparent_input(limits)})),
      Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)), True{},
      StateProof.within(value, TC.Limits.traceparent_input(limits)), fits))

# Law read_over_budget: StateProof.within turns the hypothesis into one on the
# measurement, and within_over concludes.
law read_over_budget:
  for +limits: TC.Limits
  for +value: String
  for larger: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == False{} : Bool}
  {TC.TraceParent.read(limits, value) == Fail{TC.TraceParentTooLarge{}} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_over_budget(limits, value, larger):
  within_over(TC.Utf8.left(value, Some{TC.Limits.traceparent_input(limits)}), value,
    Equal.trans(Bool, Maybe.is_some(&2, Nat, TC.Utf8.left(value, Some{TC.Limits.traceparent_input(limits)})),
      Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)), False{},
      StateProof.within(value, TC.Limits.traceparent_input(limits)), larger))

# Law read_within_budgets: within either budget, reading is the same reading
# of the value without its surrounding whitespace (read_fits).
law read_within_budgets:
  for +first: TC.Limits
  for +second: TC.Limits
  for +value: String
  for first_fits: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(first)) == True{} : Bool}
  for second_fits: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(second)) == True{} : Bool}
  {TC.TraceParent.read(first, value) == TC.TraceParent.read(second, value) :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_within_budgets(first, second, value, first_fits, second_fits):
  Equal.trans(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(first, value),
    TC.Read.trimmed(TC.Text.trim_ows(value)), TC.TraceParent.read(second, value),
    read_fits(first, value, first_fits),
    Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(second, value),
      TC.Read.trimmed(TC.Text.trim_ows(value)), read_fits(second, value, second_fits)))

# Whitespace around a value
# =========================
#
# The package removes the whitespace at the start of a value in a loop
# (Text.drop_ows) and the whitespace at its end by reversing, removing the
# whitespace at the start and reversing back (Text.trim_ows). LAWS.bend
# states both with plain recursions (Laws.ows_start, Laws.ows_end). The
# lemmas below show that they agree: drop_start for the start, and
# end_reversed for the end, which follows the text reversed one character at
# a time.

# A character that is not whitespace stops the loop: the text is kept.
law drop_go_false:
  for tail: String
  for head: Char
  {TC.Text.drop_ows.go(tail, head, False{}) == SCon{head, tail} : String}

def drop_go_false(tail, head):
  match tail:
    case SNil{}:
      {==}
    case SCon{next, rest}:
      {==}

# A whitespace character is dropped, and the loop goes on with the rest.
law drop_go_true:
  for tail: String
  for -head: Char
  {TC.Text.drop_ows.go(tail, head, True{}) == TC.Text.drop_ows(tail) : String}

def drop_go_true(tail, head):
  match tail:
    case SNil{}:
      {==}
    case SCon{next, rest}:
      {==}

# The step of drop_start for a first character `head`, with `ows` standing
# for whether it is whitespace and `later` the lemma for the rest.
law drop_step:
  for +rest: String
  for +head: Char
  for ows: Bool
  for later: {TC.Text.drop_ows(rest) == Laws.ows_start(rest) : String}
  {TC.Text.drop_ows.go(rest, head, ows) == Bool.pick(String, ows, Laws.ows_start(rest), SCon{head, rest}) : String}

def drop_step(rest, head, ows, later):
  match ows:
    case True{}:
      Equal.trans(String, TC.Text.drop_ows.go(rest, head, True{}), TC.Text.drop_ows(rest), Laws.ows_start(rest),
        drop_go_true(rest, head), later)
    case False{}:
      drop_go_false(rest, head)

# The package's loop removes exactly the whitespace Laws.ows_start removes.
# Induction on the text.
law drop_start:
  for +text: String
  {TC.Text.drop_ows(text) == Laws.ows_start(text) : String}

def drop_start(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      drop_step(rest, head, TC.StateChar.is_ows(head), drop_start(rest))

# A text reversed onto `acc` is all whitespace exactly when the text and
# `acc` both are. Induction on the text, with BoolsProof.and_swap regrouping
# the checks.
law all_ows_reverse:
  for +text: String
  for +acc: String
  {Laws.all_ows(String.reverse.go(text, acc)) == Bool.and(Laws.all_ows(text), Laws.all_ows(acc)) : Bool}

def all_ows_reverse(text, acc):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +tail}:
      Equal.trans(Bool, Laws.all_ows(String.reverse.go(tail, SCon{head, acc})),
        Bool.and(Laws.all_ows(tail), Laws.all_ows(SCon{head, acc})),
        Bool.and(Laws.all_ows(SCon{head, tail}), Laws.all_ows(acc)),
        all_ows_reverse(tail, SCon{head, acc}),
        BoolsProof.and_swap(Laws.all_ows(tail), Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')),
          Laws.all_ows(acc)))

# Whitespace before a text does not change what Laws.ows_start leaves.
# Induction on the whitespace.
law start_ows:
  for +before: String
  for +text: String
  for +all: {Laws.all_ows(before) == True{} : Bool}
  {Laws.ows_start(before ++ text) == Laws.ows_start(text) : String}

def start_ows(before, text, all):
  match before:
    case SNil{}:
      {==}
    case SCon{+head, +tail}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), True{},
        BoolsProof.and_left(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(tail), all)) :
        {Bool.pick(String, _, Laws.ows_start(tail ++ text), SCon{head, tail ++ text}) == Laws.ows_start(text) : String}
      start_ows(tail, text,
        BoolsProof.and_right(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(tail), all))

# A text of whitespace only has nothing left at its end.
law end_all:
  for +text: String
  for all: {Laws.all_ows(text) == True{} : Bool}
  {Laws.ows_end(text) == SNil{} : String}

def end_all(text, all):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +tail}:
      %Equal.sym(Bool, Laws.all_ows(SCon{head, tail}), True{}, all) :
        {Bool.pick(String, _, SNil{}, SCon{head, Laws.ows_end(tail)}) == SNil{} : String}
      {==}

# The step of start_solid for a first character `head`, with `ows` standing
# for whether it is whitespace and `later` the lemma for the rest.
law start_solid_step:
  for +head: Char
  for +rest: String
  for +after: String
  for ows: Bool
  for evidence: {Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')) == ows : Bool}
  for some: {Bool.and(ows, Laws.all_ows(rest)) == False{} : Bool}
  for later: {Laws.all_ows(rest) == False{} : Bool} ->
    {Laws.ows_start(rest ++ after) == Laws.ows_start(rest) ++ after : String}
  {Laws.ows_start(SCon{head, rest} ++ after) == Laws.ows_start(SCon{head, rest}) ++ after : String}

def start_solid_step(head, rest, after, ows, evidence, some, later):
  match ows:
    case True{}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), True{}, evidence) :
        {Bool.pick(String, _, Laws.ows_start(rest ++ after), SCon{head, rest ++ after}) ==
          Bool.pick(String, _, Laws.ows_start(rest), SCon{head, rest}) ++ after : String}
      later(some)
    case False{}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), False{}, evidence) :
        {Bool.pick(String, _, Laws.ows_start(rest ++ after), SCon{head, rest ++ after}) ==
          Bool.pick(String, _, Laws.ows_start(rest), SCon{head, rest}) ++ after : String}
      {==}

# When a text is not all whitespace, Laws.ows_start stops inside it, so what
# follows is kept whole. Induction on the text; the empty text is all
# whitespace, which contradicts `some`.
law start_solid:
  for +text: String
  for +after: String
  for some: {Laws.all_ows(text) == False{} : Bool}
  {Laws.ows_start(text ++ after) == Laws.ows_start(text) ++ after : String}

def start_solid(text, after, some):
  match text:
    case SNil{}:
      Empty.absurd({Laws.ows_start(SNil{} ++ after) == Laws.ows_start(SNil{}) ++ after : String},
        BoolsProof.true_ne_false(some))
    case SCon{+head, +rest}:
      start_solid_step(head, rest, after, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), {==}, some,
        solid => start_solid(rest, after, solid))

# The step of end_reversed when the rest is all whitespace: the last
# character decides, and it is kept exactly when it is not whitespace.
law end_single:
  for +head: Char
  for +rest: String
  for ows: Bool
  for evidence: {Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')) == ows : Bool}
  for rest_all: {Laws.all_ows(rest) == True{} : Bool}
  {String.reverse.go(Bool.pick(String, ows, SNil{}, SCon{head, SNil{}}), SNil{}) == Laws.ows_end(SCon{head, rest}) :
    String}

def end_single(head, rest, ows, evidence, rest_all):
  match ows:
    case True{}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), True{}, evidence) :
        {SNil{} == Bool.pick(String, Bool.and(_, Laws.all_ows(rest)), SNil{}, SCon{head, Laws.ows_end(rest)}) : String}
      %Equal.sym(Bool, Laws.all_ows(rest), True{}, rest_all) :
        {SNil{} == Bool.pick(String, _, SNil{}, SCon{head, Laws.ows_end(rest)}) : String}
      {==}
    case False{}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), False{}, evidence) :
        {SCon{head, SNil{}} == Bool.pick(String, Bool.and(_, Laws.all_ows(rest)), SNil{}, SCon{head, Laws.ows_end(rest)}) :
          String}
      %Equal.sym(String, Laws.ows_end(rest), SNil{}, end_all(rest, rest_all)) :
        {SCon{head, SNil{}} == SCon{head, _} : String}
      {==}

# The step of end_reversed for a first character `head` of the text, with
# `rest_ows` standing for whether the rest is all whitespace and `later` the
# lemma for the rest. Reversed, `head` comes last: when the rest is all
# whitespace it alone decides (end_single); otherwise Laws.ows_start stops
# inside the reversed rest, and `head` stays in front of the rest's result.
law end_reversed_step:
  for +head: Char
  for +rest: String
  for rest_ows: Bool
  for +evidence: {Laws.all_ows(rest) == rest_ows : Bool}
  for later: {String.reverse.go(Laws.ows_start(String.reverse.go(rest, SNil{})), SNil{}) == Laws.ows_end(rest) : String}
  {String.reverse.go(Laws.ows_start(String.reverse.go(rest, SNil{}) ++ SCon{head, SNil{}}), SNil{}) ==
    Laws.ows_end(SCon{head, rest}) : String}

def end_reversed_step(head, rest, rest_ows, evidence, later):
  match rest_ows:
    case True{}:
      %Equal.sym(String, Laws.ows_start(String.reverse.go(rest, SNil{}) ++ SCon{head, SNil{}}),
        Laws.ows_start(SCon{head, SNil{}}),
        start_ows(String.reverse.go(rest, SNil{}), SCon{head, SNil{}},
          Equal.trans(Bool, Laws.all_ows(String.reverse.go(rest, SNil{})), Bool.and(Laws.all_ows(rest), True{}), True{},
            all_ows_reverse(rest, SNil{}),
            Equal.cong(Bool, Bool, all => Bool.and(all, True{}), Laws.all_ows(rest), True{}, evidence)))) :
        {String.reverse.go(_, SNil{}) == Laws.ows_end(SCon{head, rest}) : String}
      end_single(head, rest, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), {==}, evidence)
    case False{}:
      %Equal.sym(String, Laws.ows_start(String.reverse.go(rest, SNil{}) ++ SCon{head, SNil{}}),
        Laws.ows_start(String.reverse.go(rest, SNil{})) ++ SCon{head, SNil{}},
        start_solid(String.reverse.go(rest, SNil{}), SCon{head, SNil{}},
          Equal.trans(Bool, Laws.all_ows(String.reverse.go(rest, SNil{})), Bool.and(Laws.all_ows(rest), True{}), False{},
            all_ows_reverse(rest, SNil{}),
            Equal.cong(Bool, Bool, all => Bool.and(all, True{}), Laws.all_ows(rest), False{}, evidence)))) :
        {String.reverse.go(_, SNil{}) == Laws.ows_end(SCon{head, rest}) : String}
      %Equal.sym(String, String.reverse.go(Laws.ows_start(String.reverse.go(rest, SNil{})) ++ SCon{head, SNil{}}, SNil{}),
        String.reverse.go(SCon{head, SNil{}}, String.reverse.go(Laws.ows_start(String.reverse.go(rest, SNil{})), SNil{})),
        StringsProof.reverse_append(Laws.ows_start(String.reverse.go(rest, SNil{})), SCon{head, SNil{}}, SNil{})) :
        {_ == Laws.ows_end(SCon{head, rest}) : String}
      %Equal.sym(String, String.reverse.go(Laws.ows_start(String.reverse.go(rest, SNil{})), SNil{}), Laws.ows_end(rest),
        later) :
        {SCon{head, _} == Laws.ows_end(SCon{head, rest}) : String}
      %Equal.sym(Bool, Laws.all_ows(rest), False{}, evidence) :
        {SCon{head, Laws.ows_end(rest)} == Bool.pick(String, Bool.and(Bool.or(Char.is_eq(head, ' '),
          Char.is_eq(head, '\t')), _), SNil{}, SCon{head, Laws.ows_end(rest)}) : String}
      %Equal.sym(Bool, Bool.and(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), False{}), False{},
        BoolsProof.and_false(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')))) :
        {SCon{head, Laws.ows_end(rest)} == Bool.pick(String, _, SNil{}, SCon{head, Laws.ows_end(rest)}) : String}
      {==}

# Reversing a text, removing the whitespace at the start and reversing back
# removes exactly the whitespace Laws.ows_end removes at the end. Induction
# on the text: reversed, its first character comes last (reverse_onto).
law end_reversed:
  for +text: String
  {String.reverse.go(Laws.ows_start(String.reverse.go(text, SNil{})), SNil{}) == Laws.ows_end(text) : String}

def end_reversed(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      %Equal.sym(String, String.reverse.go(rest, SCon{head, SNil{}}),
        String.reverse.go(rest, SNil{}) ++ SCon{head, SNil{}}, StringsProof.reverse_onto(rest, SCon{head, SNil{}})) :
        {String.reverse.go(Laws.ows_start(_), SNil{}) == Laws.ows_end(SCon{head, rest}) : String}
      end_reversed_step(head, rest, Laws.all_ows(rest), {==}, end_reversed(rest))

# Text.trim_ows removes exactly the whitespace around the text, as
# Laws.trimmed states it.
law trim_law:
  for +text: String
  {TC.Text.trim_ows(text) == Laws.trimmed(text) : String}

def trim_law(text):
  %Equal.sym(String, TC.Text.drop_ows(text), Laws.ows_start(text), drop_start(text)) :
    {String.reverse(TC.Text.drop_ows(String.reverse(_))) == Laws.trimmed(text) : String}
  %Equal.sym(String, TC.Text.drop_ows(String.reverse(Laws.ows_start(text))),
    Laws.ows_start(String.reverse(Laws.ows_start(text))), drop_start(String.reverse(Laws.ows_start(text)))) :
    {String.reverse(_) == Laws.trimmed(text) : String}
  end_reversed(Laws.ows_start(text))

# Accepted messages
# =================

# The package's extraction of an accepted message with parsed tracestate
# fields is Laws.accepted.parsed, for every result of parsing them.
law parsed_law:
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for remote: TC.RemoteContext
  for text: String
  for fields: List<&2, String>
  {TC.Extract.parsed(parsed, remote, text, fields) == Laws.accepted.parsed(parsed, remote, text, fields) : TC.Extraction}

def parsed_law(parsed, remote, text, fields):
  match parsed:
    case Fail{error}:
      {==}
    case Done{state}:
      {==}

# The package's extraction of an accepted message is Laws.accepted, for every
# list of tracestate field values.
law state_law:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for remote: TC.RemoteContext
  for text: String
  {TC.Extract.state(limits, fields, remote, text) == Laws.accepted(limits, remote, text, fields) : TC.Extraction}

def state_law(limits, fields, remote, text):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      parsed_law(TC.TraceState.parse_fields(limits, Con{field, rest}), remote, text, Con{field, rest})

# Law extract_read: with one value, which TraceParent.read accepts,
# Extract.read reads the tracestate fields with the value kept without its
# surrounding whitespace (trim_law).
law extract_read:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for +value: String
  for +known: TC.TraceParentV00
  for single: {Laws.named("traceparent", carrier) == Con{value, Nil{}} : List<&2, String>}
  for read: {TC.TraceParent.read(limits, value) == Done{known} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {TC.Context.extract(limits, carrier, base) == Laws.accepted(limits, TC.RemoteContext.from_traceparent(known),
    Laws.trimmed(value), Laws.named("tracestate", carrier)) : TC.Extraction}

def extract_read(limits, carrier, base, value, known, single, read):
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base),
    extract_named(limits, carrier, base)) :
    {_ == Laws.accepted(limits, TC.RemoteContext.from_traceparent(known), Laws.trimmed(value),
      Laws.named("tracestate", carrier)) : TC.Extraction}
  %Equal.sym(List<&2, String>, Laws.named("traceparent", carrier), Con{value, Nil{}}, single) :
    {TC.Extract.parents(limits, _, Laws.named("tracestate", carrier), base) ==
      Laws.accepted(limits, TC.RemoteContext.from_traceparent(known), Laws.trimmed(value),
        Laws.named("tracestate", carrier)) : TC.Extraction}
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, value),
    Done{known}, read) :
    {TC.Extract.read(_, value, limits, Laws.named("tracestate", carrier), base) ==
      Laws.accepted(limits, TC.RemoteContext.from_traceparent(known), Laws.trimmed(value),
        Laws.named("tracestate", carrier)) : TC.Extraction}
  %Equal.sym(String, TC.Text.trim_ows(value), Laws.trimmed(value), trim_law(value)) :
    {TC.Extract.state(limits, Laws.named("tracestate", carrier), TC.RemoteContext.from_traceparent(known), _) ==
      Laws.accepted(limits, TC.RemoteContext.from_traceparent(known), Laws.trimmed(value),
        Laws.named("tracestate", carrier)) : TC.Extraction}
  state_law(limits, Laws.named("tracestate", carrier), TC.RemoteContext.from_traceparent(known), Laws.trimmed(value))

# Reading a traceparent value
# ===========================
#
# TraceParent.read measures the value, removes the whitespace around it,
# refuses a comma and reads the known fields by the rules of its version.
# The laws on it follow those steps. Plain texts, without a comma, a space or
# a tab, pass the whitespace and comma steps unchanged; the digits and dashes
# of a traceparent are plain.

# A hexadecimal digit is neither a comma nor whitespace, so Laws.plain passes
# over it. By cases on the digit; each case computes.
law digit_plain:
  for digit: Hex.Digit
  for +rest: String
  {Laws.plain(SCon{Hex.Digit.to_char(digit), rest}) == Laws.plain(rest) : Bool}

def digit_plain(digit, rest):
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

# The digits of a sequence pass Laws.plain one by one. Induction on the
# number of digits.
law digits_plain:
  for n: Nat
  for digits: Digits.Digits(n)
  for +rest: String
  {Laws.plain(Digits.Digits.to_string(n, digits) ++ rest) == Laws.plain(rest) : Bool}

def digits_plain(n, digits, rest):
  match n:
    case 0n:
      match digits:
        case Digits.DNil{}:
          {==}
    case 1n+(+p):
      match digits:
        case Digits.DCon{head, +tail}:
          Equal.trans(Bool, Laws.plain(SCon{Hex.Digit.to_char(head), Digits.Digits.to_string(p, tail) ++ rest}),
            Laws.plain(Digits.Digits.to_string(p, tail) ++ rest), Laws.plain(rest),
            digit_plain(head, Digits.Digits.to_string(p, tail) ++ rest), digits_plain(p, tail, rest))

# The text of a strict v00 value from its first dash, followed by `rest`,
# passes Laws.plain exactly when `rest` does: its digits and dashes are
# neither commas nor whitespace. StringsProof.string_assoc regroups the text
# so that `rest` follows each group of digits.
law format_plain:
  for known: TC.TraceParentV00
  for +rest: String
  {Laws.plain(String.drop(TC.TraceParentV00.format(known), 2n) ++ rest) == Laws.plain(rest) : Bool}

def format_plain(known, rest):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      +trace = Digits.NonZero.to_string(32n, trace_id)
      +parent = Digits.NonZero.to_string(16n, parent_id)
      +flag_text = Digits.Digits.to_string(2n, flags)
      Equal.trans(Bool, Laws.plain((trace ++ "-" ++ parent ++ "-" ++ flag_text) ++ rest),
        Laws.plain(trace ++ ("-" ++ parent ++ "-" ++ flag_text) ++ rest), Laws.plain(rest),
        Equal.cong(String, Bool, text => Laws.plain(text), (trace ++ "-" ++ parent ++ "-" ++ flag_text) ++ rest,
          trace ++ ("-" ++ parent ++ "-" ++ flag_text) ++ rest,
          StringsProof.string_assoc(trace, "-" ++ parent ++ "-" ++ flag_text, rest)),
        Equal.trans(Bool, Laws.plain(trace ++ ("-" ++ parent ++ "-" ++ flag_text) ++ rest),
          Laws.plain((parent ++ "-" ++ flag_text) ++ rest), Laws.plain(rest),
          digits_plain(32n, Digits.NonZero.digits(32n, trace_id), ("-" ++ parent ++ "-" ++ flag_text) ++ rest),
          Equal.trans(Bool, Laws.plain((parent ++ "-" ++ flag_text) ++ rest),
            Laws.plain(parent ++ ("-" ++ flag_text) ++ rest), Laws.plain(rest),
            Equal.cong(String, Bool, text => Laws.plain(text), (parent ++ "-" ++ flag_text) ++ rest,
              parent ++ ("-" ++ flag_text) ++ rest, StringsProof.string_assoc(parent, "-" ++ flag_text, rest)),
            Equal.trans(Bool, Laws.plain(parent ++ ("-" ++ flag_text) ++ rest), Laws.plain(flag_text ++ rest),
              Laws.plain(rest),
              digits_plain(16n, Digits.NonZero.digits(16n, parent_id), ("-" ++ flag_text) ++ rest),
              digits_plain(2n, flags, rest)))))

# The text of a strict v00 value is plain.
law format_solid:
  for known: TC.TraceParentV00
  {Laws.plain(TC.TraceParentV00.format(known)) == True{} : Bool}

def format_solid(known):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      Equal.trans(Bool, Laws.plain(String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n)),
        Laws.plain(String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n) ++ ""),
        True{},
        Equal.cong(String, Bool, text => Laws.plain(text),
          String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n),
          String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n) ++ "",
          Equal.sym(String, String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n) ++ "",
            String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n),
            StringsProof.append_nil(String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}),
              2n)))),
        format_plain(TC.TraceParentV00{trace_id, parent_id, flags}, ""))

# The first character of a plain text is not whitespace.
law plain_head:
  for +head: Char
  for +rest: String
  for +holds: {Laws.plain(SCon{head, rest}) == True{} : Bool}
  {Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')) == False{} : Bool}

def plain_head(head, rest, holds):
  %Equal.sym(Bool, Char.is_eq(head, ' '), False{},
    BoolsProof.not_true(Char.is_eq(head, ' '),
      BoolsProof.and_left(Bool.not(Char.is_eq(head, ' ')), Laws.lacks(' ', rest),
        BoolsProof.and_left(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest}),
          BoolsProof.and_right(Laws.lacks(',', SCon{head, rest}),
            Bool.and(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest})), holds))))) :
    {Bool.or(_, Char.is_eq(head, '\t')) == False{} : Bool}
  BoolsProof.not_true(Char.is_eq(head, '\t'),
    BoolsProof.and_left(Bool.not(Char.is_eq(head, '\t')), Laws.lacks('\t', rest),
      BoolsProof.and_right(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest}),
        BoolsProof.and_right(Laws.lacks(',', SCon{head, rest}),
          Bool.and(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest})), holds))))

# The rest of a plain text is plain.
law plain_tail:
  for +head: Char
  for +rest: String
  for +holds: {Laws.plain(SCon{head, rest}) == True{} : Bool}
  {Laws.plain(rest) == True{} : Bool}

def plain_tail(head, rest, holds):
  %Equal.sym(Bool, Laws.lacks(',', rest), True{},
    BoolsProof.and_right(Bool.not(Char.is_eq(head, ',')), Laws.lacks(',', rest),
      BoolsProof.and_left(Laws.lacks(',', SCon{head, rest}),
        Bool.and(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest})), holds))) :
    {Bool.and(_, Bool.and(Laws.lacks(' ', rest), Laws.lacks('\t', rest))) == True{} : Bool}
  %Equal.sym(Bool, Laws.lacks(' ', rest), True{},
    BoolsProof.and_right(Bool.not(Char.is_eq(head, ' ')), Laws.lacks(' ', rest),
      BoolsProof.and_left(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest}),
        BoolsProof.and_right(Laws.lacks(',', SCon{head, rest}),
          Bool.and(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest})), holds)))) :
    {Bool.and(True{}, Bool.and(_, Laws.lacks('\t', rest))) == True{} : Bool}
  BoolsProof.and_right(Bool.not(Char.is_eq(head, '\t')), Laws.lacks('\t', rest),
    BoolsProof.and_right(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest}),
      BoolsProof.and_right(Laws.lacks(',', SCon{head, rest}),
        Bool.and(Laws.lacks(' ', SCon{head, rest}), Laws.lacks('\t', SCon{head, rest})), holds)))

# A text of whitespace only is removed whole by Laws.ows_start. Induction on
# the text.
law start_all:
  for +text: String
  for +all: {Laws.all_ows(text) == True{} : Bool}
  {Laws.ows_start(text) == SNil{} : String}

def start_all(text, all):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +tail}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), True{},
        BoolsProof.and_left(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(tail), all)) :
        {Bool.pick(String, _, Laws.ows_start(tail), SCon{head, tail}) == SNil{} : String}
      start_all(tail, BoolsProof.and_right(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(tail), all))

# Laws.ows_end keeps a plain text whole when only whitespace follows it.
# Induction on the text.
law end_plain:
  for +text: String
  for +after: String
  for +holds: {Laws.plain(text) == True{} : Bool}
  for +all: {Laws.all_ows(after) == True{} : Bool}
  {Laws.ows_end(text ++ after) == text : String}

def end_plain(text, after, holds, all):
  match text:
    case SNil{}:
      end_all(after, all)
    case SCon{+head, +rest}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), False{}, plain_head(head, rest, holds)) :
        {Bool.pick(String, Bool.and(_, Laws.all_ows(rest ++ after)), SNil{}, SCon{head, Laws.ows_end(rest ++ after)}) ==
          SCon{head, rest} : String}
      %Equal.sym(String, Laws.ows_end(rest ++ after), rest, end_plain(rest, after, plain_tail(head, rest, holds), all)) :
        {SCon{head, _} == SCon{head, rest} : String}
      {==}

# Laws.trimmed of a plain text followed by whitespace only is that text.
law trimmed_rest:
  for +text: String
  for +after: String
  for +holds: {Laws.plain(text) == True{} : Bool}
  for +all: {Laws.all_ows(after) == True{} : Bool}
  {Laws.ows_end(Laws.ows_start(text ++ after)) == text : String}

def trimmed_rest(text, after, holds, all):
  match text:
    case SNil{}:
      %Equal.sym(String, Laws.ows_start(after), SNil{}, start_all(after, all)) :
        {Laws.ows_end(_) == SNil{} : String}
      {==}
    case SCon{+head, +rest}:
      %Equal.sym(Bool, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), False{}, plain_head(head, rest, holds)) :
        {Laws.ows_end(Bool.pick(String, _, Laws.ows_start(rest ++ after), SCon{head, rest ++ after})) ==
          SCon{head, rest} : String}
      end_plain(SCon{head, rest}, after, holds, all)

# Laws.trimmed removes exactly the whitespace around a plain text.
law trimmed_solid:
  for +before: String
  for +text: String
  for +after: String
  for before_ows: {Laws.all_ows(before) == True{} : Bool}
  for +holds: {Laws.plain(text) == True{} : Bool}
  for +after_ows: {Laws.all_ows(after) == True{} : Bool}
  {Laws.trimmed(before ++ text ++ after) == text : String}

def trimmed_solid(before, text, after, before_ows, holds, after_ows):
  %Equal.sym(String, Laws.ows_start(before ++ text ++ after), Laws.ows_start(text ++ after),
    start_ows(before, text ++ after, before_ows)) :
    {Laws.ows_end(_) == text : String}
  trimmed_rest(text, after, holds, after_ows)

# A plain text has no whitespace to remove.
law trimmed_plain:
  for +text: String
  for +holds: {Laws.plain(text) == True{} : Bool}
  {Laws.trimmed(text) == text : String}

def trimmed_plain(text, holds):
  Equal.trans(String, Laws.trimmed(text), Laws.trimmed(text ++ ""), text,
    Equal.cong(String, String, value => Laws.trimmed(value), text, text ++ "",
      Equal.sym(String, text ++ "", text, StringsProof.append_nil(text))),
    trimmed_rest(text, "", holds, {==}))

# The package's comma search, from `found`, reports a comma exactly when one
# was found before or Laws.lacks finds one. Induction on the text.
law comma_go:
  for +text: String
  for found: Bool
  {TC.Text.has_comma.go(text, found) == Bool.or(found, Bool.not(Laws.lacks(',', text))) : Bool}

def comma_go(text, found):
  match text found:
    case SNil{} True{}:
      {==}
    case SNil{} False{}:
      {==}
    case SCon{char, rest} True{}:
      {==}
    case SCon{+char, +rest} False{}:
      Equal.trans(Bool, TC.Text.has_comma.go(rest, Char.is_eq(char, ',')),
        Bool.or(Char.is_eq(char, ','), Bool.not(Laws.lacks(',', rest))),
        Bool.not(Laws.lacks(',', SCon{char, rest})),
        comma_go(rest, Char.is_eq(char, ',')),
        BoolsProof.or_not(Char.is_eq(char, ','), Laws.lacks(',', rest)))

# A plain text has no comma.
law plain_comma:
  for +text: String
  for holds: {Laws.plain(text) == True{} : Bool}
  {TC.Text.has_comma(text) == False{} : Bool}

def plain_comma(text, holds):
  Equal.trans(Bool, TC.Text.has_comma(text), Bool.not(Laws.lacks(',', text)), False{},
    comma_go(text, False{}),
    Equal.cong(Bool, Bool, found => Bool.not(found), Laws.lacks(',', text), True{},
      BoolsProof.and_left(Laws.lacks(',', text), Bool.and(Laws.lacks(' ', text), Laws.lacks('\t', text)), holds)))

# For each of the 256 versions, given as two digits, a version that
# Laws.later_version accepts is read by its known prefix: 00 and ff
# contradict `holds`, and every other version computes to Done{True{}}.
law later_digits:
  for high: Hex.Digit
  for low: Hex.Digit
  for holds: {Laws.later_version(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}) == True{} : Bool}
  {TC.Read.is_later(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}) == Done{True{}} :
    Result<&2, &2, TC.Error, Bool>}

def later_digits(high, low, holds):
  match high:
    case Hex.H0{}:
      match low:
        case Hex.H0{}:
          BoolsProof.absurd({TC.Read.is_later(Digits.DCon{Hex.H0{}, Digits.DCon{Hex.H0{}, Digits.DNil{}}}) ==
            Done{True{}} : Result<&2, &2, TC.Error, Bool>}, holds)
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
      match low:
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
          BoolsProof.absurd({TC.Read.is_later(Digits.DCon{Hex.Hf{}, Digits.DCon{Hex.Hf{}, Digits.DNil{}}}) ==
            Done{True{}} : Result<&2, &2, TC.Error, Bool>}, holds)

# A later version is read by its known prefix.
law later:
  for version: Digits.Digits(2n)
  for holds: {Laws.later_version(version) == True{} : Bool}
  {TC.Read.is_later(version) == Done{True{}} : Result<&2, &2, TC.Error, Bool>}

def later(version, holds):
  match version:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      later_digits(high, low, holds)

# The known prefix of a later version has 55 characters: two version digits
# and the 53 of a strict v00 value after its version
# (ContextProof.tail_length).
law prefix_length:
  for +version: Digits.Digits(2n)
  for known: TC.TraceParentV00
  {String.length(Digits.Digits.to_string(2n, version) ++ String.drop(TC.TraceParentV00.format(known), 2n)) == 55n :
    Nat}

def prefix_length(version, known):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      StringsProof.joined_length(Digits.Digits.to_string(2n, version),
        "-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++ Digits.NonZero.to_string(16n, parent_id) ++ "-" ++
          Digits.Digits.to_string(2n, flags),
        2n, 53n, DigitsProof.encoded_length(2n, version), ContextProof.tail_length(trace_id, parent_id, flags))

# Unknown fields that pass Laws.unknown_fields are plain: a dash, then plain
# characters.
law unknown_plain:
  for +unknown: String
  for +holds: {Laws.unknown_fields(unknown) == True{} : Bool}
  {Laws.plain(unknown) == True{} : Bool}

def unknown_plain(unknown, holds):
  match unknown:
    case SNil{}:
      {==}
    case SCon{+first, +rest}:
      %Equal.sym(Char, first, '-', CharsProof.char_sound(first, '-', BoolsProof.and_left(Char.is_eq(first, '-'), Laws.plain(rest),
        holds))) :
        {Laws.plain(SCon{_, rest}) == True{} : Bool}
      BoolsProof.and_right(Char.is_eq(first, '-'), Laws.plain(rest), holds)

# The text of a later version is plain: its version digits, the known fields
# of a strict v00 value and plain unknown fields.
law future_plain:
  for +version: Digits.Digits(2n)
  for +known: TC.TraceParentV00
  for +unknown: String
  for +holds: {Laws.unknown_fields(unknown) == True{} : Bool}
  {Laws.plain(Laws.future(version, known, unknown)) == True{} : Bool}

def future_plain(version, known, unknown, holds):
  Equal.trans(Bool, Laws.plain(Laws.future(version, known, unknown)),
    Laws.plain(String.drop(TC.TraceParentV00.format(known), 2n) ++ unknown), True{},
    digits_plain(2n, version, String.drop(TC.TraceParentV00.format(known), 2n) ++ unknown),
    Equal.trans(Bool, Laws.plain(String.drop(TC.TraceParentV00.format(known), 2n) ++ unknown), Laws.plain(unknown),
      True{}, format_plain(known, unknown), unknown_plain(unknown, holds)))

# The steps of Read.known after reading the two version digits, as a
# function of that read: they mirror the package's do block, so that a
# rewrite motive can mark the read with `_`.
def known_result(parsed: Result<&2, &2, TC.Error, TC.Parsed<2n>>, text: String) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    version : TC.Parsed<2n> <- parsed
    later : Bool <- TC.Read.is_later.parsed(version)
    TC.Read.by_version(later, text)

# The steps of Read.known after the rules of the version.
def version_result(rules: Result<&2, &2, TC.Error, Bool>, text: String) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    later : Bool <- rules
    TC.Read.by_version(later, text)

# The steps of Read.prefix after reading the known fields, as a
# function of that read and of what follows the flags.
def prefix_result(parsed: Result<&2, &2, TC.Error, TC.TraceParentV00>, rest: String) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    known : TC.TraceParentV00 <- parsed
    unknown : Unit <- TC.Read.extension(rest)
    return known

# The last step of Read.prefix, once the known fields are read.
def unit_then(extension: Result<&2, &2, TC.Error, Unit>, known: TC.TraceParentV00) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    unknown : Unit <- extension
    return known

# The step of Read.extension after a first character.
def dash_result(read: Result<&2, &2, TC.Error, String>) -> Result<&2, &2, TC.Error, Unit>:
  do Result<&2, &2, TC.Error, Unit>:
    unknown : String <- read
    return Unit{}

# Unknown fields that pass Laws.unknown_fields are accepted after the flags.
law unknown_ok:
  for +unknown: String
  for +holds: {Laws.unknown_fields(unknown) == True{} : Bool}
  {TC.Read.extension(unknown) == Done{Unit{}} : Result<&2, &2, TC.Error, Unit>}

def unknown_ok(unknown, holds):
  match unknown:
    case SNil{}:
      {==}
    case SCon{+first, +rest}:
      %Equal.sym(Bool, Char.is_eq(first, '-'), True{}, BoolsProof.and_left(Char.is_eq(first, '-'), Laws.plain(rest),
        holds)) :
        {dash_result(TC.Parse.separator_result(rest, _, 55n)) == Done{Unit{}} : Result<&2, &2, TC.Error, Unit>}
      {==}

# The first 55 characters of a later version's text are its known prefix:
# the text is the prefix followed by the unknown fields (string_assoc), and
# the prefix has 55 characters (prefix_length).
law take_prefix:
  for +version: Digits.Digits(2n)
  for +known: TC.TraceParentV00
  for +unknown: String
  {String.take(Laws.future(version, known, unknown), 55n) ==
    Digits.Digits.to_string(2n, version) ++ String.drop(TC.TraceParentV00.format(known), 2n) : String}

def take_prefix(version, known, unknown):
  +prefix = Digits.Digits.to_string(2n, version) ++ String.drop(TC.TraceParentV00.format(known), 2n)
  Equal.trans(String, String.take(Laws.future(version, known, unknown), 55n), String.take(prefix ++ unknown, 55n), prefix,
    Equal.cong(String, String, text => String.take(text, 55n), Laws.future(version, known, unknown), prefix ++ unknown,
      Equal.sym(String, prefix ++ unknown, Laws.future(version, known, unknown),
        StringsProof.string_assoc(Digits.Digits.to_string(2n, version), String.drop(TC.TraceParentV00.format(known), 2n),
          unknown))),
    Equal.trans(String, String.take(prefix ++ unknown, 55n), String.take(prefix ++ unknown, String.length(prefix)),
      prefix,
      Equal.cong(Nat, String, count => String.take(prefix ++ unknown, count), 55n, String.length(prefix),
        Equal.sym(Nat, String.length(prefix), 55n, prefix_length(version, known))),
      StringsProof.take_append(prefix, unknown)))

# What follows the first 55 characters of a later version's text is its
# unknown fields.
law drop_prefix:
  for +version: Digits.Digits(2n)
  for +known: TC.TraceParentV00
  for +unknown: String
  {String.drop(Laws.future(version, known, unknown), 55n) == unknown : String}

def drop_prefix(version, known, unknown):
  +prefix = Digits.Digits.to_string(2n, version) ++ String.drop(TC.TraceParentV00.format(known), 2n)
  Equal.trans(String, String.drop(Laws.future(version, known, unknown), 55n), String.drop(prefix ++ unknown, 55n),
    unknown,
    Equal.cong(String, String, text => String.drop(text, 55n), Laws.future(version, known, unknown), prefix ++ unknown,
      Equal.sym(String, prefix ++ unknown, Laws.future(version, known, unknown),
        StringsProof.string_assoc(Digits.Digits.to_string(2n, version), String.drop(TC.TraceParentV00.format(known), 2n),
          unknown))),
    Equal.trans(String, String.drop(prefix ++ unknown, 55n), String.drop(prefix ++ unknown, String.length(prefix)),
      unknown,
      Equal.cong(Nat, String, count => String.drop(prefix ++ unknown, count), 55n, String.length(prefix),
        Equal.sym(Nat, String.length(prefix), 55n, prefix_length(version, known))),
      StringsProof.drop_append(prefix, unknown)))

# The known fields of a later version's text are read as those of the
# strict v00 value they came from: the version digits are read back
# (ParserProof.digits_roundtrip), the version is later, and the first 55
# characters, with the version replaced by 00, are the text of that value
# (ContextProof.roundtrip); the unknown fields are accepted.
law future_known:
  for +version: Digits.Digits(2n)
  for +known: TC.TraceParentV00
  for +unknown: String
  for later_is: {Laws.later_version(version) == True{} : Bool}
  for +holds: {Laws.unknown_fields(unknown) == True{} : Bool}
  {TC.Read.known(Laws.future(version, known, unknown)) == Done{known} :
    Result<&2, &2, TC.Error, TC.TraceParentV00>}

def future_known(version, known, unknown, later_is, holds):
  match version:
    case Digits.DCon{+high, Digits.DCon{+low, Digits.DNil{}}}:
      match known:
        case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
          %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<2n>>,
            TC.Parse.digits(2n, Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              TC.TraceParentV00{trace_id, parent_id, flags}, unknown), 0n),
            Done{TC.Parsed{Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n) ++ unknown}},
            ParserProof.digits_roundtrip(2n, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n) ++ unknown, 0n)) :
            {known_result(_, Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              TC.TraceParentV00{trace_id, parent_id, flags}, unknown)) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
              Result<&2, &2, TC.Error, TC.TraceParentV00>}
          %Equal.sym(Result<&2, &2, TC.Error, Bool>, TC.Read.is_later(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}),
            Done{True{}}, later(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, later_is)) :
            {version_result(_, Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              TC.TraceParentV00{trace_id, parent_id, flags}, unknown)) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
              Result<&2, &2, TC.Error, TC.TraceParentV00>}
          %Equal.sym(String, String.take(Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              TC.TraceParentV00{trace_id, parent_id, flags}, unknown), 55n),
            Digits.Digits.to_string(2n, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}) ++
              String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n),
            take_prefix(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, TC.TraceParentV00{trace_id, parent_id, flags},
              unknown)) :
            {prefix_result(TC.TraceParentV00.parse("00" ++ String.drop(_, 2n)),
              String.drop(Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
                TC.TraceParentV00{trace_id, parent_id, flags}, unknown), 55n)) ==
              Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}
          %Equal.sym(String, String.drop(Laws.future(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}},
              TC.TraceParentV00{trace_id, parent_id, flags}, unknown), 55n), unknown,
            drop_prefix(Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}, TC.TraceParentV00{trace_id, parent_id, flags},
              unknown)) :
            {prefix_result(TC.TraceParentV00.parse("00" ++ String.drop(Digits.Digits.to_string(2n,
              Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}) ++
              String.drop(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}), 2n), 2n)), _) ==
              Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}
          %Equal.sym(Result<&2, &2, TC.Error, TC.TraceParentV00>,
            TC.TraceParentV00.parse(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags})),
            Done{TC.TraceParentV00{trace_id, parent_id, flags}},
            ContextProof.roundtrip(TC.TraceParentV00{trace_id, parent_id, flags})) :
            {prefix_result(_, unknown) == Done{TC.TraceParentV00{trace_id, parent_id, flags}} :
              Result<&2, &2, TC.Error, TC.TraceParentV00>}
          %Equal.sym(Result<&2, &2, TC.Error, Unit>, TC.Read.extension(unknown), Done{Unit{}},
            unknown_ok(unknown, holds)) :
            {unit_then(_, TC.TraceParentV00{trace_id, parent_id, flags}) ==
              Done{TC.TraceParentV00{trace_id, parent_id, flags}} : Result<&2, &2, TC.Error, TC.TraceParentV00>}
          {==}

# The known fields of a strict v00 text: version 00 sends it to the strict
# codec, which reads it back (ContextProof.roundtrip).
law v00_known:
  for known: TC.TraceParentV00
  {TC.Read.known(TC.TraceParentV00.format(known)) == Done{known} :
    Result<&2, &2, TC.Error, TC.TraceParentV00>}

def v00_known(known):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      ContextProof.roundtrip(TC.TraceParentV00{trace_id, parent_id, flags})

# Law read_v00: the value fits (read_fits), the whitespace around its plain
# text is removed (trim_law, trimmed_solid), it has no comma (plain_comma),
# and its version 00 sends it to the strict codec (v00_known).
law read_v00:
  for +limits: TC.Limits
  for +known: TC.TraceParentV00
  for +before: String
  for +after: String
  for before_ows: {Laws.all_ows(before) == True{} : Bool}
  for after_ows: {Laws.all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(before ++ TC.TraceParentV00.format(known) ++ after),
    TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {TC.TraceParent.read(limits, before ++ TC.TraceParentV00.format(known) ++ after) == Done{known} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_v00(limits, known, before, after, before_ows, after_ows, fits):
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>,
    TC.TraceParent.read(limits, before ++ TC.TraceParentV00.format(known) ++ after),
    TC.Read.trimmed(TC.Text.trim_ows(before ++ TC.TraceParentV00.format(known) ++ after)),
    read_fits(limits, before ++ TC.TraceParentV00.format(known) ++ after, fits)) :
    {_ == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, TC.Text.trim_ows(before ++ TC.TraceParentV00.format(known) ++ after),
    Laws.trimmed(before ++ TC.TraceParentV00.format(known) ++ after),
    trim_law(before ++ TC.TraceParentV00.format(known) ++ after)) :
    {TC.Read.trimmed(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, Laws.trimmed(before ++ TC.TraceParentV00.format(known) ++ after), TC.TraceParentV00.format(known),
    trimmed_solid(before, TC.TraceParentV00.format(known), after, before_ows, format_solid(known), after_ows)) :
    {TC.Read.trimmed(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Bool, TC.Text.has_comma(TC.TraceParentV00.format(known)), False{},
    plain_comma(TC.TraceParentV00.format(known), format_solid(known))) :
    {TC.Read.single(_, TC.TraceParentV00.format(known)) == Done{known} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Result<&2, &2, TC.Error, TC.TraceParentV00>, TC.Read.known(TC.TraceParentV00.format(known)),
    Done{known}, v00_known(known)) :
    {TC.Read.invalid(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {==}

# Law read_future: as read_v00, with future_plain for the text and
# future_known for its known fields.
law read_future:
  for +limits: TC.Limits
  for +version: Digits.Digits(2n)
  for +known: TC.TraceParentV00
  for +unknown: String
  for +before: String
  for +after: String
  for later_is: {Laws.later_version(version) == True{} : Bool}
  for +plain_unknown: {Laws.unknown_fields(unknown) == True{} : Bool}
  for before_ows: {Laws.all_ows(before) == True{} : Bool}
  for after_ows: {Laws.all_ows(after) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(before ++ Laws.future(version, known, unknown) ++ after),
    TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {TC.TraceParent.read(limits, before ++ Laws.future(version, known, unknown) ++ after) == Done{known} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_future(limits, version, known, unknown, before, after, later_is, plain_unknown, before_ows, after_ows, fits):
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>,
    TC.TraceParent.read(limits, before ++ Laws.future(version, known, unknown) ++ after),
    TC.Read.trimmed(TC.Text.trim_ows(before ++ Laws.future(version, known, unknown) ++ after)),
    read_fits(limits, before ++ Laws.future(version, known, unknown) ++ after, fits)) :
    {_ == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, TC.Text.trim_ows(before ++ Laws.future(version, known, unknown) ++ after),
    Laws.trimmed(before ++ Laws.future(version, known, unknown) ++ after),
    trim_law(before ++ Laws.future(version, known, unknown) ++ after)) :
    {TC.Read.trimmed(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, Laws.trimmed(before ++ Laws.future(version, known, unknown) ++ after),
    Laws.future(version, known, unknown),
    trimmed_solid(before, Laws.future(version, known, unknown), after, before_ows,
      future_plain(version, known, unknown, plain_unknown), after_ows)) :
    {TC.Read.trimmed(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Bool, TC.Text.has_comma(Laws.future(version, known, unknown)), False{},
    plain_comma(Laws.future(version, known, unknown), future_plain(version, known, unknown, plain_unknown))) :
    {TC.Read.single(_, Laws.future(version, known, unknown)) == Done{known} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Result<&2, &2, TC.Error, TC.TraceParentV00>, TC.Read.known(Laws.future(version, known, unknown)),
    Done{known}, future_known(version, known, unknown, later_is, plain_unknown)) :
    {TC.Read.invalid(_) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {==}

# Law read_ff: the text is plain, so it reaches the version check, which
# refuses ff by computation.
law read_ff:
  for +limits: TC.Limits
  for +rest: String
  for +plain_rest: {Laws.plain(rest) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length("ff" ++ rest), TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {TC.TraceParent.read(limits, "ff" ++ rest) == Fail{TC.InvalidTraceParent{TC.ForbiddenVersion{}}} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_ff(limits, rest, plain_rest, fits):
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, "ff" ++ rest),
    TC.Read.trimmed(TC.Text.trim_ows("ff" ++ rest)), read_fits(limits, "ff" ++ rest, fits)) :
    {_ == Fail{TC.InvalidTraceParent{TC.ForbiddenVersion{}}} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, TC.Text.trim_ows("ff" ++ rest), Laws.trimmed("ff" ++ rest), trim_law("ff" ++ rest)) :
    {TC.Read.trimmed(_) == Fail{TC.InvalidTraceParent{TC.ForbiddenVersion{}}} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, Laws.trimmed("ff" ++ rest), "ff" ++ rest, trimmed_plain("ff" ++ rest, plain_rest)) :
    {TC.Read.trimmed(_) == Fail{TC.InvalidTraceParent{TC.ForbiddenVersion{}}} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Bool, TC.Text.has_comma("ff" ++ rest), False{}, plain_comma("ff" ++ rest, plain_rest)) :
    {TC.Read.single(_, "ff" ++ rest) == Fail{TC.InvalidTraceParent{TC.ForbiddenVersion{}}} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {==}

# Law inverse, for a proof inside this module: a text the strict codec
# accepts is the text of the value read.
law inverse_of:
  for +text: String
  for context: TC.TraceParentV00
  for accepted: {TC.TraceParentV00.parse(text) == Done{context} : Result<&2, &2, TC.Error, TC.TraceParentV00>}
  {TC.TraceParentV00.format(context) == text : String}

def inverse_of(text, context, accepted):
  %accepted : InverseProof.ParseView(text, _)
  InverseProof.parse_view(text)

# The strict codec refuses a v00 text followed by more characters: a value it
# read would format to that text (inverse_of), but a value formats to 55
# characters and the text has more (NatsProof.add_succ_ne).
law exact_view:
  for +known: TC.TraceParentV00
  for +head: Char
  for +rest: String
  for parsed: Result<&2, &2, TC.Error, TC.TraceParentV00>
  for evidence: {TC.TraceParentV00.parse(TC.TraceParentV00.format(known) ++ SCon{head, rest}) == parsed :
    Result<&2, &2, TC.Error, TC.TraceParentV00>}
  {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00, TC.Read.invalid(parsed)) == False{} : Bool}

def exact_view(known, head, rest, parsed, evidence):
  match parsed:
    case Fail{error}:
      {==}
    case Done{+context}:
      Empty.absurd({Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
        TC.Read.invalid(Done{context})) == False{} : Bool},
        NatsProof.add_succ_ne(55n, String.length(rest),
          Equal.trans(Nat, 55n, String.length(TC.TraceParentV00.format(context)), Nat.add(55n, 1n+String.length(rest)),
            Equal.sym(Nat, String.length(TC.TraceParentV00.format(context)), 55n, ContextProof.formatted_length(context)),
            Equal.trans(Nat, String.length(TC.TraceParentV00.format(context)),
              String.length(TC.TraceParentV00.format(known) ++ SCon{head, rest}), Nat.add(55n, 1n+String.length(rest)),
              Equal.cong(String, Nat, text => String.length(text), TC.TraceParentV00.format(context),
                TC.TraceParentV00.format(known) ++ SCon{head, rest},
                inverse_of(TC.TraceParentV00.format(known) ++ SCon{head, rest}, context, evidence)),
              StringsProof.joined_length(TC.TraceParentV00.format(known), SCon{head, rest}, 55n, 1n+String.length(rest),
                ContextProof.formatted_length(known), {==})))))

# A v00 text followed by more characters is refused once its version 00
# sends it to the strict codec.
law exact_known:
  for +known: TC.TraceParentV00
  for +head: Char
  for +rest: String
  {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
    TC.Read.invalid(TC.Read.known(TC.TraceParentV00.format(known) ++ SCon{head, rest}))) == False{} :
    Bool}

def exact_known(known, head, rest):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      exact_view(TC.TraceParentV00{trace_id, parent_id, flags}, head, rest,
        TC.TraceParentV00.parse(TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id, flags}) ++
          SCon{head, rest}), {==})

# A v00 text followed by plain characters is plain.
law exact_plain:
  for known: TC.TraceParentV00
  for +more: String
  {Laws.plain(TC.TraceParentV00.format(known) ++ more) == Laws.plain(more) : Bool}

def exact_plain(known, more):
  match known:
    case TC.TraceParentV00{+trace_id, +parent_id, +flags}:
      format_plain(TC.TraceParentV00{trace_id, parent_id, flags}, more)

# Law read_v00_exact: the text is plain, so it reaches the version check,
# which sends it to the strict codec, and exact_known concludes.
law read_v00_exact:
  for +limits: TC.Limits
  for +known: TC.TraceParentV00
  for +more: String
  for nonempty: {String.is_empty(more) == False{} : Bool}
  for +plain_more: {Laws.plain(more) == True{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(TC.TraceParentV00.format(known) ++ more),
    TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
    TC.TraceParent.read(limits, TC.TraceParentV00.format(known) ++ more)) == False{} : Bool}

def read_v00_exact(limits, known, more, nonempty, plain_more, fits):
  match more:
    case SNil{}:
      Empty.absurd({Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
        TC.TraceParent.read(limits, TC.TraceParentV00.format(known) ++ SNil{})) == False{} : Bool},
        BoolsProof.true_ne_false(nonempty))
    case SCon{+head, +rest}:
      %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>,
        TC.TraceParent.read(limits, TC.TraceParentV00.format(known) ++ SCon{head, rest}),
        TC.Read.trimmed(TC.Text.trim_ows(TC.TraceParentV00.format(known) ++ SCon{head, rest})),
        read_fits(limits, TC.TraceParentV00.format(known) ++ SCon{head, rest}, fits)) :
        {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00, _) == False{} : Bool}
      %Equal.sym(String, TC.Text.trim_ows(TC.TraceParentV00.format(known) ++ SCon{head, rest}),
        Laws.trimmed(TC.TraceParentV00.format(known) ++ SCon{head, rest}),
        trim_law(TC.TraceParentV00.format(known) ++ SCon{head, rest})) :
        {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00, TC.Read.trimmed(_)) == False{} : Bool}
      %Equal.sym(String, Laws.trimmed(TC.TraceParentV00.format(known) ++ SCon{head, rest}),
        TC.TraceParentV00.format(known) ++ SCon{head, rest},
        trimmed_plain(TC.TraceParentV00.format(known) ++ SCon{head, rest},
          Equal.trans(Bool, Laws.plain(TC.TraceParentV00.format(known) ++ SCon{head, rest}), Laws.plain(SCon{head, rest}),
            True{}, exact_plain(known, SCon{head, rest}), plain_more))) :
        {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00, TC.Read.trimmed(_)) == False{} : Bool}
      %Equal.sym(Bool, TC.Text.has_comma(TC.TraceParentV00.format(known) ++ SCon{head, rest}), False{},
        plain_comma(TC.TraceParentV00.format(known) ++ SCon{head, rest},
          Equal.trans(Bool, Laws.plain(TC.TraceParentV00.format(known) ++ SCon{head, rest}), Laws.plain(SCon{head, rest}),
            True{}, exact_plain(known, SCon{head, rest}), plain_more))) :
        {Result.is_done(&2, &2, TC.TraceParentError, TC.TraceParentV00,
          TC.Read.single(_, TC.TraceParentV00.format(known) ++ SCon{head, rest})) == False{} : Bool}
      exact_known(known, head, rest)

# A comma is not whitespace: when `char` is a space or a tab, comparing it
# with a comma computes to False.
law ows_not_comma_step:
  for +char: Char
  for space: Bool
  for space_is: {Char.is_eq(char, ' ') == space : Bool}
  for ows: {Bool.or(space, Char.is_eq(char, '\t')) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def ows_not_comma_step(char, space, space_is, ows):
  match space:
    case True{}:
      %Equal.sym(Char, char, ' ', CharsProof.char_sound(char, ' ', space_is)) : {Char.is_eq(_, ',') == False{} : Bool}
      {==}
    case False{}:
      %Equal.sym(Char, char, '\t', CharsProof.char_sound(char, '\t', ows)) : {Char.is_eq(_, ',') == False{} : Bool}
      {==}

# Optional whitespace is not a comma.
law ows_not_comma:
  for +char: Char
  for ows: {Bool.or(Char.is_eq(char, ' '), Char.is_eq(char, '\t')) == True{} : Bool}
  {Char.is_eq(char, ',') == False{} : Bool}

def ows_not_comma(char, ows):
  ows_not_comma_step(char, Char.is_eq(char, ' '), {==}, ows)

# A text of whitespace only has no comma. Induction on the text.
law ows_lacks:
  for +text: String
  for +all: {Laws.all_ows(text) == True{} : Bool}
  {Laws.lacks(',', text) == True{} : Bool}

def ows_lacks(text, all):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      %Equal.sym(Bool, Char.is_eq(head, ','), False{}, ows_not_comma(head,
        BoolsProof.and_left(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(rest), all))) :
        {Bool.and(Bool.not(_), Laws.lacks(',', rest)) == True{} : Bool}
      ows_lacks(rest, BoolsProof.and_right(Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), Laws.all_ows(rest), all))

# The step of comma_start for a first character `head`.
law comma_start_step:
  for +head: Char
  for +rest: String
  for ows: Bool
  for evidence: {Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')) == ows : Bool}
  for later: {Laws.lacks(',', Laws.ows_start(rest)) == Laws.lacks(',', rest) : Bool}
  {Laws.lacks(',', Bool.pick(String, ows, Laws.ows_start(rest), SCon{head, rest})) == Laws.lacks(',', SCon{head, rest}) :
    Bool}

def comma_start_step(head, rest, ows, evidence, later):
  match ows:
    case True{}:
      %Equal.sym(Bool, Char.is_eq(head, ','), False{}, ows_not_comma(head, evidence)) :
        {Laws.lacks(',', Laws.ows_start(rest)) == Bool.and(Bool.not(_), Laws.lacks(',', rest)) : Bool}
      later
    case False{}:
      {==}

# Removing the whitespace at the start keeps every comma. Induction on the
# text.
law comma_start:
  for +text: String
  {Laws.lacks(',', Laws.ows_start(text)) == Laws.lacks(',', text) : Bool}

def comma_start(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      comma_start_step(head, rest, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), {==}, comma_start(rest))

# The step of comma_end for a first character `head`.
law comma_end_step:
  for +head: Char
  for +rest: String
  for all: Bool
  for evidence: {Laws.all_ows(SCon{head, rest}) == all : Bool}
  for later: {Laws.lacks(',', Laws.ows_end(rest)) == Laws.lacks(',', rest) : Bool}
  {Laws.lacks(',', Bool.pick(String, all, SNil{}, SCon{head, Laws.ows_end(rest)})) ==
    Laws.lacks(',', SCon{head, rest}) : Bool}

def comma_end_step(head, rest, all, evidence, later):
  match all:
    case True{}:
      Equal.sym(Bool, Laws.lacks(',', SCon{head, rest}), True{}, ows_lacks(SCon{head, rest}, evidence))
    case False{}:
      Equal.cong(Bool, Bool, found => Bool.and(Bool.not(Char.is_eq(head, ',')), found),
        Laws.lacks(',', Laws.ows_end(rest)), Laws.lacks(',', rest), later)

# Removing the whitespace at the end keeps every comma. Induction on the
# text.
law comma_end:
  for +text: String
  {Laws.lacks(',', Laws.ows_end(text)) == Laws.lacks(',', text) : Bool}

def comma_end(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      comma_end_step(head, rest, Laws.all_ows(SCon{head, rest}), {==}, comma_end(rest))

# A value with a comma keeps it once trimmed, so the package's comma search
# finds it.
law trimmed_comma:
  for +value: String
  for joined: {Laws.lacks(',', value) == False{} : Bool}
  {TC.Text.has_comma(Laws.trimmed(value)) == True{} : Bool}

def trimmed_comma(value, joined):
  Equal.trans(Bool, TC.Text.has_comma(Laws.trimmed(value)), Bool.not(Laws.lacks(',', Laws.trimmed(value))), True{},
    comma_go(Laws.trimmed(value), False{}),
    Equal.cong(Bool, Bool, found => Bool.not(found), Laws.lacks(',', Laws.trimmed(value)), False{},
      Equal.trans(Bool, Laws.lacks(',', Laws.trimmed(value)), Laws.lacks(',', Laws.ows_start(value)), False{},
        comma_end(Laws.ows_start(value)),
        Equal.trans(Bool, Laws.lacks(',', Laws.ows_start(value)), Laws.lacks(',', value), False{},
          comma_start(value), joined))))

# Law read_comma: the value fits, its comma survives trimming, and the
# package refuses it as repeated fields.
law read_comma:
  for +limits: TC.Limits
  for +value: String
  for joined: {Laws.lacks(',', value) == False{} : Bool}
  for fits: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == True{} : Bool}
  {TC.TraceParent.read(limits, value) == Fail{TC.RepeatedTraceParent{}} :
    Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}

def read_comma(limits, value, joined, fits):
  %Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, value),
    TC.Read.trimmed(TC.Text.trim_ows(value)), read_fits(limits, value, fits)) :
    {_ == Fail{TC.RepeatedTraceParent{}} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(String, TC.Text.trim_ows(value), Laws.trimmed(value), trim_law(value)) :
    {TC.Read.trimmed(_) == Fail{TC.RepeatedTraceParent{}} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  %Equal.sym(Bool, TC.Text.has_comma(Laws.trimmed(value)), True{}, trimmed_comma(value, joined)) :
    {TC.Read.single(_, Laws.trimmed(value)) == Fail{TC.RepeatedTraceParent{}} :
      Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {==}

# The tracestate plays no part in the traceparent
# ===============================================

# An accepted message reports its traceparent accepted, whatever its
# tracestate fields parse to.
law parsed_parent:
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for remote: TC.RemoteContext
  for text: String
  for fields: List<&2, String>
  {TC.Extraction.parent(TC.Extract.parsed(parsed, remote, text, fields)) == TC.TraceParentAccepted{} :
    TC.TraceParentOutcome}

def parsed_parent(parsed, remote, text, fields):
  match parsed:
    case Fail{error}:
      {==}
    case Done{state}:
      {==}

# An accepted message gives the sender's operation, whatever its tracestate
# fields parse to.
law parsed_sender:
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for +remote: TC.RemoteContext
  for text: String
  for fields: List<&2, String>
  {Laws.sender(TC.Extract.parsed(parsed, remote, text, fields)) == Some{remote} : Maybe<&2, TC.RemoteContext>}

def parsed_sender(parsed, remote, text, fields):
  match parsed:
    case Fail{error}:
      {==}
    case Done{state}:
      {==}

# An accepted message reports its traceparent accepted, with or without
# tracestate fields.
law state_parent:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for remote: TC.RemoteContext
  for text: String
  {TC.Extraction.parent(TC.Extract.state(limits, fields, remote, text)) == TC.TraceParentAccepted{} :
    TC.TraceParentOutcome}

def state_parent(limits, fields, remote, text):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      parsed_parent(TC.TraceState.parse_fields(limits, Con{field, rest}), remote, text, Con{field, rest})

# An accepted message gives the sender's operation, with or without
# tracestate fields.
law state_sender:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for +remote: TC.RemoteContext
  for text: String
  {Laws.sender(TC.Extract.state(limits, fields, remote, text)) == Some{remote} : Maybe<&2, TC.RemoteContext>}

def state_sender(limits, fields, remote, text):
  match fields:
    case Nil{}:
      {==}
    case Con{field, rest}:
      parsed_sender(TC.TraceState.parse_fields(limits, Con{field, rest}), remote, text, Con{field, rest})

# Two messages whose one traceparent value was read the same way report the
# same outcome and the same sender's operation, whatever their tracestate
# fields.
law read_independent:
  for read: Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>
  for +value: String
  for +limits: TC.Limits
  for +first: List<&2, String>
  for +second: List<&2, String>
  for +base: Maybe<&2, TC.BaseContext>
  {TC.Extraction.parent(TC.Extract.read(read, value, limits, first, base)) ==
    TC.Extraction.parent(TC.Extract.read(read, value, limits, second, base)) : TC.TraceParentOutcome} &
  {Laws.sender(TC.Extract.read(read, value, limits, first, base)) ==
    Laws.sender(TC.Extract.read(read, value, limits, second, base)) : Maybe<&2, TC.RemoteContext>}

def read_independent(read, value, limits, first, second, base):
  match read:
    case Fail{error}:
      ({==}, {==})
    case Done{+known}:
      (Equal.trans(TC.TraceParentOutcome,
        TC.Extraction.parent(TC.Extract.state(limits, first, TC.RemoteContext.from_traceparent(known),
          TC.Text.trim_ows(value))), TC.TraceParentAccepted{},
        TC.Extraction.parent(TC.Extract.state(limits, second, TC.RemoteContext.from_traceparent(known),
          TC.Text.trim_ows(value))),
        state_parent(limits, first, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value)),
        Equal.sym(TC.TraceParentOutcome, TC.Extraction.parent(TC.Extract.state(limits, second,
          TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value))), TC.TraceParentAccepted{},
          state_parent(limits, second, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value)))),
       Equal.trans(Maybe<&2, TC.RemoteContext>,
        Laws.sender(TC.Extract.state(limits, first, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value))),
        Some{TC.RemoteContext.from_traceparent(known)},
        Laws.sender(TC.Extract.state(limits, second, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value))),
        state_sender(limits, first, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value)),
        Equal.sym(Maybe<&2, TC.RemoteContext>, Laws.sender(TC.Extract.state(limits, second,
          TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value))), Some{TC.RemoteContext.from_traceparent(known)},
          state_sender(limits, second, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value)))))

# Two messages with the same traceparent values report the same outcome and
# the same sender's operation, whatever their tracestate fields: by cases on
# the values, then on how the only value was read.
law parents_independent:
  for +limits: TC.Limits
  for +parents: List<&2, String>
  for +first: List<&2, String>
  for +second: List<&2, String>
  for +base: Maybe<&2, TC.BaseContext>
  {TC.Extraction.parent(TC.Extract.parents(limits, parents, first, base)) ==
    TC.Extraction.parent(TC.Extract.parents(limits, parents, second, base)) : TC.TraceParentOutcome} &
  {Laws.sender(TC.Extract.parents(limits, parents, first, base)) ==
    Laws.sender(TC.Extract.parents(limits, parents, second, base)) : Maybe<&2, TC.RemoteContext>}

def parents_independent(limits, parents, first, second, base):
  match parents:
    case Nil{}:
      ({==}, {==})
    case Con{+value, Nil{}}:
      read_independent(TC.TraceParent.read(limits, value), value, limits, first, second, base)
    case Con{value, Con{next, more}}:
      ({==}, {==})

# Law state_independent: both extractions are Extract.parents of the same
# traceparent values (extract_named and `same`).
law state_independent:
  for +limits: TC.Limits
  for +first: List<&2, TC.Header>
  for +second: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for same: {Laws.named("traceparent", first) == Laws.named("traceparent", second) : List<&2, String>}
  {TC.Extraction.parent(TC.Context.extract(limits, first, base)) ==
    TC.Extraction.parent(TC.Context.extract(limits, second, base)) : TC.TraceParentOutcome} &
  {Laws.sender(TC.Context.extract(limits, first, base)) == Laws.sender(TC.Context.extract(limits, second, base)) :
    Maybe<&2, TC.RemoteContext>}

def state_independent(limits, first, second, base, same):
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, first, base), TC.Extract.parents(limits,
    Laws.named("traceparent", first), Laws.named("tracestate", first), base), extract_named(limits, first, base)) :
    {TC.Extraction.parent(_) == TC.Extraction.parent(TC.Context.extract(limits, second, base)) : TC.TraceParentOutcome} &
    {Laws.sender(_) == Laws.sender(TC.Context.extract(limits, second, base)) : Maybe<&2, TC.RemoteContext>}
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, second, base), TC.Extract.parents(limits,
    Laws.named("traceparent", second), Laws.named("tracestate", second), base), extract_named(limits, second, base)) :
    {TC.Extraction.parent(TC.Extract.parents(limits, Laws.named("traceparent", first), Laws.named("tracestate", first),
      base)) == TC.Extraction.parent(_) : TC.TraceParentOutcome} &
    {Laws.sender(TC.Extract.parents(limits, Laws.named("traceparent", first), Laws.named("tracestate", first), base)) ==
      Laws.sender(_) : Maybe<&2, TC.RemoteContext>}
  %same :
    {TC.Extraction.parent(TC.Extract.parents(limits, Laws.named("traceparent", first), Laws.named("tracestate", first),
      base)) == TC.Extraction.parent(TC.Extract.parents(limits, _, Laws.named("tracestate", second), base)) :
      TC.TraceParentOutcome} &
    {Laws.sender(TC.Extract.parents(limits, Laws.named("traceparent", first), Laws.named("tracestate", first), base)) ==
      Laws.sender(TC.Extract.parents(limits, _, Laws.named("tracestate", second), base)) : Maybe<&2, TC.RemoteContext>}
  parents_independent(limits, Laws.named("traceparent", first), Laws.named("tracestate", first),
    Laws.named("tracestate", second), base)

# The received pair is bounded
# ============================

# The view of a kept pair: Unit when there is none, and the two bounds of law
# received_bounds when there is one.
def PairView(+limits: TC.Limits, received: Maybe<&2, TC.ReceivedPair>) -> Type:
  match received:
    case None{}:
      Unit
    case Some{pair}:
      {Nat.is_le(TC.Utf8.length(TC.ReceivedPair.traceparent(pair)), TC.Limits.traceparent_input(limits)) == True{} :
        Bool} &
      {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")), TC.Limits.tracestate_input(limits)) ==
        True{} : Bool}

# The view of an extraction's own context: Unit when there is none, and the
# view of the pair it kept when there is one.
def IncomingView(+limits: TC.Limits, incoming: Maybe<&2, TC.IncomingContext>) -> Type:
  match incoming:
    case None{}:
      Unit
    case Some{context}:
      PairView(limits, TC.IncomingContext.received(context))

# The step of start_shorter for a first character `head`, with `ows`
# standing for whether it is whitespace and `later` the lemma for the rest: a
# removed character leaves the rest, which is shorter by its octets
# (NatsProof.le_add_left), and a kept one leaves the text.
law start_shorter_step:
  for +head: Char
  for +rest: String
  for ows: Bool
  for later: {Nat.is_le(TC.Utf8.length(Laws.ows_start(rest)), TC.Utf8.length(rest)) == True{} : Bool}
  {Nat.is_le(TC.Utf8.length(Bool.pick(String, ows, Laws.ows_start(rest), SCon{head, rest})),
    TC.Utf8.length(SCon{head, rest})) == True{} : Bool}

def start_shorter_step(head, rest, ows, later):
  match ows:
    case True{}:
      NatsProof.le_trans(TC.Utf8.length(Laws.ows_start(rest)), TC.Utf8.length(rest),
        Nat.add(TC.Utf8.width(head), TC.Utf8.length(rest)), later,
        NatsProof.le_add_left(TC.Utf8.width(head), TC.Utf8.length(rest)))
    case False{}:
      NatsProof.le_refl(TC.Utf8.length(SCon{head, rest}))

# Removing the whitespace at the start never lengthens a text. Induction on
# the text, with start_shorter_step.
law start_shorter:
  for +text: String
  {Nat.is_le(TC.Utf8.length(Laws.ows_start(text)), TC.Utf8.length(text)) == True{} : Bool}

def start_shorter(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      start_shorter_step(head, rest, Bool.or(Char.is_eq(head, ' '), Char.is_eq(head, '\t')), start_shorter(rest))

# The step of end_shorter for a first character `head`, with `all` standing
# for whether the text is all whitespace and `later` the lemma for the rest:
# nothing is left of an all-whitespace text, and a kept character adds the
# same octets to both sides (NatsProof.add_le_left).
law end_shorter_step:
  for +head: Char
  for +rest: String
  for all: Bool
  for later: {Nat.is_le(TC.Utf8.length(Laws.ows_end(rest)), TC.Utf8.length(rest)) == True{} : Bool}
  {Nat.is_le(TC.Utf8.length(Bool.pick(String, all, SNil{}, SCon{head, Laws.ows_end(rest)})),
    TC.Utf8.length(SCon{head, rest})) == True{} : Bool}

def end_shorter_step(head, rest, all, later):
  match all:
    case True{}:
      NatsProof.zero_le(TC.Utf8.length(SCon{head, rest}))
    case False{}:
      NatsProof.add_le_left(TC.Utf8.width(head), TC.Utf8.length(Laws.ows_end(rest)), TC.Utf8.length(rest), later)

# Removing the whitespace at the end never lengthens a text. Induction on the
# text, with end_shorter_step.
law end_shorter:
  for +text: String
  {Nat.is_le(TC.Utf8.length(Laws.ows_end(text)), TC.Utf8.length(text)) == True{} : Bool}

def end_shorter(text):
  match text:
    case SNil{}:
      {==}
    case SCon{+head, +rest}:
      end_shorter_step(head, rest, Laws.all_ows(SCon{head, rest}), end_shorter(rest))

# The value kept for forwarding is no longer than the value received.
law trim_shorter:
  for +value: String
  {Nat.is_le(TC.Utf8.length(TC.Text.trim_ows(value)), TC.Utf8.length(value)) == True{} : Bool}

def trim_shorter(value):
  %Equal.sym(String, TC.Text.trim_ows(value), Laws.trimmed(value), trim_law(value)) :
    {Nat.is_le(TC.Utf8.length(_), TC.Utf8.length(value)) == True{} : Bool}
  NatsProof.le_trans(TC.Utf8.length(Laws.ows_end(Laws.ows_start(value))), TC.Utf8.length(Laws.ows_start(value)),
    TC.Utf8.length(value), end_shorter(Laws.ows_start(value)), start_shorter(value))

# A Done result is not a Fail one.
law done_ne_fail:
  for -E: Data
  for -A: Data
  for -value: A
  for -error: E
  for clash: {Done{value} == Fail{error} : Result<&2, &2, E, A>}
  Empty

def done_ne_fail(E, A, value, error, clash):
  BoolsProof.true_ne_false(Equal.cong(Result<&2, &2, E, A>, Bool, result => Result.is_done(&2, &2, E, A, result),
    Done{value}, Fail{error}, clash))

# The step of read_fits_done, with `fits` standing for the budget check.
law read_fits_step:
  for +limits: TC.Limits
  for +value: String
  for -known: TC.TraceParentV00
  for fits: Bool
  for fits_is: {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == fits : Bool}
  for read: {TC.TraceParent.read(limits, value) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == True{} : Bool}

def read_fits_step(limits, value, known, fits, fits_is, read):
  match fits:
    case True{}:
      fits_is
    case False{}:
      Empty.absurd({Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == True{} : Bool},
        done_ne_fail(TC.TraceParentError, TC.TraceParentV00, known, TC.TraceParentTooLarge{},
          Equal.trans(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, Done{known}, TC.TraceParent.read(limits, value),
            Fail{TC.TraceParentTooLarge{}},
            Equal.sym(Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>, TC.TraceParent.read(limits, value),
              Done{known}, read),
            read_over_budget(limits, value, fits_is))))

# A value that TraceParent.read accepts fits the traceparent input budget,
# since a larger one is refused (read_over_budget).
law read_fits_done:
  for +limits: TC.Limits
  for +value: String
  for -known: TC.TraceParentV00
  for read: {TC.TraceParent.read(limits, value) == Done{known} : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  {Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)) == True{} : Bool}

def read_fits_done(limits, value, known, read):
  read_fits_step(limits, value, known, Nat.is_le(TC.Utf8.length(value), TC.Limits.traceparent_input(limits)), {==}, read)

# The step of fields_fit, with `fits` standing for the budget check.
law fields_fit_step:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for -state: TC.TraceState
  for fits: Bool
  for fits_is: {Nat.is_le(TC.Utf8.length(String.join(fields, ",")), TC.Limits.tracestate_input(limits)) == fits : Bool}
  for parsed: {TC.TraceState.parse_fields(limits, fields) == Done{state} : Result<&2, &2, TC.StateError, TC.TraceState>}
  {Nat.is_le(TC.Utf8.length(String.join(fields, ",")), TC.Limits.tracestate_input(limits)) == True{} : Bool}

def fields_fit_step(limits, fields, state, fits, fits_is, parsed):
  match fits:
    case True{}:
      fits_is
    case False{}:
      Empty.absurd({Nat.is_le(TC.Utf8.length(String.join(fields, ",")), TC.Limits.tracestate_input(limits)) == True{} :
        Bool},
        done_ne_fail(TC.StateError, TC.TraceState, state, TC.StateTooLarge{},
          Equal.trans(Result<&2, &2, TC.StateError, TC.TraceState>, Done{state}, TC.TraceState.parse_fields(limits, fields),
            Fail{TC.StateTooLarge{}},
            Equal.sym(Result<&2, &2, TC.StateError, TC.TraceState>, TC.TraceState.parse_fields(limits, fields),
              Done{state}, parsed),
            Equal.trans(Result<&2, &2, TC.StateError, TC.TraceState>, TC.TraceState.parse_fields(limits, fields),
              TC.TraceState.parse(limits, String.join(fields, ",")), Fail{TC.StateTooLarge{}},
              StateProof.fields_join(limits, fields),
              StateProof.over_budget(limits, String.join(fields, ","), fits_is)))))

# Tracestate fields that parse fit the tracestate input budget, joined by
# commas: a larger combination is refused (StateProof.fields_join and
# over_budget).
law fields_fit:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for -state: TC.TraceState
  for parsed: {TC.TraceState.parse_fields(limits, fields) == Done{state} : Result<&2, &2, TC.StateError, TC.TraceState>}
  {Nat.is_le(TC.Utf8.length(String.join(fields, ",")), TC.Limits.tracestate_input(limits)) == True{} : Bool}

def fields_fit(limits, fields, state, parsed):
  fields_fit_step(limits, fields, state, Nat.is_le(TC.Utf8.length(String.join(fields, ",")),
    TC.Limits.tracestate_input(limits)), {==}, parsed)

# The view for an accepted message with parsed tracestate fields: a refused
# state keeps no pair, and an accepted one keeps the fields, which fit.
law parsed_view:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for remote: TC.RemoteContext
  for text: String
  for text_fits: {Nat.is_le(TC.Utf8.length(text), TC.Limits.traceparent_input(limits)) == True{} : Bool}
  for parsed: Result<&2, &2, TC.StateError, TC.TraceState>
  for evidence: {TC.TraceState.parse_fields(limits, fields) == parsed : Result<&2, &2, TC.StateError, TC.TraceState>}
  IncomingView(limits, TC.Extraction.incoming(TC.Extract.parsed(parsed, remote, text, fields)))

def parsed_view(limits, fields, remote, text, text_fits, parsed, evidence):
  match parsed:
    case Fail{error}:
      Unit{}
    case Done{state}:
      (text_fits, fields_fit(limits, fields, state, evidence))

# The view for an accepted message, given that the value it keeps fits.
law state_view:
  for +limits: TC.Limits
  for +fields: List<&2, String>
  for remote: TC.RemoteContext
  for text: String
  for text_fits: {Nat.is_le(TC.Utf8.length(text), TC.Limits.traceparent_input(limits)) == True{} : Bool}
  IncomingView(limits, TC.Extraction.incoming(TC.Extract.state(limits, fields, remote, text)))

def state_view(limits, fields, remote, text, text_fits):
  match fields:
    case Nil{}:
      (text_fits, NatsProof.zero_le(TC.Limits.tracestate_input(limits)))
    case Con{field, rest}:
      parsed_view(limits, Con{field, rest}, remote, text, text_fits,
        TC.TraceState.parse_fields(limits, Con{field, rest}), {==})

# The view for a message with one traceparent value, given how it was read.
law read_view:
  for +limits: TC.Limits
  for +value: String
  for +fields: List<&2, String>
  for base: Maybe<&2, TC.BaseContext>
  for read: Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>
  for evidence: {TC.TraceParent.read(limits, value) == read : Result<&2, &2, TC.TraceParentError, TC.TraceParentV00>}
  IncomingView(limits, TC.Extraction.incoming(TC.Extract.read(read, value, limits, fields, base)))

def read_view(limits, value, fields, base, read, evidence):
  match read:
    case Fail{error}:
      Unit{}
    case Done{+known}:
      state_view(limits, fields, TC.RemoteContext.from_traceparent(known), TC.Text.trim_ows(value),
        NatsProof.le_trans(TC.Utf8.length(TC.Text.trim_ows(value)), TC.Utf8.length(value),
          TC.Limits.traceparent_input(limits), trim_shorter(value), read_fits_done(limits, value, known, evidence)))

# The view for every extraction of selected field values.
law incoming_view:
  for +limits: TC.Limits
  for +parents: List<&2, String>
  for +fields: List<&2, String>
  for base: Maybe<&2, TC.BaseContext>
  IncomingView(limits, TC.Extraction.incoming(TC.Extract.parents(limits, parents, fields, base)))

def incoming_view(limits, parents, fields, base):
  match parents:
    case Nil{}:
      Unit{}
    case Con{+value, Nil{}}:
      read_view(limits, value, fields, base, TC.TraceParent.read(limits, value), {==})
    case Con{value, Con{next, more}}:
      Unit{}

# Law received_bounds: `kept` and `extracted` turn the bounds into the view of
# the extraction's own context, which incoming_view proves.
law received_bounds:
  for +limits: TC.Limits
  for +carrier: List<&2, TC.Header>
  for +base: Maybe<&2, TC.BaseContext>
  for +incoming: TC.IncomingContext
  for +pair: TC.ReceivedPair
  for extracted: {TC.Extraction.incoming(TC.Context.extract(limits, carrier, base)) == Some{incoming} :
    Maybe<&2, TC.IncomingContext>}
  for kept: {TC.IncomingContext.received(incoming) == Some{pair} : Maybe<&2, TC.ReceivedPair>}
  {Nat.is_le(TC.Utf8.length(TC.ReceivedPair.traceparent(pair)), TC.Limits.traceparent_input(limits)) == True{} : Bool} &
  {Nat.is_le(TC.Utf8.length(String.join(TC.ReceivedPair.tracestate(pair), ",")), TC.Limits.tracestate_input(limits)) ==
    True{} : Bool}

def received_bounds(limits, carrier, base, incoming, pair, extracted, kept):
  %kept : PairView(limits, _)
  %extracted : IncomingView(limits, _)
  %Equal.sym(TC.Extraction, TC.Context.extract(limits, carrier, base), TC.Extract.parents(limits,
    Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base), extract_named(limits, carrier, base)) :
    IncomingView(limits, TC.Extraction.incoming(_))
  incoming_view(limits, Laws.named("traceparent", carrier), Laws.named("tracestate", carrier), base)
