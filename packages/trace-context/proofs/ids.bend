# Proofs: supplied trace and span IDs
# ===================================
#
# Proves four laws of LAWS.bend, section 2, about TraceId.parse and
# SpanId.parse; PROOF.bend calls these lemmas as IdsProof.*. trace_id_view
# and span_id_view prove the views behind laws trace_id_parse and
# span_id_parse: an accepted ID is exactly the text accepted, and a parsed
# trace ID makes no randomness assertion. trace_id_accepts and
# span_id_roundtrip prove the laws of the same names: the text of every ID is
# accepted again. The fifth law, assert_random, needs no lemma: PROOF.bend
# proves it by case analysis. trace_context.bend is imported as TC.
#
# Both parsers call Parse.id: n digits from offset 0 (Parse.digits), then the
# end of the text (Parse.end), then the nonzero check (Parse.nonzero). From
# text to ID, id_view chains the views of these readers from
# proofs/parser.bend, as proofs/inverse.bend does for the codec: id_view calls
# id_digits_step, which calls id_end_step, which calls id_nonzero_step. From
# ID to text, id_roundtrip reads the canonical text back with
# ParserProof.digits_roundtrip and gives back the value's own evidence, its
# proof that the digits are not all zero, with DigitsProof.new_valid. The
# trace and span lemmas then only wrap the digits in TraceId or SpanId. The
# `*_result` defs name the rest of a parser after one step, as a function of
# that step's result: a step law takes the result as a parameter, since
# `match` cannot inspect a computed value, and a rewrite motive (the P of
# `%e : P`) marks it with `_`.

import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./strings.bend as StringsProof
import ./parser.bend as ParserProof
import ./digits.bend as DigitsProof

# The view of Parse.id for `text`: Unit for a failure and, for a success, the
# equation saying that the text of the digits returned is `text`. A supplied
# ID the parser accepts is exactly the text it read.
def IdView(n: Nat, text: String, result: Result<&2, &2, TC.Error, Digits.NonZero<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.NonZero.to_string(n, value) == text : String}

# Parse.id as a function of the read of its n digits: Parse.id.finish on its
# success. id_digits_step and the motives of id_roundtrip are stated with it.
def id_result(n: Nat, field: TC.Field, result: Result<&2, &2, TC.Error, TC.Parsed<n>>) ->
  Result<&2, &2, TC.Error, Digits.NonZero<n>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<n>>:
    parsed : TC.Parsed<n> <- result
    TC.Parse.id.finish(n, parsed, field)

# The rest of Parse.id.finish, as a function of the end check's `result`: the
# nonzero check of the digits.
def id_end_result(n: Nat, digits: Digits.Digits(n), field: TC.Field,
  result: Result<&2, &2, TC.Error, Unit>) -> Result<&2, &2, TC.Error, Digits.NonZero<n>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<n>>:
    end : Unit <- result
    TC.Parse.nonzero(n, digits, field)

# When the nonzero check of `digits` satisfies NonZeroView, its result also
# satisfies IdView for the text of `digits`: once the result is known to be a
# success, the two views are the same equation. id_end_step uses it.
law id_nonzero_step:
  for -n: Nat
  for -digits: Digits.Digits(n)
  for result: Result<&2, &2, TC.Error, Digits.NonZero<n>>
  for view: ParserProof.NonZeroView(n, digits, result)
  IdView(n, Digits.Digits.to_string(n, digits), result)

