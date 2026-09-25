import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./parser.bend as ParserProof
import ./context.bend as ContextProof

# Every accepted strict-v00 text is reproduced by formatting its parsed value.
# Each stage states which text a successful parse must have read. A stage
# either fails, which leaves nothing to prove, or supplies the equation that
# rewrites its input text into the text the next stage reads.
def ParseView(text: String, result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{context}:
      {TC.TraceParentV00.format(context) == text : String}

# The accepted text once the version, trace ID and parent ID have been read.
def trace_text(rest: String) -> String:
  "00-" ++ rest

def parent_text(trace_id: Digits.NonZero<32n>, rest: String) -> String:
  "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++ rest

def flags_text(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>, rest: String) -> String:
  "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++
    Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ rest

# The remaining Result continuations of the parser, named for the motives.
def end_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  flags: Digits.Digits(2n), result: Result<&2, &2, TC.Error, Unit>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    end : Unit <- result
    return TC.TraceParentV00{trace_id, parent_id, flags}

def parent_after_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  result: Result<&2, &2, TC.Error, String>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.flags_result(trace_id, parent_id, TC.Parse.digits(2n, after, 53n))

def parent_nonzero_result(trace_id: Digits.NonZero<32n>, rest: String,
  result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent_id : Digits.NonZero<16n> <- result
    parent_after_result(trace_id, parent_id, TC.Parse.separator(rest, 52n))

def trace_after_result(trace_id: Digits.NonZero<32n>, result: Result<&2, &2, TC.Error, String>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.parent_result(trace_id, TC.Parse.digits(16n, after, 36n))

def trace_nonzero_result(rest: String, result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace_id : Digits.NonZero<32n> <- result
    trace_after_result(trace_id, TC.Parse.separator(rest, 35n))

def start_after_result(result: Result<&2, &2, TC.Error, String>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.trace_result(TC.Parse.digits(32n, after, 3n))

def version_result(rest: String, result: Result<&2, &2, TC.Error, Unit>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    version_ok : Unit <- result
    start_after_result(TC.Parse.separator(rest, 2n))

def parse_result(result: Result<&2, &2, TC.Error, TC.Parsed<2n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    version : TC.Parsed<2n> <- result
    TC.Parse.start(version)

# Flags: the two digits are followed by the end of the text.
law end_step:
  for -trace_id: Digits.NonZero<32n>
  for -parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  for -rest: String
  for result: Result<&2, &2, TC.Error, Unit>
  for view: ParserProof.EndView(rest, result)
  ParseView(flags_text(trace_id, parent_id, Digits.Digits.to_string(2n, flags) ++ rest),
    end_result(trace_id, parent_id, flags, result))

def end_step(trace_id, parent_id, flags, rest, result, view):
  match flags:
    case Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}:
      match result:
        case Fail{error}:
          Unit{}
        case Done{end}:
          %view : {TC.TraceParentV00.format(TC.TraceParentV00{trace_id, parent_id,
            Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}}) ==
            flags_text(trace_id, parent_id,
              Digits.Digits.to_string(2n, Digits.DCon{high, Digits.DCon{low, Digits.DNil{}}}) ++ _) : String}
          {==}

law flags_step:
  for +trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for -after: String
  for result: Result<&2, &2, TC.Error, TC.Parsed<2n>>
  for view: ParserProof.DigitsView(2n, after, result)
  ParseView(flags_text(trace_id, parent_id, after), ContextProof.flags_result(trace_id, parent_id, result))

def flags_step(trace_id, parent_id, after, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{+flags, +rest}}:
      %view : ParseView(flags_text(trace_id, parent_id, _), TC.Parse.flags(trace_id, parent_id, TC.Parsed{flags, rest}))
      end_step(trace_id, parent_id, flags, rest, TC.Parse.end(rest), ParserProof.end_view(rest))

law flags_view:
  for +trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for +after: String
  ParseView(flags_text(trace_id, parent_id, after),
    ContextProof.flags_result(trace_id, parent_id, TC.Parse.digits(2n, after, 53n)))

def flags_view(trace_id, parent_id, after):
  flags_step(trace_id, parent_id, after, TC.Parse.digits(2n, after, 53n),
    ParserProof.digits_view(2n, after, 53n))

# Parent ID: sixteen nonzero digits, then the separator before the flags.
law parent_separator_step:
  for +trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for -rest: String
  for result: Result<&2, &2, TC.Error, String>
  for view: ParserProof.SeparatorView(rest, result)
  ParseView(parent_text(trace_id, Digits.NonZero.to_string(16n, parent_id) ++ rest),
    parent_after_result(trace_id, parent_id, result))

def parent_separator_step(trace_id, parent_id, rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{+after}:
      %view : ParseView(parent_text(trace_id, Digits.NonZero.to_string(16n, parent_id) ++ _),
        ContextProof.flags_result(trace_id, parent_id, TC.Parse.digits(2n, after, 53n)))
      flags_view(trace_id, parent_id, after)

law parent_nonzero_step:
  for +trace_id: Digits.NonZero<32n>
  for -digits: Digits.Digits(16n)
  for +rest: String
  for result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>
  for view: ParserProof.NonZeroView(16n, digits, result)
  ParseView(parent_text(trace_id, Digits.Digits.to_string(16n, digits) ++ rest),
    parent_nonzero_result(trace_id, rest, result))

def parent_nonzero_step(trace_id, digits, rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{+parent_id}:
      %view : ParseView(parent_text(trace_id, _ ++ rest),
        parent_after_result(trace_id, parent_id, TC.Parse.separator(rest, 52n)))
      parent_separator_step(trace_id, parent_id, rest, TC.Parse.separator(rest, 52n),
        ParserProof.separator_view(rest, 52n))

law parent_step:
  for +trace_id: Digits.NonZero<32n>
  for -after: String
  for result: Result<&2, &2, TC.Error, TC.Parsed<16n>>
  for view: ParserProof.DigitsView(16n, after, result)
  ParseView(parent_text(trace_id, after), ContextProof.parent_result(trace_id, result))

def parent_step(trace_id, after, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{+digits, +rest}}:
      %view : ParseView(parent_text(trace_id, _), TC.Parse.parent(trace_id, TC.Parsed{digits, rest}))
      parent_nonzero_step(trace_id, digits, rest, TC.Parse.nonzero(16n, digits, TC.ParentIdField{}),
        ParserProof.nonzero_view(16n, digits, TC.ParentIdField{}))

law parent_view:
  for +trace_id: Digits.NonZero<32n>
  for +after: String
  ParseView(parent_text(trace_id, after),
    ContextProof.parent_result(trace_id, TC.Parse.digits(16n, after, 36n)))

def parent_view(trace_id, after):
  parent_step(trace_id, after, TC.Parse.digits(16n, after, 36n),
    ParserProof.digits_view(16n, after, 36n))

# Trace ID: thirty-two nonzero digits, then the separator before the parent ID.
law trace_separator_step:
  for +trace_id: Digits.NonZero<32n>
  for -rest: String
  for result: Result<&2, &2, TC.Error, String>
  for view: ParserProof.SeparatorView(rest, result)
  ParseView(trace_text(Digits.NonZero.to_string(32n, trace_id) ++ rest),
    trace_after_result(trace_id, result))

def trace_separator_step(trace_id, rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{+after}:
      %view : ParseView(trace_text(Digits.NonZero.to_string(32n, trace_id) ++ _),
        ContextProof.parent_result(trace_id, TC.Parse.digits(16n, after, 36n)))
      parent_view(trace_id, after)

law trace_nonzero_step:
  for -digits: Digits.Digits(32n)
  for +rest: String
  for result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>
  for view: ParserProof.NonZeroView(32n, digits, result)
  ParseView(trace_text(Digits.Digits.to_string(32n, digits) ++ rest), trace_nonzero_result(rest, result))

def trace_nonzero_step(digits, rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{+trace_id}:
      %view : ParseView(trace_text(_ ++ rest), trace_after_result(trace_id, TC.Parse.separator(rest, 35n)))
      trace_separator_step(trace_id, rest, TC.Parse.separator(rest, 35n),
        ParserProof.separator_view(rest, 35n))

law trace_step:
  for -after: String
  for result: Result<&2, &2, TC.Error, TC.Parsed<32n>>
  for view: ParserProof.DigitsView(32n, after, result)
  ParseView(trace_text(after), ContextProof.trace_result(result))

def trace_step(after, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{+digits, +rest}}:
      %view : ParseView(trace_text(_), TC.Parse.trace(TC.Parsed{digits, rest}))
      trace_nonzero_step(digits, rest, TC.Parse.nonzero(32n, digits, TC.TraceIdField{}),
        ParserProof.nonzero_view(32n, digits, TC.TraceIdField{}))

law trace_view:
  for +after: String
  ParseView(trace_text(after), ContextProof.trace_result(TC.Parse.digits(32n, after, 3n)))

def trace_view(after):
  trace_step(after, TC.Parse.digits(32n, after, 3n), ParserProof.digits_view(32n, after, 3n))

# Version: exactly 00, then the separator before the trace ID.
law start_separator_step:
  for -rest: String
  for result: Result<&2, &2, TC.Error, String>
  for view: ParserProof.SeparatorView(rest, result)
  ParseView("00" ++ rest, start_after_result(result))

def start_separator_step(rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{+after}:
      %view : ParseView("00" ++ _, ContextProof.trace_result(TC.Parse.digits(32n, after, 3n)))
      trace_view(after)

law version_step:
  for -version: Digits.Digits(2n)
  for +rest: String
  for result: Result<&2, &2, TC.Error, Unit>
  for view: ParserProof.VersionView(version, result)
  ParseView(Digits.Digits.to_string(2n, version) ++ rest, version_result(rest, result))

def version_step(version, rest, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{version_ok}:
      %view : ParseView(_ ++ rest, start_after_result(TC.Parse.separator(rest, 2n)))
      start_separator_step(rest, TC.Parse.separator(rest, 2n), ParserProof.separator_view(rest, 2n))

law start_step:
  for -text: String
  for result: Result<&2, &2, TC.Error, TC.Parsed<2n>>
  for view: ParserProof.DigitsView(2n, text, result)
  ParseView(text, parse_result(result))

def start_step(text, result, view):
  match result:
    case Fail{error}:
      Unit{}
    case Done{TC.Parsed{+version, +rest}}:
      %view : ParseView(_, TC.Parse.start(TC.Parsed{version, rest}))
      version_step(version, rest, TC.Parse.version(version), ParserProof.version_view(version))

# Quantified over every String, including every rejected one.
law parse_view:
  for +text: String
  ParseView(text, TC.TraceParentV00.parse(text))

def parse_view(text):
  start_step(text, TC.Parse.digits(2n, text, 0n), ParserProof.digits_view(2n, text, 0n))
