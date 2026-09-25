import Base

# JavaScript host effect. The pure codec never calls it implicitly.
# Fail code 1 means unavailable; code 2 means source-failure.
# This adapter does not implement or qualify native generation.
def read_u32() -> IO(Result<&1, &1, U32 & String, U32>):
  import "./entropy/webcrypto.js"
