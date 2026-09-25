import Base
import ../../../packages/trace-context/entropy.bend as Entropy

def describe(result: Result<&1, &1, U32 & String, U32>) -> String:
  match result:
    case Done{word}:
      "done:" ++ U32.show(word)
    case Fail{(code, message)}:
      "fail:" ++ U32.show(code) ++ ":" ++ message

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, U32> <- Entropy.read_u32()
    IO.print(describe(result))
