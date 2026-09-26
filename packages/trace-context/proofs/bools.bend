import Base
import ./strings.bend as StringsProof

def absurd(-A: Type, clash: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, StringsProof.true_ne_false(Equal.sym(Bool, False{}, True{}, clash)))

law not_true:
  for a: Bool
  for holds: {Bool.not(a) == True{} : Bool}
  {a == False{} : Bool}

def not_true(a, holds):
  match a:
    case False{}:
      {==}
    case True{}:
      absurd({True{} == False{} : Bool}, holds)

law and_left:
  for a: Bool
  for -b: Bool
  for both: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def and_left(a, b, both):
  match a:
    case False{}:
      both
    case True{}:
      {==}

law and_right:
  for a: Bool
  for -b: Bool
  for both: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def and_right(a, b, both):
  match a:
    case False{}:
      absurd({b == True{} : Bool}, both)
    case True{}:
      both

law or_left_false:
  for a: Bool
  for -b: Bool
  for both: {Bool.or(a, b) == False{} : Bool}
  {a == False{} : Bool}

def or_left_false(a, b, both):
  match a:
    case False{}:
      {==}
    case True{}:
      both

law or_right_false:
  for a: Bool
  for -b: Bool
  for both: {Bool.or(a, b) == False{} : Bool}
  {b == False{} : Bool}

def or_right_false(a, b, both):
  match a:
    case False{}:
      both
    case True{}:
      Empty.absurd({b == False{} : Bool}, StringsProof.true_ne_false(both))
