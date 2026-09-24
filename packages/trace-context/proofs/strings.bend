import Base

law append_length:
  for a: String
  for b: String
  {String.length(a ++ b) == Nat.add(String.length(a), String.length(b)) : Nat}

def append_length(a, b):
  match a:
    case SNil{}:
      {==}
    case SCon{head, tail}:
      %append_length(tail, b) :
        {1n+String.length(tail ++ b) == 1n+_ : Nat}
      {==}

law joined_length:
  for a: String
  for b: String
  for n: Nat
  for m: Nat
  for a_length: {String.length(a) == n : Nat}
  for b_length: {String.length(b) == m : Nat}
  {String.length(a ++ b) == Nat.add(n, m) : Nat}

def joined_length(a, b, n, m, a_length, b_length):
  %b_length : {String.length(a ++ b) == Nat.add(n, _) : Nat}
  %a_length : {String.length(a ++ b) == Nat.add(_, String.length(b)) : Nat}
  append_length(a, b)
