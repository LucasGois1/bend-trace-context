# Expected compile-time rejection: no proof that an uppercase text is a
# tracestate key. Keys come from StateKey.parse or a parsed tracestate.
import Base
import ../../trace_context.bend as TC

def invalid() -> TC.StateKey:
  TC.StateKey{"Vendor", {==}}
