import Base

# Two IO operations of this file's own, for the facade test of what the
# compiler's ES module of a Bend file exports: one without parameters, which
# the module leaves out, and one with a parameter, which it exports as a
# function that returns an unrun IO action.
def greet() -> IO(Unit):
  IO.print("hello")

def greet_name(name: String) -> IO(Unit):
  IO.print("hello " ++ name)