def id_nonzero_step(n, digits, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      view

# When the end check of the text after the digits satisfies EndView (a
# success means that text is empty), the rest of Parse.id satisfies IdView
# for the text of the digits followed by that text. id_digits_step uses it.
law id_end_step:
  for +n: Nat
  for +digits: Digits.Digits(n)
  for -rest: String
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, Unit>
  for view: ParserProof.EndView(rest, result)
  IdView(n, Digits.Digits.to_string(n, digits) ++ rest, id_end_result(n, digits, field, result))

# After rest becomes "", StringsProof.append_nil removes ++ "" for any n.
def id_end_step(n, digits, rest, field, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{end}:
      %view : IdView(n, Digits.Digits.to_string(n, digits) ++ _, TC.Parse.nonzero(n, digits, field))
      %Equal.sym(String, Digits.Digits.to_string(n, digits) ++ "", Digits.Digits.to_string(n, digits),
        StringsProof.append_nil(Digits.Digits.to_string(n, digits))) :
        IdView(n, _, TC.Parse.nonzero(n, digits, field))
      id_nonzero_step(n, digits, TC.Parse.nonzero(n, digits, field),
        ParserProof.nonzero_view(n, digits, field))

# When the read of n digits from `text` satisfies DigitsView, the rest of
# Parse.id (id_result) satisfies IdView for `text`. id_view uses it.
law id_digits_step:
  for +n: Nat
  for -text: String
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, TC.Parsed<n>>
  for view: ParserProof.DigitsView(n, text, result)
  IdView(n, text, id_result(n, field, result))

def id_digits_step(n, text, field, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{+digits, +rest}}:
      %view : IdView(n, _, TC.Parse.id.finish(n, TC.Parsed{digits, rest}, field))
      id_end_step(n, digits, rest, field, TC.Parse.end(rest), ParserProof.end_view(rest))

# For every string, length and field, a successful Parse.id returns digits
# whose text is that string. Quantified over every String, including every
# rejected one. trace_id_view and span_id_view use it.
law id_view:
  for +n: Nat
  for +text: String
  for +field: TC.Field
  IdView(n, text, TC.Parse.id(n, text, field))

def id_view(n, text, field):
  id_digits_step(n, text, field, TC.Parse.digits(n, text, 0n), ParserProof.digits_view(n, text, 0n))

# The view of TraceId.parse for `text`: Unit for a failure and, for a success,
# the two facts of law trace_id_parse: an accepted trace ID is exactly its
# text and makes no randomness assertion. PROOF.bend's Laws.trace_id_parse
# rewrites its hypothesis into this view.
def TraceIdView(text: String, result: Result<&2, &2, TC.Error, TC.TraceId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.TraceId.to_string(id) == text : String} & {TC.TraceId.is_random(id) == False{} : Bool}

# TraceId.parse as a function of the result of Parse.id: a success becomes a
# TraceId whose randomness assertion is False{}. trace_id_step and the motive
# of trace_id_accepts are stated with it.
def trace_id_parse_result(result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceId>:
  do Result<&2, &2, TC.Error, TC.TraceId>:
    value : Digits.NonZero<32n> <- result
    return TC.TraceId{value, False{}}

# When the result of Parse.id satisfies IdView for `text`, the trace ID built
# from it satisfies TraceIdView: its text is given by the IdView equation, and
# its assertion is False{} by computation. trace_id_view uses it.
law trace_id_step:
  for -text: String
  for result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>
  for view: IdView(32n, text, result)
  TraceIdView(text, trace_id_parse_result(result))

def trace_id_step(text, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      (view, {==})

# For every string, a trace ID that TraceId.parse accepts is exactly that
# string and makes no randomness assertion. PROOF.bend's Laws.trace_id_parse
# proves law trace_id_parse with it.
law trace_id_view:
  for +text: String
  TraceIdView(text, TC.TraceId.parse(text))

def trace_id_view(text):
  trace_id_step(text, TC.Parse.id(32n, text, TC.TraceIdField{}), id_view(32n, text, TC.TraceIdField{}))

# The view of SpanId.parse for `text`: Unit for a failure and, for a success,
# the equation of law span_id_parse, saying that the span ID's text is
# `text`. PROOF.bend's Laws.span_id_parse rewrites its hypothesis into it.
def SpanIdView(text: String, result: Result<&2, &2, TC.Error, TC.SpanId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.SpanId.to_string(id) == text : String}

# SpanId.parse as a function of the result of Parse.id: a success becomes a
# SpanId. span_id_step and the motive of span_id_roundtrip are stated with it.
def span_id_parse_result(result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>) ->
  Result<&2, &2, TC.Error, TC.SpanId>:
  do Result<&2, &2, TC.Error, TC.SpanId>:
    value : Digits.NonZero<16n> <- result
    return TC.SpanId{value}

# When the result of Parse.id satisfies IdView for `text`, the span ID built
# from it satisfies SpanIdView: the two equations are the same. span_id_view
# uses it.
law span_id_step:
  for -text: String
  for result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>
  for view: IdView(16n, text, result)
  SpanIdView(text, span_id_parse_result(result))

def span_id_step(text, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{value}:
      view

# For every string, a span ID that SpanId.parse accepts is exactly that
# string. PROOF.bend's Laws.span_id_parse proves law span_id_parse with it.
law span_id_view:
  for +text: String
  SpanIdView(text, TC.SpanId.parse(text))

def span_id_view(text):
  span_id_step(text, TC.Parse.id(16n, text, TC.SpanIdField{}), id_view(16n, text, TC.SpanIdField{}))

# Every canonical ID text is accepted as the same identifier: parsing the
# text of any nonzero value of n digits gives back that value, evidence
# included, whatever field is named. trace_id_accepts and span_id_roundtrip
# use it.
law id_roundtrip:
  for +n: Nat
  for value: Digits.NonZero<n>
  for +field: TC.Field
  {TC.Parse.id(n, Digits.NonZero.to_string(n, value), field) == Done{value} :
    Result<&2, &2, TC.Error, Digits.NonZero<n>>}

# Adds ++ "" for digits_roundtrip; new_valid returns the value's own evidence.
def id_roundtrip(n, value, field):
  match value:
    case Digits.NonZero{+digits, +evidence}:
      %StringsProof.append_nil(Digits.Digits.to_string(n, digits)) :
        {id_result(n, field, TC.Parse.digits(n, _, 0n)) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<n>>}
      %Equal.sym(Result<&2, &2, TC.Error, TC.Parsed<n>>,
        TC.Parse.digits(n, Digits.Digits.to_string(n, digits) ++ "", 0n), Done{TC.Parsed{digits, ""}},
        ParserProof.digits_roundtrip(n, digits, "", 0n)) :
        {id_result(n, field, _) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<n>>}
      %Equal.sym(Maybe<&2, Digits.NonZero<n>>, Digits.NonZero.new(n, digits),
        Some{Digits.NonZero{digits, evidence}}, DigitsProof.new_valid(n, digits, evidence)) :
        {TC.Parse.nonzero_result(n, _, field) == Done{Digits.NonZero{digits, evidence}} :
          Result<&2, &2, TC.Error, Digits.NonZero<n>>}
      {==}

# The text of every trace ID is accepted again by TraceId.parse. Only
# acceptance is claimed: the parsed ID makes no randomness assertion, so it
# differs from `id` when `id` asserts one. PROOF.bend's Laws.trace_id_accepts
# calls it.
law trace_id_accepts:
  for id: TC.TraceId
  {Result.is_done(&2, &2, TC.Error, TC.TraceId, TC.TraceId.parse(TC.TraceId.to_string(id))) == True{} : Bool}

def trace_id_accepts(id):
  match id:
    case TC.TraceId{value, random}:
      %Equal.sym(Result<&2, &2, TC.Error, Digits.NonZero<32n>>,
        TC.Parse.id(32n, Digits.NonZero.to_string(32n, value), TC.TraceIdField{}), Done{value},
        id_roundtrip(32n, value, TC.TraceIdField{})) :
        {Result.is_done(&2, &2, TC.Error, TC.TraceId, trace_id_parse_result(_)) == True{} : Bool}
      {==}

# Parsing the text of any span ID gives back that span ID: a span ID carries
# nothing besides its digits. PROOF.bend's Laws.span_id_roundtrip calls it.
law span_id_roundtrip:
  for id: TC.SpanId
  {TC.SpanId.parse(TC.SpanId.to_string(id)) == Done{id} : Result<&2, &2, TC.Error, TC.SpanId>}

def span_id_roundtrip(id):
  match id:
    case TC.SpanId{value}:
      %Equal.sym(Result<&2, &2, TC.Error, Digits.NonZero<16n>>,
        TC.Parse.id(16n, Digits.NonZero.to_string(16n, value), TC.SpanIdField{}), Done{value},
        id_roundtrip(16n, value, TC.SpanIdField{})) :
        {span_id_parse_result(_) == Done{TC.SpanId{value}} : Result<&2, &2, TC.Error, TC.SpanId>}
      {==}
