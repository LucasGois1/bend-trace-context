import Base

law append_assoc:
  for -A: Data
  for a: List<&2, A>
  for b: List<&2, A>
  for c: List<&2, A>
  {List.append(&2, A, List.append(&2, A, a, b), c) == List.append(&2, A, a, List.append(&2, A, b, c)) : List<&2, A>}

def append_assoc(A, a, b, c):
  match a:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %append_assoc(A, tail, b, c) : {Con{head, List.append(&2, A, List.append(&2, A, tail, b), c)} == Con{head, _} :
        List<&2, A>}
      {==}

law append_nil:
  for -A: Data
  for list: List<&2, A>
  {List.append(&2, A, list, Nil{}) == list : List<&2, A>}

def append_nil(A, list):
  match list:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %append_nil(A, tail) : {Con{head, List.append(&2, A, tail, Nil{})} == Con{head, _} : List<&2, A>}
      {==}

law length_snoc:
  for -A: Data
  for list: List<&2, A>
  for -last: A
  {List.length(&2, A, List.append(&2, A, list, Con{last, Nil{}})) == 1n+List.length(&2, A, list) : Nat}

def length_snoc(A, list, last):
  match list:
    case Nil{}:
      {==}
    case Con{head, tail}:
      %length_snoc(A, tail, last) : {1n+List.length(&2, A, List.append(&2, A, tail, Con{last, Nil{}})) == 1n+_ : Nat}
      {==}
