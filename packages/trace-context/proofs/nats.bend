import Base

law le_succ:
  for a: Nat
  for b: Nat
  {Nat.is_le(1n+a, b) == Nat.is_lt(a, b) : Bool}

def le_succ(a, b):
  match a:
    case 0n:
      match b:
        case 0n:
          {==}
        case 1n+more:
          match more:
            case 0n:
              {==}
            case 1n+rest:
              {==}
    case 1n+less:
      match b:
        case 0n:
          {==}
        case 1n+more:
          le_succ(less, more)
