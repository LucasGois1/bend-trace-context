import Base

# Reproduce the upstream boundary independently of the package adapter.
def describe(result: Result<&1, &1, U32 & String, U32>) -> String:
  match result:
    case Done{word}:
      "done:" ++ U32.show(word)
    case Fail{(code, message)}:
      "fail:" ++ U32.show(code) ++ ":" ++ message

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    IO.print(describe(result))
