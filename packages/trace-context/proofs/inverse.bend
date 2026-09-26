# Proofs: formatting reproduces every accepted text
# =================================================
#
# Proves that TraceParentV00.parse accepts only texts that formatting
# reproduces: parse_view proves the view ParseView for every string, and
# PROOF.bend's Laws.inverse rewrites the hypothesis of law inverse into it.
# With law roundtrip (proofs/context.bend), parse and format are exact
# inverses. trace_context.bend is imported as TC.
#
# The proof follows the parser stage by stage: version, trace ID, parent ID,
# flags. A step law receives the result of one reader of the parser with that
# reader's view from proofs/parser.bend, and matches on the result. A failure
# leaves Unit to prove. A success supplies the equation that rewrites the text
# into the pieces read so far and the text still to read (trace_text,
# parent_text, flags_text); the law then calls the next stage. At the end of
# the text, both sides of the goal compute to the same string. A `*_view` law
# applies a step to the actual reader and its view. The `*_result` defs name
# the rest of the parser after one reader, as a function of that reader's
# result: `match` cannot inspect a computed value, so each step takes the
# result as a parameter, and a rewrite motive (the P of `%e : P`) marks it
# with `_`. In the step laws, `-x` binders are erased (only the types mention
# them) and `+x` binders may be used several times. A def may only call the
# defs written above it, so the stages appear from the flags back to the
# version, and parse_view, the entry point, comes last.

import Base
import ../trace_context.bend as TC
import ../src/digits.bend as Digits
import ./parser.bend as ParserProof
import ./context.bend as ContextProof

# The view of the whole parser for `text`: Unit for a failure and, for a
# success, the equation saying that formatting the value returned gives back
# `text`. Each step law concludes it for the whole text, written as the pieces
# read so far and the rest, and for the rest of the parse.
def ParseView(text: String, result: Result<&2, &2, TC.Error, TC.TraceParentV00>) -> Type:
  match result:
    case Fail{error}:
      Unit
    case Done{context}:
      {TC.TraceParentV00.format(context) == text : String}

# The whole text once the version and its "-" have been read: "00-" followed
# by `rest`, where the trace ID starts.
def trace_text(rest: String) -> String:
  "00-" ++ rest

# The whole text once the trace ID and its "-" have also been read: `rest`
# starts at the parent ID.
def parent_text(trace_id: Digits.NonZero<32n>, rest: String) -> String:
  "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++ rest

# The whole text once the parent ID and its "-" have also been read: `rest`
# starts at the flags. With the text of the flags as `rest`, it computes to
# the same string as TraceParentV00.format of the value.
def flags_text(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>, rest: String) -> String:
  "00-" ++ Digits.NonZero.to_string(32n, trace_id) ++ "-" ++
    Digits.NonZero.to_string(16n, parent_id) ++ "-" ++ rest

# The rest of Parse.flags, as a function of the end check's `result`: when
# the text ended, the value made of the three fields.
def end_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  flags: Digits.Digits(2n), result: Result<&2, &2, TC.Error, Unit>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    end : Unit <- result
    return TC.TraceParentV00{trace_id, parent_id, flags}

