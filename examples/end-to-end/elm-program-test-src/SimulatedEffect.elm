module SimulatedEffect exposing (HttpRequest, SimulatedEffect(..), SimulatedSub(..), SimulatedTask(..))

import Http
import Json.Decode
import Json.Encode
import Time


type SimulatedEffect msg
    = None
    | Batch (List (SimulatedEffect msg))
    | Task (SimulatedTask msg msg)
    | PortEffect String Json.Encode.Value
      -- Navigation
    | PushUrl String
    | ReplaceUrl String
    | Back Int
    | Load String
    | Reload Bool


type SimulatedTask x a
    = Succeed a
    | Fail x
    | HttpTask (HttpRequest x a)
    | SleepTask Float (() -> SimulatedTask x a)
    | NowTask (Time.Posix -> SimulatedTask x a)


type alias HttpRequest x a =
    { method : String
    , url : String
    , body : String
    , headers : List ( String, String )
    , onRequestComplete : Http.Response String -> SimulatedTask x a
    }


type SimulatedSub msg
    = NoneSub
    | BatchSub (List (SimulatedSub msg))
    | PortSub String (Json.Decode.Decoder msg)
