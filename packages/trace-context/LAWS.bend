import Base
import ./trace_context.bend as Trace

# This is a statement about every value of the type, not just parsed examples.
law formatted_length:
  for context: Trace.TraceParentV00
  {String.length(Trace.TraceParentV00.format(context)) == 55n : Nat}

# The IDs, their evidence and all flag bits survive the complete codec.
law roundtrip:
  for context: Trace.TraceParentV00
  {Trace.TraceParentV00.parse(Trace.TraceParentV00.format(context)) ==
    Done{context} : Result<&2, &2, Trace.Error, Trace.TraceParentV00>}