# The rest of Parse.parent after the separator that follows the parent ID, as
# a function of that separator's `result`: the flags, read from offset 53.
def parent_after_result(trace_id: Digits.NonZero<32n>, parent_id: Digits.NonZero<16n>,
  result: Result<&2, &2, TC.Error, String>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.flags_result(trace_id, parent_id, TC.Parse.digits(2n, after, 53n))

# The rest of Parse.parent after the parent ID's digits, as a function of
# their nonzero check's `result`: the separator at offset 52, then the flags.
def parent_nonzero_result(trace_id: Digits.NonZero<32n>, rest: String,
  result: Result<&2, &2, TC.Error, Digits.NonZero<16n>>) -> Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    parent_id : Digits.NonZero<16n> <- result
    parent_after_result(trace_id, parent_id, TC.Parse.separator(rest, 52n))

# The rest of Parse.trace after the separator that follows the trace ID, as a
# function of that separator's `result`: the parent ID, read from offset 36.
def trace_after_result(trace_id: Digits.NonZero<32n>, result: Result<&2, &2, TC.Error, String>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.parent_result(trace_id, TC.Parse.digits(16n, after, 36n))

# The rest of Parse.trace after the trace ID's digits, as a function of their
# nonzero check's `result`: the separator at offset 35, then the parent ID.
def trace_nonzero_result(rest: String, result: Result<&2, &2, TC.Error, Digits.NonZero<32n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    trace_id : Digits.NonZero<32n> <- result
    trace_after_result(trace_id, TC.Parse.separator(rest, 35n))

# The rest of Parse.start after the separator that follows the version, as a
# function of that separator's `result`: the trace ID, read from offset 3.
def start_after_result(result: Result<&2, &2, TC.Error, String>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    after : String <- result
    ContextProof.trace_result(TC.Parse.digits(32n, after, 3n))

# The rest of Parse.start after the version digits, as a function of the
# version check's `result`: the separator at offset 2, then the trace ID.
def version_result(rest: String, result: Result<&2, &2, TC.Error, Unit>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    version_ok : Unit <- result
    start_after_result(TC.Parse.separator(rest, 2n))

# TraceParentV00.parse as a function of the read of the two version digits:
# Parse.start on its success.
def parse_result(result: Result<&2, &2, TC.Error, TC.Parsed<2n>>) ->
  Result<&2, &2, TC.Error, TC.TraceParentV00>:
  do Result<&2, &2, TC.Error, TC.TraceParentV00>:
    version : TC.Parsed<2n> <- result
    TC.Parse.start(version)

# When the end check of the text after the flag digits satisfies EndView (a
# success means that text is empty), the value built formats to the whole
# text. This is the last stage, the flags: two digits, then the end of the
# text. flags_step uses it.
law end_step:
  for -trace_id: Digits.NonZero<32n>
  for -parent_id: Digits.NonZero<16n>
  for flags: Digits.Digits(2n)
  for -rest: String
  for result: Result<&2, &2, TC.Error, Unit>
  for view: ParserProof.EndView(rest, result)
  ParseView(flags_text(trace_id, parent_id, Digits.Digits.to_string(2n, flags) ++ rest),
    end_result(trace_id, parent_id, flags, result))

# Splits the flags: after rest becomes "", their text ++ "" must compute.
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

# When the read of the two flag digits from `after` satisfies DigitsView, the
# rest of the parse satisfies ParseView for the whole text ending in `after`.
# A success rewrites `after` into the flags' text and the rest, then calls
# end_step. flags_view uses it.
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

# Whatever text `after` follows the separator after the parent ID, a
# successful parse of the flags from it, at offset 53, yields a value that
# formats to the whole text. parent_separator_step uses it.
law flags_view:
  for +trace_id: Digits.NonZero<32n>
  for +parent_id: Digits.NonZero<16n>
  for +after: String
  ParseView(flags_text(trace_id, parent_id, after),
    ContextProof.flags_result(trace_id, parent_id, TC.Parse.digits(2n, after, 53n)))

def flags_view(trace_id, parent_id, after):
  flags_step(trace_id, parent_id, after, TC.Parse.digits(2n, after, 53n),
    ParserProof.digits_view(2n, after, 53n))

# When the read of the separator after the parent ID satisfies SeparatorView,
# the rest of the parse satisfies ParseView for the whole text. Parent ID
# stage: sixteen nonzero digits, then the separator before the flags.
# parent_nonzero_step uses it.
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

# When the nonzero check of the parent ID's digits satisfies NonZeroView, the
# rest of the parse satisfies ParseView for the whole text. A success rewrites
# the text of the digits into the text of the parent ID returned. parent_step
# uses it.
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

# When the read of the sixteen parent ID digits from `after` satisfies
# DigitsView, the rest of the parse satisfies ParseView for the whole text.
# parent_view uses it.
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

# Whatever text `after` follows the separator after the trace ID, a
# successful parse from the parent ID, at offset 36, yields a value that
# formats to the whole text. trace_separator_step uses it.
law parent_view:
  for +trace_id: Digits.NonZero<32n>
  for +after: String
  ParseView(parent_text(trace_id, after),
    ContextProof.parent_result(trace_id, TC.Parse.digits(16n, after, 36n)))

def parent_view(trace_id, after):
  parent_step(trace_id, after, TC.Parse.digits(16n, after, 36n),
    ParserProof.digits_view(16n, after, 36n))

# When the read of the separator after the trace ID satisfies SeparatorView,
# the rest of the parse satisfies ParseView for the whole text. Trace ID
# stage: thirty-two nonzero digits, then the separator before the parent ID.
# trace_nonzero_step uses it.
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

# When the nonzero check of the trace ID's digits satisfies NonZeroView, the
# rest of the parse satisfies ParseView for the whole text. A success rewrites
# the text of the digits into the text of the trace ID returned. trace_step
# uses it.
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

# When the read of the thirty-two trace ID digits from `after` satisfies
# DigitsView, the rest of the parse satisfies ParseView for the whole text.
# trace_view uses it.
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

# Whatever text `after` follows "00-", a successful parse from the trace ID,
# at offset 3, yields a value that formats to the whole text.
# start_separator_step uses it.
law trace_view:
  for +after: String
  ParseView(trace_text(after), ContextProof.trace_result(TC.Parse.digits(32n, after, 3n)))

def trace_view(after):
  trace_step(after, TC.Parse.digits(32n, after, 3n), ParserProof.digits_view(32n, after, 3n))

# When the read of the separator after the version satisfies SeparatorView,
# the rest of the parse satisfies ParseView for "00" followed by `rest`.
# Version stage: exactly 00, then the separator before the trace ID.
# version_step uses it.
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

# When the version check of the two version digits satisfies VersionView,
# the rest of the parse satisfies ParseView for their text followed by
# `rest`: a success rewrites that text into "00". start_step uses it.
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

# When the read of the two version digits from `text` satisfies DigitsView,
# the whole parse (parse_result) satisfies ParseView for `text`. parse_view,
# the entry point, uses it.
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

# For every string, a successful TraceParentV00.parse returns a value that
# formats back to that string. Quantified over every String, including every
# rejected one, whose view is Unit. PROOF.bend's Laws.inverse proves law
# inverse with it.
law parse_view:
  for +text: String
  ParseView(text, TC.TraceParentV00.parse(text))

def parse_view(text):
  start_step(text, TC.Parse.digits(2n, text, 0n), ParserProof.digits_view(2n, text, 0n))
