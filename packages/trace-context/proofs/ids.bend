import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./strings.bend as StringsProof
import ./parser.bend as ParserProof
import ./digits.bend as DigitsProof

# A supplied ID the parser accepts is exactly the text it read.
def IdView(n: Nat, text: String, result: Result<&2, &2, TC.Error, Digits.NonZero<n>>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{value}:
      {Digits.NonZero.to_string(n, value) == text : String}

# The Result continuations of Parse.id, named for the motives.
def id_result(n: Nat, field: TC.Field, result: Result<&2, &2, TC.Error, TC.Parsed<n>>) ->
  Result<&2, &2, TC.Error, Digits.NonZero<n>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<n>>:
    parsed : TC.Parsed<n> <- result
    TC.Parse.id.finish(n, parsed, field)

def id_end_result(n: Nat, digits: Digits.Digits(n), field: TC.Field,
  result: Result<&2, &2, TC.Error, Unit>) -> Result<&2, &2, TC.Error, Digits.NonZero<n>>:
  do Result<&2, &2, TC.Error, Digits.NonZero<n>>:
    end : Unit <- result
    TC.Parse.nonzero(n, digits, field)

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

law id_end_step:
  for +n: Nat
  for +digits: Digits.Digits(n)
  for -rest: String
  for +field: TC.Field
  for result: Result<&2, &2, TC.Error, Unit>
  for view: ParserProof.EndView(rest, result)
  IdView(n, Digits.Digits.to_string(n, digits) ++ rest, id_end_result(n, digits, field, result))

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

# Quantified over every String, including every rejected one.
law id_view:
  for +n: Nat
  for +text: String
  for +field: TC.Field
  IdView(n, text, TC.Parse.id(n, text, field))

def id_view(n, text, field):
  id_digits_step(n, text, field, TC.Parse.digits(n, text, 0n), ParserProof.digits_view(n, text, 0n))

# An accepted trace ID is exactly its text and makes no randomness assertion.
def TraceIdView(text: String, result: Result<&2, &2, TC.Error, TC.TraceId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.TraceId.to_string(id) == text : String} & {TC.TraceId.is_random(id) == False{} : Bool}

def trace_id_parse_result(result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceId>:
  do Result<&2, &2, TC.Error, TC.TraceId>:
    value : Digits.NonZero<32n> <- result
    return TC.TraceId{value, False{}}

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

law trace_id_view:
  for +text: String
  TraceIdView(text, TC.TraceId.parse(text))

def trace_id_view(text):
  trace_id_step(text, TC.Parse.id(32n, text, TC.TraceIdField{}), id_view(32n, text, TC.TraceIdField{}))

def SpanIdView(text: String, result: Result<&2, &2, TC.Error, TC.SpanId>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{id}:
      {TC.SpanId.to_string(id) == text : String}

def span_id_parse_result(result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>) ->
  Result<&2, &2, TC.Error, TC.SpanId>:
  do Result<&2, &2, TC.Error, TC.SpanId>:
    value : Digits.NonZero<16n> <- result
    return TC.SpanId{value}

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

law span_id_view:
  for +text: String
  SpanIdView(text, TC.SpanId.parse(text))

def span_id_view(text):
  span_id_step(text, TC.Parse.id(16n, text, TC.SpanIdField{}), id_view(16n, text, TC.SpanIdField{}))

# Every canonical ID text is accepted as the same identifier.
law id_roundtrip:
  for +n: Nat
  for value: Digits.NonZero<n>
  for +field: TC.Field
  {TC.Parse.id(n, Digits.NonZero.to_string(n, value), field) == Done{value} :
    Result<&2, &2, TC.Error, Digits.NonZero<n>>}

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
