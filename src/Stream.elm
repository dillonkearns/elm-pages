module Stream exposing (Stream, command, fileRead, fileWrite, fromString, httpRead, httpWrite, pipe, read, run, stdin, stdout, gzip, readJson, unzip)

{-|

@docs Stream, command, fileRead, fileWrite, fromString, httpRead, httpWrite, pipe, read, run, stdin, stdout, gzip, readJson, unzip

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body)
import BackendTask.Internal.Request
import Bytes exposing (Bytes)
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


{-| -}
type Stream kind
    = Stream (List StreamPart)


type StreamPart
    = StreamPart String (List ( String, Encode.Value ))


single : String -> List ( String, Encode.Value ) -> Stream kind
single inner1 inner2 =
    Stream [ StreamPart inner1 inner2 ]


{-| -}
stdin : Stream { read : (), write : Never }
stdin =
    single "stdin" []


{-| -}
stdout : Stream { read : Never, write : () }
stdout =
    single "stdout" []


{-| -}
fileRead : String -> Stream { read : (), write : Never }
fileRead path =
    single "fileRead" [ ( "path", Encode.string path ) ]


{-| -}
fileWrite : String -> Stream { read : Never, write : () }
fileWrite path =
    single "fileWrite" [ ( "path", Encode.string path ) ]


{-| -}
gzip : Stream { read : (), write : () }
gzip =
    single "gzip" []


{-| -}
unzip : Stream { read : (), write : () }
unzip =
    single "unzip" []


{-| -}
httpRead :
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Stream { read : (), write : Never }
httpRead string =
    single "httpRead" []


{-| -}
httpWrite :
    { url : String
    , method : String
    , headers : List ( String, String )
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Stream { read : Never, write : () }
httpWrite string =
    single "httpWrite" []


{-| -}
pipe :
    -- to
    Stream { read : toReadable, write : toWriteable }
    -- from
    -> Stream { read : (), write : fromWriteable }
    -> Stream { read : toReadable, write : toWriteable }
pipe (Stream to) (Stream from) =
    Stream (from ++ to)


{-| -}
run : Stream { read : read, write : () } -> BackendTask FatalError ()
run stream =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "none")
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


pipelineEncoder : Stream a -> String -> Encode.Value
pipelineEncoder (Stream parts) kind =
    Encode.object
        [ ( "kind", Encode.string kind )
        , ( "parts"
          , Encode.list
                (\(StreamPart name data) ->
                    Encode.object (( "name", Encode.string name ) :: data)
                )
                parts
          )
        ]


{-| -}
fromString : String -> Stream { read : (), write : Never }
fromString string =
    single "fromString" [ ( "string", Encode.string string ) ]


{-| -}
read : Stream { read : (), write : write } -> BackendTask FatalError String
read stream =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "text")
        , expect = BackendTask.Http.expectJson Decode.string
        }


{-| -}
readJson : Decoder value -> Stream { read : (), write : write } -> BackendTask FatalError value
readJson decoder stream =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "json")
        , expect = BackendTask.Http.expectJson decoder
        }


{-| -}
readBytes : Stream { read : (), write : write } -> BackendTask FatalError Bytes
readBytes stream =
    BackendTask.fail (FatalError.fromString "Not implemented")


{-| -}
command : String -> List String -> Stream { read : read, write : write }
command command_ args_ =
    single "command"
        [ ( "command", Encode.string command_ )
        , ( "args", Encode.list Encode.string args_ )
        ]
