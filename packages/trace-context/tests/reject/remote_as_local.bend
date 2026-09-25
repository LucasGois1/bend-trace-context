# Expected compile-time rejection: a received context is not a local context.
# A participant creates its own operation with Context.child_from_id instead.
import Base
import ../../trace_context.bend as TC

def invalid(remote: TC.RemoteContext) -> TC.LocalContext:
  remote
