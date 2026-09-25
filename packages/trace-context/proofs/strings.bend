import Base
import ./chars.bend as CharsProof

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

law append_nil:
  for a: String
  {a ++ "" == a : String}

def append_nil(a):
  match a:
    case SNil{}:
      {==}
    case SCon{head, tail}:
      %append_nil(tail) : {SCon{head, tail ++ ""} == SCon{head, _} : String}
      {==}

# Comparing the rest of two strings decides the comparison of their extensions.
law compare_rest:
  for -first: Char
  for -second: Char
  for rest: (String & String) & Cmp
  {String.eq.fin(String.cmp.rec(first, second, rest)) == String.eq.fin(rest) : Bool}

def compare_rest(first, second, rest):
  match rest:
    case ((left, right), result):
      {==}

law eq_refl:
  for +text: String
  {String.eq(text, text) == True{} : Bool}

def eq_refl(text):
  match text:
    case SNil{}:
      {==}
    case SCon{Chr{U32{+code}}, +tail}:
      %Equal.sym(Cmp, Word.cmp(32n, code, code), EQ{}, CharsProof.word_cmp_refl(32n, code)) :
        {String.eq.fin(String.cmp.fin(tail, tail, ((Chr{U32{code}}, Chr{U32{code}}), _))) == True{} : Bool}
      Equal.trans(Bool,
        String.eq.fin(String.cmp.rec(Chr{U32{code}}, Chr{U32{code}}, String.cmp(tail, tail))),
        String.eq.fin(String.cmp(tail, tail)), True{},
        compare_rest(Chr{U32{code}}, Chr{U32{code}}, String.cmp(tail, tail)), eq_refl(tail))

def BoolClash(value: Bool) -> Type:
  match value:
    case False{}:
      Empty
    case True{}:
      Unit

law true_ne_false:
  for clash: {True{} == False{} : Bool}
  Empty

def true_ne_false(clash):
  %clash : BoolClash(_)
  Unit{}

# A False comparison proves that the two strings differ.
law distinct:
  for +a: String
  for -b: String
  for different: {String.eq(a, b) == False{} : Bool}
  {a != b : String}

def distinct(a, b, different):
  same => true_ne_false(Equal.trans(Bool, True{}, String.eq(a, b), False{},
    Equal.trans(Bool, True{}, String.eq(a, a), String.eq(a, b),
      Equal.sym(Bool, String.eq(a, a), True{}, eq_refl(a)),
      Equal.cong(String, Bool, x => String.eq(a, x), a, b, same)),
    different))

# A True comparison carries the equality of the two strings.
def EqView(a: String, b: String, same: Bool) -> Type:
  match same:
    case False{}:
      Unit
    case True{}:
      {a == b : String}

law eq_tail_step:
  for -wx: Word(32n)
  for -wy: Word(32n)
  for -left: String
  for -right: String
  for char_view: {wx == wy : Word(32n)}
  for same: Bool
  for tail_view: EqView(left, right, same)
  EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right}, same)

def eq_tail_step(wx, wy, left, right, char_view, same, tail_view):
  match same:
    case False{}:
      Unit{}
    case True{}:
      %tail_view : {SCon{Chr{U32{wx}}, left} == SCon{Chr{U32{wy}}, _} : String}
      %char_view : {SCon{Chr{U32{wx}}, left} == SCon{Chr{U32{_}}, left} : String}
      {==}

law eq_char_step:
  for -wx: Word(32n)
  for -wy: Word(32n)
  for +left: String
  for +right: String
  for result: Cmp
  for char_view: CharsProof.WordView(32n, wx, wy, result)
  for tail_view: EqView(left, right, String.eq(left, right))
  EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right},
    String.eq.fin(String.cmp.fin(left, right, ((Chr{U32{wx}}, Chr{U32{wy}}), result))))

def eq_char_step(wx, wy, left, right, result, char_view, tail_view):
  match result:
    case LT{}:
      Unit{}
    case EQ{}:
      %Equal.sym(Bool,
        String.eq.fin(String.cmp.rec(Chr{U32{wx}}, Chr{U32{wy}}, String.cmp(left, right))),
        String.eq.fin(String.cmp(left, right)),
        compare_rest(Chr{U32{wx}}, Chr{U32{wy}}, String.cmp(left, right))) :
        EqView(SCon{Chr{U32{wx}}, left}, SCon{Chr{U32{wy}}, right}, _)
      eq_tail_step(wx, wy, left, right, char_view, String.eq(left, right), tail_view)
    case GT{}:
      Unit{}

law eq_view:
  for +a: String
  for +b: String
  EqView(a, b, String.eq(a, b))

def eq_view(a, b):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{head, tail}:
      Unit{}
    case SCon{head, tail} SNil{}:
      Unit{}
    case SCon{Chr{U32{+wx}}, +left} SCon{Chr{U32{+wy}}, +right}:
      eq_char_step(wx, wy, left, right, Word.cmp(32n, wx, wy), CharsProof.word_view(32n, wx, wy),
        eq_view(left, right))

# A True comparison proves that the two strings are equal.
law eq_sound:
  for +a: String
  for +b: String
  for same: {String.eq(a, b) == True{} : Bool}
  {a == b : String}

def eq_sound(a, b, same):
  %same : EqView(a, b, _)
  eq_view(a, b)
