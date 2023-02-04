module Post exposing (Post, decoder)

import BackendTask.Custom
import Date exposing (Date)
import Json.Decode as Decode exposing (Decoder)
import Time


type alias Post =
    { title : String
    , body : String
    , slug : String
    , publish : Maybe Date
    }


decoder : Decoder Post
decoder =
    Decode.map4 Post
        (Decode.field "title" Decode.string)
        (Decode.field "body" Decode.string)
        (Decode.field "slug" Decode.string)
        (Decode.field "publish"
            (Decode.nullable
                BackendTask.Custom.dateDecoder
             --(Decode.int |> Decode.map (Time.millisToPosix >> Date.fromPosix Time.utc))
            )
        )
