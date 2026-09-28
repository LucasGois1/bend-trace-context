# The request shape of the W3C Trace Context test harness
# =======================================================
#
# The harness posts to a service's /test route a JSON array of actions, each
# {url, arguments}, and the service posts each action's arguments, as JSON,
# to its url. The native transport fixture and the native propagation
# service read that shape here. bend-kit's JSON values are linear, so one
# pass over an action's fields takes both.
import Base
# bend-kit-http 0.23.0.1 and bend-kit-json 0.5.0.1, the JSON package that it
# uses, from BendHub by content hash. Http.Body() is bend-kit's byte string,
# which JSON text, strings and object keys are too.
import 0x1cef8a5fb1d9142ca5c6b2cb43629b21/http.bend as Http
import 0x584fc27920487ceab242392391418d7f/json.bend as Json

# One action: the URL it names, if it names one as a JSON string, and the
# body to post there, its arguments as JSON text, "[]" without any.
type Action is Data:
  Action{url: Maybe<&2, String>, body: String}

def Action.url(action: Action) -> Maybe<&2, String>:
  match action:
    case Action{url, body}:
      url

def Action.body(action: Action) -> String:
  match action:
    case Action{url, body}:
      body

# An action that names no URL and has no arguments.
def Action.empty() -> Action:
  Action{None{}, "[]"}

# The URL of a JSON string, one character per octet, as bend-kit's HTTP
# package reads the text of a request.
def url.of(value: Json.Val) -> Maybe<&2, String>:
  match value:
    case Json.Str{text}:
      Some{Http.to_string(text)}
    case other:
      None{}

# An action with one more field of its JSON object: `url` and `arguments` set
# its parts, and any other field leaves it as it is.
def field.set(is.url: Bool, is.arguments: Bool, value: Json.Val, action: Action) -> Action:
  match is.url:
    case True{}:
      Action{url.of(value), Action.body(action)}
    case False{}:
      match is.arguments:
        case True{}:
          Action{Action.url(action), Http.to_string(Json.encode.bytes(value))}
        case False{}:
          action

def field(+name: String, value: Json.Val, action: Action) -> Action:
  field.set(String.eq(name, "url"), String.eq(name, "arguments"), value, action)

def fields(kvs: List<&1, Http.Body() & Json.Val>, action: Action) -> Action:
  match kvs:
    case Nil{}:
      action
    case Con{(name, value), rest}:
      fields(rest, field(Http.to_string(name), value, action))

# The action of one element of the array: an object's fields, or an empty
# action for any other JSON value.
def action(value: Json.Val) -> Action:
  match value:
    case Json.Obj{kvs}:
      fields(kvs, Action.empty())
    case other:
      Action.empty()

def actions(values: List<&1, Json.Val>) -> List<&2, Action>:
  match values:
    case Nil{}:
      Nil{}
    case Con{value, rest}:
      Con{action(value), actions(rest)}

def parse.of(parsed: Maybe<&1, Json.Val>) -> Maybe<&2, List<&2, Action>>:
  match parsed:
    case Some{Json.Arr{values}}:
      Some{actions(values)}
    case Some{other}:
      None{}
    case None{}:
      None{}

# The actions of a request body, or None unless it is a JSON array.
def parse(body: Http.Body()) -> Maybe<&2, List<&2, Action>>:
  parse.of(Json.parse.bytes(body))
