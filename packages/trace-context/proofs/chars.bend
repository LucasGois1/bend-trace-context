import Base

# A comparison that reports EQ carries the equality of its operands.
def WordView(n: Nat, a: Word(n), b: Word(n), result: Cmp) -> Type:
  match result:
    case LT{}:
      Unit
    case EQ{}:
      {a == b : Word(n)}
    case GT{}:
      Unit

law word_step:
  for -p: Nat
  for -at: Word(p)
  for -bt: Word(p)
  for result: Cmp
  for tail: WordView(p, at, bt, result)
  for +ab: Bool
  for +bb: Bool
  WordView(1n+p, WCon{ab, at}, WCon{bb, bt}, Word.cmp.fin(ab, bb, result))

def word_step(p, at, bt, result, tail, ab, bb):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      match ab bb:
        case False{} False{}:
          %tail : {WCon{False{}, at} == WCon{False{}, _} : Word(1n+p)}
          {==}
        case False{} True{}:
          Unit{}
        case True{} False{}:
          Unit{}
        case True{} True{}:
          %tail : {WCon{True{}, at} == WCon{True{}, _} : Word(1n+p)}
          {==}
    case GT{}:
      Unit{}

law word_view:
  for +n: Nat
  for a: Word(n)
  for b: Word(n)
  WordView(n, a, b, Word.cmp(n, a, b))

def word_view(n, a, b):
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          word_step(p, at, bt, Word.cmp(p, at, bt), word_view(p, at, bt), ab, bb)

# A True character comparison carries the equality of the two characters.
def CharView(a: Char, b: Char, same: Bool) -> Type:
  match same:
    case False{}:
      Unit
    case True{}:
      {a == b : Char}

law char_step:
  for -x: Word(32n)
  for -y: Word(32n)
  for result: Cmp
  for view: WordView(32n, x, y, result)
  CharView(Chr{U32{x}}, Chr{U32{y}}, Cmp.is_eq(result))

def char_step(x, y, result, view):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      %view : {Chr{U32{x}} == Chr{U32{_}} : Char}
      {==}
    case GT{}:
      Unit{}

law char_view:
  for a: Char
  for b: Char
  CharView(a, b, Char.is_eq(a, b))

def char_view(a, b):
  match a b:
    case Chr{U32{+x}} Chr{U32{+y}}:
      char_step(x, y, Word.cmp(32n, x, y), word_view(32n, x, y))

law word_cmp_refl:
  for +n: Nat
  for w: Word(n)
  {Word.cmp(n, w, w) == EQ{} : Cmp}

def word_cmp_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{False{}, +tail}:
          %Equal.sym(Cmp, Word.cmp(p, tail, tail), EQ{}, word_cmp_refl(p, tail)) :
            {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
          {==}
        case WCon{True{}, +tail}:
          %Equal.sym(Cmp, Word.cmp(p, tail, tail), EQ{}, word_cmp_refl(p, tail)) :
            {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
          {==}
