import Base
import ./LAWS.bend as Laws
import ./trace_context.bend as Trace
import ./src/digits.bend as Digits
import ./proofs/hex.bend as HexProof
import ./proofs/digits.bend as DigitsProof
import ./proofs/strings.bend as StringsProof
import ./proofs/parser.bend as ParserProof
import ./proofs/context.bend as ContextProof

def Laws.formatted_length(context):
  match context:
    case Trace.TraceParentV00{+trace_id, +parent_id, +flags}:
      +trace = Digits.NonZero.to_string(32n, trace_id)
      +parent = Digits.NonZero.to_string(16n, parent_id)
      +flag_text = Digits.Digits.to_string(2n, flags)
      f = StringsProof.joined_length("-", flag_text, 1n, 2n,
        {==}, DigitsProof.encoded_length(2n, flags))
      p = StringsProof.joined_length(parent, "-" ++ flag_text, 16n, 3n,
        DigitsProof.nonzero_encoded_length(16n, parent_id), f)
      ps = StringsProof.joined_length("-", parent ++ "-" ++ flag_text,
        1n, 19n, {==}, p)
      t = StringsProof.joined_length(trace, "-" ++ parent ++ "-" ++ flag_text,
        32n, 20n, DigitsProof.nonzero_encoded_length(32n, trace_id), ps)
      StringsProof.joined_length("00-", trace ++ "-" ++ parent ++ "-" ++ flag_text,
        3n, 52n, {==}, t)

def Laws.roundtrip(context):
  ContextProof.roundtrip(context)
