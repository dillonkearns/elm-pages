module BackendTask.Stream exposing
    ( Stream
    , fileRead, fileWrite, fromString, http, httpWithInput, pipe, stdin, stdout, stderr, gzip, unzip
    , command
    , read, readJson, run
    , Error(..)
    , commandWithOptions
    , StderrOutput(..)
    , CommandOptions, defaultCommandOptions, allowNon0Status, withOutput, withTimeout
    , customRead, customWrite, customDuplex
    )

{-| A `Stream` represents a flow of data through a pipeline.

It is typically

  - An input source, or Readable Stream (`Stream { read : (), write : Never }`)
  - An output destination, or Writable Stream (`Stream { read : Never, write : () }`)
  - And (optionally) a series of transformations in between, or Duplex Streams (`Stream { read : (), write : () }`)

For example, you could have a stream that

  - Reads from a file [`fileRead`](#fileRead)
  - Unzips the contents [`unzip`](#unzip)
  - Runs a shell command on the contents [`command`](#command)
  - And writes the result to a network connection [`httpWithInput`](#httpWithInput)

For example,

    import BackendTask.Stream as Stream exposing (Stream)

    example =
        Stream.fileRead "data.txt"
            |> Stream.unzip
            |> Stream.command "wc" [ "-l" ]
            |> Stream.httpWithInput
                { url = "http://example.com"
                , method = "POST"
                , headers = []
                , retries = Nothing
                , timeoutInMs = Nothing
                }
            |> Stream.run

End example

@docs Stream

@docs fileRead, fileWrite, fromString, http, httpWithInput, pipe, stdin, stdout, stderr, gzip, unzip


## Shell Commands

@docs command


## Running Streams

@docs read, readJson, run

@docs Error


## Command Options

@docs commandWithOptions

@docs StderrOutput

@docs CommandOptions, defaultCommandOptions, allowNon0Status, withOutput, withTimeout


## Custom Streams

@docs customRead, customWrite, customDuplex

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body)
import BackendTask.Internal.Request
import Bytes exposing (Bytes)
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody
import RequestsAndPending


{-| -}
type Stream error metadata kind
    = Stream ( String, Decoder (Result (Recoverable error) metadata) ) (List StreamPart)


type alias Recoverable error =
    { fatal : FatalError, recoverable : error }


mapRecoverable : Maybe body -> { a | fatal : b, recoverable : c } -> { fatal : b, recoverable : Error c body }
mapRecoverable maybeBody { fatal, recoverable } =
    { fatal = fatal
    , recoverable = CustomError recoverable maybeBody
    }


type StreamPart
    = StreamPart String (List ( String, Encode.Value ))


single : ( String, Decoder (Result (Recoverable error) metadata) ) -> String -> List ( String, Encode.Value ) -> Stream error metadata kind
single decoder inner1 inner2 =
    Stream decoder [ StreamPart inner1 inner2 ]


unit : ( String, Decoder (Result (Recoverable ()) ()) )
unit =
    ( "unit", Decode.succeed (Ok ()) )


{-| -}
stdin : Stream () () { read : (), write : Never }
stdin =
    single unit "stdin" []


{-| -}
stdout : Stream () () { read : Never, write : () }
stdout =
    single unit "stdout" []


{-| -}
stderr : Stream () () { read : Never, write : () }
stderr =
    single unit "stderr" []


{-| -}
fileRead : String -> Stream () () { read : (), write : Never }
fileRead path =
    -- TODO revisit the error type instead of ()?
    single unit "fileRead" [ ( "path", Encode.string path ) ]


{-| -}
fileWrite : String -> Stream () () { read : Never, write : () }
fileWrite path =
    single unit "fileWrite" [ ( "path", Encode.string path ) ]


{-| -}
customRead : String -> Encode.Value -> Stream () () { read : (), write : Never }
customRead name input =
    single unit
        "customRead"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| -}
customWrite : String -> Encode.Value -> Stream () () { read : Never, write : () }
customWrite name input =
    single unit
        "customWrite"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| -}
customDuplex : String -> Encode.Value -> Stream () () { read : (), write : () }
customDuplex name input =
    single unit
        "customDuplex"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| -}
gzip : Stream () () { read : (), write : () }
gzip =
    single unit "gzip" []


{-| -}
unzip : Stream () () { read : (), write : () }
unzip =
    single unit "unzip" []


{-| Streams the data from the input stream as the body of the HTTP request. The HTTP response body becomes the output stream.
-}
httpWithInput :
    { url : String
    , method : String
    , headers : List ( String, String )
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Stream BackendTask.Http.Error BackendTask.Http.Metadata { read : (), write : () }
httpWithInput string =
    -- Pages.Internal.StaticHttpBody
    single httpMetadataDecoder
        "httpWrite"
        [ ( "url", Encode.string string.url )
        , ( "method", Encode.string string.method )
        , ( "headers", Encode.list (\( key, value ) -> Encode.object [ ( "key", Encode.string key ), ( "value", Encode.string value ) ]) string.headers )
        , ( "retries", nullable Encode.int string.retries )
        , ( "timeoutInMs", nullable Encode.int string.timeoutInMs )
        ]


{-| Uses a regular HTTP request body (not a Stream), streams the HTTP response body.
-}
http :
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Stream BackendTask.Http.Error BackendTask.Http.Metadata { read : (), write : Never }
http request_ =
    single httpMetadataDecoder
        "httpWrite"
        [ ( "url", Encode.string request_.url )
        , ( "method", Encode.string request_.method )
        , ( "headers", Encode.list (\( key, value ) -> Encode.object [ ( "key", Encode.string key ), ( "value", Encode.string value ) ]) request_.headers )
        , ( "body", Pages.Internal.StaticHttpBody.encode request_.body )
        , ( "retries", nullable Encode.int request_.retries )
        , ( "timeoutInMs", nullable Encode.int request_.timeoutInMs )
        ]


httpMetadataDecoder : ( String, Decoder (Result (Recoverable BackendTask.Http.Error) BackendTask.Http.Metadata) )
httpMetadataDecoder =
    ( "http"
    , RequestsAndPending.responseDecoder
        |> Decode.map Ok
    )


{-| -}
pipe :
    Stream errorTo metaTo { read : toReadable, write : () }
    -> Stream errorFrom metaFrom { read : (), write : fromWriteable }
    -> Stream errorTo metaTo { read : toReadable, write : fromWriteable }
pipe (Stream decoderTo to) (Stream _ from) =
    Stream decoderTo (from ++ to)


{-| -}
run : Stream error metadata kind -> BackendTask FatalError ()
run stream =
    -- TODO give access to recoverable error here instead of just FatalError
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "none")
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


pipelineEncoder : Stream error metadata kind -> String -> Encode.Value
pipelineEncoder (Stream decoder parts) kind =
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
fromString : String -> Stream () () { read : (), write : Never }
fromString string =
    single unit "fromString" [ ( "string", Encode.string string ) ]


{-| -}
type Error error body
    = StreamError String
    | CustomError error (Maybe body)


{-| -}
read :
    Stream error metadata { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : Error error String } { metadata : metadata, body : String }
read ((Stream ( decoderName, decoder ) pipeline) as stream) =
    BackendTask.Internal.Request.request
        { name = "stream"

        -- TODO pass in `decoderName` to pipelineEncoder
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "text")
        , expect =
            BackendTask.Http.expectJson
                (Decode.oneOf
                    [ Decode.field "error" Decode.string
                        |> Decode.andThen
                            (\error ->
                                Decode.succeed
                                    (Err
                                        (FatalError.recoverable
                                            { title = "Stream Error"
                                            , body = error
                                            }
                                            (StreamError error)
                                        )
                                    )
                            )
                    , decodeLog (Decode.field "metadata" decoder)
                        |> Decode.andThen
                            (\result ->
                                case result of
                                    Ok metadata ->
                                        Decode.map
                                            (\body ->
                                                Ok
                                                    { metadata = metadata
                                                    , body = body
                                                    }
                                            )
                                            (Decode.field "body" Decode.string)

                                    Err error ->
                                        Decode.field "body" Decode.string
                                            |> Decode.maybe
                                            |> Decode.map
                                                (\body ->
                                                    error |> mapRecoverable body |> Err
                                                )
                            )
                    ]
                )
        }
        |> BackendTask.andThen BackendTask.fromResult


