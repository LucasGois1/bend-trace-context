import Base

# One word from the host's cryptographic source: WebCrypto in JavaScript and
# the operating system's generator natively. Fail code 1 means unavailable and
# code 2 means source-failure in JavaScript; natively the code is the host
# errno with its strerror text. The pure codec never calls it implicitly.
def read_u32() -> IO(Result<&1, &1, U32 & String, U32>):
  import "./entropy/native.c"
  import "./entropy/webcrypto.js"
