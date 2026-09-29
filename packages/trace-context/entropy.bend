# W3C Trace Context Level 2 propagation, with its rules proved as laws. Source: https://github.com/LucasGois1/bend-trace-context
#
# Host entropy
# ============
#
# The first line is the package's description on BendHub, which describes a
# package by the first line of its first .bend file in path order: this one.
#
# The package's only host binding for randomness: entropy/native.c natively and
# entropy/webcrypto.js in JavaScript. generation.bend reads source words from
# it; trace_context.bend never does.

import Base

# One word from the host's cryptographic source: WebCrypto in JavaScript and
# the operating system's generator natively. Fail code 1 means unavailable and
# code 2 means source-failure in JavaScript; natively the code is the host
# errno with its strerror text. The pure codec never calls it implicitly.
def read_u32() -> IO(Result<&1, &1, U32 & String, U32>):
  import "./entropy/native.c"
  import "./entropy/webcrypto.js"