decodeLog : Decoder a -> Decoder a
decodeLog decoder =
    Decode.value
        |> Decode.andThen
            (\value ->
                --let
                --    _ =
                --        Debug.log (Encode.encode 2 value) ()
                --in
                decoder
            )


{-| -}
readJson :
    Decoder value
    -> Stream error metadata { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : Error error value } { metadata : metadata, body : value }
readJson decoder ((Stream ( decoderName, metadataDecoder ) pipeline) as stream) =
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "json")
        , expect =
            BackendTask.Http.expectJson
                (Decode.field "metadata" metadataDecoder
                    |> Decode.andThen
                        (\result1 ->
                            let
                                bodyResult : Decoder (Result Decode.Error value)
                                bodyResult =
                                    Decode.field "body" Decode.value
                                        |> Decode.map
                                            (\bodyValue ->
                                                Decode.decodeValue decoder bodyValue
                                            )
                            in
                            bodyResult
                                |> Decode.map
                                    (\result ->
                                        case result1 of
                                            Ok metadata ->
                                                case result of
                                                    Ok body ->
                                                        Ok
                                                            { metadata = metadata
                                                            , body = body
                                                            }

                                                    Err decoderError ->
                                                        FatalError.recoverable
                                                            { title = "Failed to decode body"
                                                            , body = "Failed to decode body"
                                                            }
                                                            (StreamError (Decode.errorToString decoderError))
                                                            |> Err

                                            Err error ->
                                                error
                                                    |> mapRecoverable (Result.toMaybe result)
                                                    |> Err
                                    )
                        )
                )
        }
        |> BackendTask.andThen BackendTask.fromResult


