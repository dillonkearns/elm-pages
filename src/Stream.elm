module Stream exposing
    ( Stream, command, fileRead, fileWrite, fromString, httpRead, httpWrite, pipe, read, run, stdin, stdout, gzip, readJson, unzip
    , CommandOutput, captureCommandWithInput, runCommandWithInput
    , captureCommand, runCommand
    , commandWithOptions
    , CommandOptions, defaultCommandOptions, allowNon0Status, inheritUnused, withOutput, withTimeout
    , OutputChannel(..)
    )

{-|

@docs Stream, command, fileRead, fileWrite, fromString, httpRead, httpWrite, pipe, read, run, stdin, stdout, gzip, readJson, unzip

@docs CommandOutput, captureCommandWithInput, runCommandWithInput


## Running Commands

@docs captureCommand, runCommand


## Command Options

@docs commandWithOptions

@docs CommandOptions, defaultCommandOptions, allowNon0Status, inheritUnused, withOutput, withTimeout

@docs OutputChannel

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
    Stream { read : toReadable, write : toWriteable }
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
    commandWithOptions defaultCommandOptions command_ args_


{-| -}
commandWithOptions : CommandOptions -> String -> List String -> Stream { read : read, write : write }
commandWithOptions (CommandOptions options) command_ args_ =
    single "command"
        [ ( "command", Encode.string command_ )
        , ( "args", Encode.list Encode.string args_ )
        , ( "allowNon0Status", Encode.bool options.allowNon0Status )
        , ( "output", encodeChannel options.output )
        , ( "timeoutInMs", nullable Encode.int options.timeoutInMs )
        ]


nullable : (a -> Encode.Value) -> Maybe a -> Encode.Value
nullable encoder maybeValue =
    case maybeValue of
        Just value ->
            encoder value

        Nothing ->
            Encode.null


{-| -}
type OutputChannel
    = Stdout
    | Stderr
    | Both


{-| -}
type CommandOptions
    = CommandOptions CommandOptions_


type alias CommandOptions_ =
    { output : OutputChannel
    , inheritUnused : Bool
    , allowNon0Status : Bool
    , timeoutInMs : Maybe Int
    }


{-| -}
defaultCommandOptions : CommandOptions
defaultCommandOptions =
    CommandOptions
        { output = Stdout
        , inheritUnused = False
        , allowNon0Status = False
        , timeoutInMs = Nothing
        }


{-| -}
withOutput : OutputChannel -> CommandOptions -> CommandOptions
withOutput output (CommandOptions cmd) =
    CommandOptions { cmd | output = output }


{-| -}
allowNon0Status : CommandOptions -> CommandOptions
allowNon0Status (CommandOptions cmd) =
    CommandOptions { cmd | allowNon0Status = True }


{-| -}
withTimeout : Int -> CommandOptions -> CommandOptions
withTimeout timeoutMs (CommandOptions cmd) =
    CommandOptions { cmd | timeoutInMs = Just timeoutMs }


{-| -}
inheritUnused : CommandOptions -> CommandOptions
inheritUnused (CommandOptions cmd) =
    CommandOptions { cmd | inheritUnused = True }


encodeChannel : OutputChannel -> Encode.Value
encodeChannel output =
    Encode.string
        (case output of
            Stdout ->
                "stdout"

            Stderr ->
                "stderr"

            Both ->
                "both"
        )


{-| -}
type alias CommandOutput =
    { stdout : String
    , stderr : String
    , combined : String
    , exitCode : Int
    }


commandOutputDecoder : Decoder CommandOutput
commandOutputDecoder =
    Decode.map4 CommandOutput
        (Decode.field "stdoutOutput" Decode.string)
        (Decode.field "stderrOutput" Decode.string)
        (Decode.field "combinedOutput" Decode.string)
        (Decode.field "exitCode" Decode.int)


{-| -}
captureCommandWithInput :
    String
    -> List String
    -> Stream { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : { code : Int, output : CommandOutput } } CommandOutput
captureCommandWithInput command_ args_ stream =
    captureCommand_ command_ args_ (Just stream)


{-| -}
captureCommand_ :
    String
    -> List String
    -> Maybe (Stream { read : (), write : write })
    -> BackendTask { fatal : FatalError, recoverable : { code : Int, output : CommandOutput } } CommandOutput
captureCommand_ command_ args_ maybeStream =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body =
            BackendTask.Http.jsonBody
                (pipelineEncoder
                    (case maybeStream of
                        Just stream ->
                            stream
                                |> pipe (command command_ args_)

                        Nothing ->
                            command command_ args_
                    )
                    "command"
                )
        , expect = BackendTask.Http.expectJson commandOutputDecoder
        }


{-| -}
runCommandWithInput :
    String
    -> List String
    -> Stream { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : Int } ()
runCommandWithInput command_ args_ maybeStream =
    runCommand_ command_ args_ (Just maybeStream)


{-| -}
runCommand_ :
    String
    -> List String
    -> Maybe (Stream { read : (), write : write })
    -> BackendTask { fatal : FatalError, recoverable : Int } ()
runCommand_ command_ args_ maybeStream =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body =
            BackendTask.Http.jsonBody
                (pipelineEncoder
                    (case maybeStream of
                        Just stream ->
                            stream
                                |> pipe (command command_ args_)

                        Nothing ->
                            command command_ args_
                    )
                    "commandCode"
                )
        , expect = BackendTask.Http.expectJson (Decode.field "exitCode" Decode.int)
        }
        |> BackendTask.andThen
            (\exitCode ->
                if exitCode == 0 then
                    BackendTask.succeed ()

                else
                    BackendTask.fail
                        (FatalError.recoverable
                            { title = "Command Failed"
                            , body = "Command `" ++ commandToString command_ args_ ++ "` failed with exit code " ++ String.fromInt exitCode
                            }
                            exitCode
                        )
            )


{-| -}
captureCommand :
    String
    -> List String
    -> BackendTask { fatal : FatalError, recoverable : { code : Int, output : CommandOutput } } CommandOutput
captureCommand command_ args_ =
    captureCommand_ command_ args_ Nothing


{-| -}
runCommand :
    String
    -> List String
    -> BackendTask { fatal : FatalError, recoverable : Int } ()
runCommand command_ args_ =
    runCommand_ command_ args_ Nothing


commandToString : String -> List String -> String
commandToString command_ args_ =
    command_ ++ " " ++ String.join " " args_