{-| -}
readBytes : Stream error metadata { read : (), write : write } -> BackendTask FatalError Bytes
readBytes stream =
    BackendTask.fail (FatalError.fromString "Not implemented")


{-| -}
command : String -> List String -> Stream Int () { read : read, write : write }
command command_ args_ =
    commandWithOptions defaultCommandOptions command_ args_


commandDecoder : Bool -> ( String, Decoder (Result (Recoverable Int) ()) )
commandDecoder allowNon0 =
    ( "command"
    , commandOutputDecoder
        |> Decode.map
            (\exitCode ->
                if exitCode == 0 || allowNon0 || True then
                    Ok ()

                else
                    Err
                        (FatalError.recoverable
                            { title = "Command Failed"
                            , body = "Command  failed with exit code " ++ String.fromInt exitCode
                            }
                            exitCode
                        )
            )
    )



-- on error, give CommandOutput as well


{-| -}
commandWithOptions : CommandOptions -> String -> List String -> Stream Int () { read : read, write : write }
commandWithOptions (CommandOptions options) command_ args_ =
    single (commandDecoder options.allowNon0Status)
        "command"
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
type CommandOptions
    = CommandOptions CommandOptions_


type alias CommandOptions_ =
    { output : StderrOutput
    , allowNon0Status : Bool
    , timeoutInMs : Maybe Int
    }


{-| -}
defaultCommandOptions : CommandOptions
defaultCommandOptions =
    CommandOptions
        { output = PrintStderr
        , allowNon0Status = False
        , timeoutInMs = Nothing
        }


{-| -}
withOutput : StderrOutput -> CommandOptions -> CommandOptions
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


encodeChannel : StderrOutput -> Encode.Value
encodeChannel output =
    Encode.string
        (case output of
            IgnoreStderr ->
                "Ignore"

            PrintStderr ->
                "Print"

            MergeStderrAndStdout ->
                "MergeWithStdout"

            StderrInsteadOfStdout ->
                "InsteadOfStdout"
        )


commandOutputDecoder : Decoder Int
commandOutputDecoder =
    Decode.field "exitCode" Decode.int


commandToString : String -> List String -> String
commandToString command_ args_ =
    command_ ++ " " ++ String.join " " args_


{-| -}
type StderrOutput
    = IgnoreStderr
    | PrintStderr
    | MergeStderrAndStdout
    | StderrInsteadOfStdout
