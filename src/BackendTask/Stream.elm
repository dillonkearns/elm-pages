module BackendTask.Stream exposing
    ( Stream
    , pipe
    , fileRead, fileWrite, fromString, http, httpWithInput, stdin, stdout, stderr
    , read, readJson, readMetadata, run
    , Error(..)
    , command
    , commandWithOptions
    , StderrOutput(..)
    , CommandOptions, defaultCommandOptions, allowNon0Status, withOutput, withTimeout
    , gzip, unzip
    , customRead, customWrite, customDuplex
    , customReadWithMeta, customTransformWithMeta, customWriteWithMeta
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

@docs pipe

@docs fileRead, fileWrite, fromString, http, httpWithInput, stdin, stdout, stderr


## Running Streams

@docs read, readJson, readMetadata, run

@docs Error


## Shell Commands

Note that the commands do not execute through a shell but rather directly executes a child process. That means that
special shell syntax will have no effect, but instead will be interpreted as literal characters in arguments to the command.

So instead of `grep error < log.txt`, you would use

    module GrepErrors exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "log.txt"
                |> Stream.pipe (Stream.command "grep" [ "error" ])
                |> Stream.stdout
                |> Stream.run
            )

@docs command


## Command Options

@docs commandWithOptions

@docs StderrOutput

@docs CommandOptions, defaultCommandOptions, allowNon0Status, withOutput, withTimeout


## Command Output Strategies

There are 3 things that effect the output behavior of a command:

  - The verbosity of the `BackendTask` context ([`BackendTask.quiet`](BackendTask#quiet))
  - Whether the `Stream` output is ignored ([`Stream.run`](#run)), or read ([`Stream.read`](#read))
  - [`withOutput`](#withOutput) (allows you to use stdout, stderr, or both)

With `BackendTask.quiet`, the output of the command will not print as it runs, but you still read it in Elm if you read the `Stream` (instead of using [`Stream.run`](#run)).

There are 3 ways to handle the output of a command:

1.  Read the output but don't print
2.  Print the output but don't read
3.  Ignore the output

To read the output (1), use [`Stream.read`](#read) or [`Stream.readJson`](#readJson). This will give you the output as a String or JSON object.
Regardless of whether you use `BackendTask.quiet`, the output will be read and returned to Elm.

To let the output from the command natively print to the console (2), use [`Stream.run`](#run) without setting `BackendTask.quiet`. Based on
the command's `withOutput` configuration, either stderr, stdout, or both will print to the console. The native output will
sometimes be treated more like running the command directly in the terminal, for example `elm make` will print progress
messages which will be cleared and updated in place.

To ignore the output (3), use [`Stream.run`](#run) with `BackendTask.quiet`. This will run the command without printing anything to the console.
You can also use [`Stream.read`](#read) and ignore the captured output, but this is less efficient than using `BackendTask.quiet` with `Stream.run`.


## Compression Helpers

    module CompressionDemo exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "elm.json"
                |> Stream.pipe Stream.gzip
                |> Stream.pipe (Stream.fileWrite "elm.json.gz")
                |> Stream.run
                |> BackendTask.andThen
                    (\_ ->
                        Stream.fileRead "elm.json.gz"
                            |> Stream.pipe Stream.unzip
                            |> Stream.pipe Stream.stdout
                            |> Stream.run
                    )
            )

@docs gzip, unzip


## Custom Streams

[`BackendTask.Custom`](BackendTask-Custom) lets you define custom `BackendTask`s from async NodeJS functions in your `custom-backend-task` file.
Similarly, you can define custom streams with async functions in your `custom-backend-task` file, returning native NodeJS Streams, and optionally functions to extract metadata.

```js
import { Writable, Transform, Readable } from "node:stream";

export async function upperCaseStream(input, { cwd, env, quiet }) {
  return {
    metadata: () => "Hi! I'm metadata from upperCaseStream!",
    stream: new Transform({
      transform(chunk, encoding, callback) {
        callback(null, chunk.toString().toUpperCase());
      },
    }),
  };
}

export async function customReadStream(input) {
  return new Readable({
    read(size) {
      this.push("Hello from customReadStream!");
      this.push(null);
    },
  });
}

export async function customWriteStream(input, { cwd, env, quiet }) {
  return {
    stream: new Writable({
      write(chunk, encoding, callback) {
        console.error("...received chunk...");
        console.log(chunk.toString());
        callback();
      },
    }),
    metadata: () => {
      return "Hi! I'm metadata from customWriteStream!";
    },
  };
}
```

    module CustomStreamDemo exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.customRead "customReadStream" Encode.null
                |> Stream.pipe (Stream.customDuplex "upperCaseStream" Encode.null)
                |> Stream.pipe (Stream.customWrite "customWriteStream" Encode.null)
                |> Stream.run
            )

    To extract the metadata from the custom stream, you can use the `...WithMeta` functions:

    module CustomStreamDemoWithMeta exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.customReadWithMeta "customReadStream" Encode.null Decode.succeed
                |> Stream.pipe (Stream.customTransformWithMeta "upperCaseStream" Encode.null Decode.succeed)
                |> Stream.readMetadata
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\metadata ->
                        Script.log ("Metadata: " ++ metadata)
                    )
            )
        --> Script.log "Metadata: Hi! I'm metadata from upperCaseStream!"

@docs customRead, customWrite, customDuplex


### With Metadata Decoders

@docs customReadWithMeta, customTransformWithMeta, customWriteWithMeta

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body)
import BackendTask.Internal.Request
import Base64
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody
import RequestsAndPending
import TerminalText


{-| Once you've defined a `Stream`, it can be turned into a `BackendTask` that will run it (and optionally read its output and metadata).
-}
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


{-| The `stdin` from the process. When you execute an `elm-pages` script, this will be the value that is piped in to it. For example, given this script module:

    module CountLines exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.stdin
                |> Stream.read
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\{ body } ->
                        body
                            |> String.lines
                            |> List.length
                            |> String.fromInt
                            |> Script.log
                    )
            )

If you run the script without any stdin, it will wait until stdin is closed.

```shell
elm-pages run script/src/CountLines.elm
# pressing ctrl-d (or your platform-specific way of closing stdin) will print the number of lines in the input
```

Or you can pipe to it and it will read that input:

```shell
ls | elm-pages run script/src/CountLines.elm
# prints the number of files in the current directory
```

-}
stdin : Stream () () { read : (), write : Never }
stdin =
    single unit "stdin" []


{-| Streaming through to stdout can be a convenient way to print a pipeline directly without going through to Elm.

    module UnzipFile exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "data.gzip.txt"
                |> Stream.pipe Stream.unzip
                |> Stream.pipe Stream.stdout
                |> Stream.run
                |> BackendTask.allowFatal
            )

-}
stdout : Stream () () { read : Never, write : () }
stdout =
    single unit "stdout" []


{-| Similar to [`stdout`](#stdout), but writes to `stderr` instead.
-}
stderr : Stream () () { read : Never, write : () }
stderr =
    single unit "stderr" []


{-| Open a file's contents as a Stream.

    module ReadFile exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "elm.json"
                |> Stream.readJson (Decode.field "source-directories" (Decode.list Decode.string))
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\{ body } ->
                        Script.log
                            ("The source directories are: "
                                ++ String.join ", " body
                            )
                    )
            )

If you want to read a file but don't need to use any of the other Stream functions, you can use [`BackendTask.File.read`](BackendTask-File#rawFile) instead.

-}
fileRead : String -> Stream () () { read : (), write : Never }
fileRead path =
    -- TODO revisit the error type instead of ()?
    single unit "fileRead" [ ( "path", Encode.string path ) ]


{-| Write a Stream to a file.

    module WriteFile exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "logs.txt"
                |> Stream.pipe (Stream.command "grep" [ "error" ])
                |> Stream.pipe (Stream.fileWrite "errors.txt")
            )

-}
fileWrite : String -> Stream () () { read : Never, write : () }
fileWrite path =
    single unit "fileWrite" [ ( "path", Encode.string path ) ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `ReadableStream` it returns.
-}
customRead : String -> Encode.Value -> Stream () () { read : (), write : Never }
customRead name input =
    single unit
        "customRead"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `WritableStream` it returns.
-}
customWrite : String -> Encode.Value -> Stream () () { read : Never, write : () }
customWrite name input =
    single unit
        "customWrite"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `DuplexStream` it returns.
-}
customReadWithMeta :
    String
    -> Encode.Value
    -> Decoder (Result { fatal : FatalError, recoverable : error } metadata)
    -> Stream error metadata { read : (), write : Never }
customReadWithMeta name input decoder =
    single ( "", decoder )
        "customRead"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `WritableStream` and metadata function it returns.
-}
customWriteWithMeta :
    String
    -> Encode.Value
    -> Decoder (Result { fatal : FatalError, recoverable : error } metadata)
    -> Stream error metadata { read : Never, write : () }
customWriteWithMeta name input decoder =
    single ( "", decoder )
        "customWrite"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `DuplexStream` and metadata function it returns.
-}
customTransformWithMeta :
    String
    -> Encode.Value
    -> Decoder (Result { fatal : FatalError, recoverable : error } metadata)
    -> Stream error metadata { read : (), write : () }
customTransformWithMeta name input decoder =
    single ( "", decoder )
        "customDuplex"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Calls an async function from your `custom-backend-task` definitions and uses the NodeJS `DuplexStream` it returns.
-}
customDuplex : String -> Encode.Value -> Stream () () { read : (), write : () }
customDuplex name input =
    single unit
        "customDuplex"
        [ ( "portName", Encode.string name )
        , ( "input", input )
        ]


{-| Transforms the input with gzip compression.

Under the hood this builds a Stream using Node's [`zlib.createGzip`](https://nodejs.org/api/zlib.html#zlibcreategzipoptions).

-}
gzip : Stream () () { read : (), write : () }
gzip =
    single unit "gzip" []


{-| Transforms the input by auto-detecting the header and decompressing either a Gzip- or Deflate-compressed stream.

Under the hood, this builds a Stream using Node's [`zlib.createUnzip`](https://nodejs.org/api/zlib.html#zlibcreateunzip).

-}
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


{-| Uses a regular HTTP request body (not a `Stream`). Streams the HTTP response body.

If you want to pass a stream as the request body, use [`httpWithInput`](#httpWithInput) instead.

If you don't need to stream the response body, you can use the functions from [`BackendTask.Http`](BackendTask-Http) instead.

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
        |> Decode.map
            (\thing ->
                toBadResponse (Just thing) RequestsAndPending.WhateverBody
                    |> Maybe.map
                        (\httpError ->
                            FatalError.recoverable
                                (errorToString httpError)
                                httpError
                                |> Err
                        )
                    |> Maybe.withDefault (Ok thing)
            )
    )


{-| You can build up a pipeline of streams by using the `pipe` function.

The stream you are piping to must be writable (`{ write : () }`),
and the stream you are piping from must be readable (`{ read : () }`).

    module HelloWorld exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fromString "Hello, World!"
                |> Stream.stdout
                |> Stream.run
            )

-}
pipe :
    Stream errorTo metaTo { read : toReadable, write : () }
    -> Stream errorFrom metaFrom { read : (), write : fromWriteable }
    -> Stream errorTo metaTo { read : toReadable, write : fromWriteable }
pipe (Stream decoderTo to) (Stream _ from) =
    Stream decoderTo (from ++ to)


{-| Gives a `BackendTask` to execute the `Stream`, ignoring its body and metadata.

This is useful if you only want the side-effect from the `Stream` and don't need to programmatically use its
output. For example, if the end result you want is:

  - Printing to the console
  - Writing to a file
  - Making an HTTP request

If you need to read the output of the `Stream`, use [`read`](#read), [`readJson`](#readJson), or [`readMetadata`](#readMetadata) instead.

-}
run : Stream error metadata kind -> BackendTask FatalError ()
run stream =
    -- TODO give access to recoverable error here instead of just FatalError
    BackendTask.Internal.Request.request
        { name = "stream"
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "none")
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
                    , Decode.succeed (Ok ())
                    ]
                )
        }
        |> BackendTask.andThen BackendTask.fromResult
        |> BackendTask.allowFatal


pipelineEncoder : Stream error metadata kind -> String -> Encode.Value
pipelineEncoder (Stream _ parts) kind =
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


{-| A handy way to turn either a hardcoded String, or any other value from Elm into a Stream.

    module HelloWorld exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fromString "Hello, World!"
                |> Stream.stdout
                |> Stream.run
                |> BackendTask.allowFatal
            )

A more programmatic use of `fromString` to use the result of a previous `BackendTask` to a `Stream`:

    module HelloWorld exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Glob.fromString "src/**/*.elm"
                |> BackendTask.andThen
                    (\elmFiles ->
                        elmFiles
                            |> String.join ", "
                            |> Stream.fromString
                            |> Stream.pipe Stream.stdout
                            |> Stream.run
                    )
            )

-}
fromString : String -> Stream () () { read : (), write : Never }
fromString string =
    single unit "fromString" [ ( "string", Encode.string string ) ]


{-| Running or reading a `Stream` can give one of two kinds of error:

  - `StreamError String` - when something in the middle of the stream fails
  - `CustomError error body` - when the `Stream` fails with a custom error

A `CustomError` can only come from the final part of the stream.

You can define your own custom errors by decoding metadata to an `Err` in the `...WithMeta` helpers.

-}
type Error error body
    = StreamError String
    | CustomError error (Maybe body)


{-| Read the body of the `Stream` as text.
-}
read :
    Stream error metadata { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : Error error String } { metadata : metadata, body : String }
read ((Stream ( _, decoder ) _) as stream) =
    BackendTask.Internal.Request.request
        { name = "stream"

        -- TODO pass in `decoderName` to pipelineEncoder
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "text")
        , expect =
            BackendTask.Http.expectJson
                (decodeLog
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
                        , Decode.succeed
                            (Err
                                (FatalError.recoverable
                                    { title = "Stream Error", body = "No metadata" }
                                    (StreamError "No metadata")
                                )
                            )
                        ]
                    )
                )
        }
        |> BackendTask.andThen BackendTask.fromResult


{-| Ignore the body of the `Stream`, while capturing the metadata from the final part of the Stream.
-}
readMetadata :
    Stream error metadata { read : read, write : write }
    -> BackendTask { fatal : FatalError, recoverable : Error error String } metadata
readMetadata ((Stream ( _, decoder ) _) as stream) =
    BackendTask.Internal.Request.request
        { name = "stream"

        -- TODO pass in `decoderName` to pipelineEncoder
        , body = BackendTask.Http.jsonBody (pipelineEncoder stream "none")
        , expect =
            BackendTask.Http.expectJson
                (decodeLog
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
                            |> Decode.map
                                (\result ->
                                    case result of
                                        Ok metadata ->
                                            Ok metadata

                                        Err error ->
                                            error |> mapRecoverable Nothing |> Err
                                )
                        , Decode.succeed
                            (Err
                                (FatalError.recoverable
                                    { title = "Stream Error", body = "No metadata" }
                                    (StreamError "No metadata")
                                )
                            )
                        ]
                    )
                )
        }
        |> BackendTask.andThen BackendTask.fromResult


decodeLog : Decoder a -> Decoder a
decodeLog decoder =
    Decode.value
        |> Decode.andThen
            (\_ ->
                --let
                --    _ =
                --        Debug.log "VALUE" (Encode.encode 2 value)
                --in
                decoder
            )


{-| Read the body of the `Stream` as JSON.

    module ReadJson exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Json.Decode as Decode
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "data.json"
                |> Stream.readJson (Decode.field "name" Decode.string)
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\{ body } ->
                        Script.log ("The name is: " ++ body)
                    )
            )

-}
readJson :
    Decoder value
    -> Stream error metadata { read : (), write : write }
    -> BackendTask { fatal : FatalError, recoverable : Error error value } { metadata : metadata, body : value }
readJson decoder ((Stream ( _, metadataDecoder ) _) as stream) =
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


{-| Run a command (or `child_process`). The command's output becomes the body of the `Stream`.
-}
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


{-| Pass in custom [`CommandOptions`](#CommandOptions) to configure the behavior of the command.

For example, `grep` will return a non-zero status code if it doesn't find any matches. To ignore the non-zero status code and proceed with
empty output, you can use `allowNon0Status`.

    module GrepErrors exposing (run)

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script exposing (Script)

    run : Script
    run =
        Script.withoutCliOptions
            (Stream.fileRead "log.txt"
                |> Stream.pipe
                    (Stream.commandWithOptions
                        (Stream.defaultCommandOptions |> Stream.allowNon0Status)
                        "grep"
                        [ "error" ]
                    )
                |> Stream.pipe Stream.stdout
                |> Stream.run
            )

-}
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


{-| Configuration for [`commandWithOptions`](#commandWithOptions).
-}
type CommandOptions
    = CommandOptions CommandOptions_


type alias CommandOptions_ =
    { output : StderrOutput
    , allowNon0Status : Bool
    , timeoutInMs : Maybe Int
    }


{-| The default options that are used for [`command`](#command). Used to build up `CommandOptions`
to pass in to [`commandWithOptions`](#commandWithOptions).
-}
defaultCommandOptions : CommandOptions
defaultCommandOptions =
    CommandOptions
        { output = PrintStderr
        , allowNon0Status = False
        , timeoutInMs = Nothing
        }


{-| Configure the [`StderrOutput`](#StderrOutput) behavior.
-}
withOutput : StderrOutput -> CommandOptions -> CommandOptions
withOutput output (CommandOptions cmd) =
    CommandOptions { cmd | output = output }


{-| By default, the `Stream` will halt with an error if a command returns a non-zero status code.

With `allowNon0Status`, the stream will continue without an error if the command returns a non-zero status code.

-}
allowNon0Status : CommandOptions -> CommandOptions
allowNon0Status (CommandOptions cmd) =
    CommandOptions { cmd | allowNon0Status = True }


{-| By default, commands do not have a timeout. This will set the timeout, in milliseconds, for the given command. If that duration is exceeded,
the `Stream` will fail with an error.
-}
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


{-| The output configuration for [`withOutput`](#withOutput). The default is `PrintStderr`.

  - `PrintStderr` - Print (but do not pass along) the `stderr` output of the command. Only `stdout` will be passed along as the body of the stream.
  - `IgnoreStderr` - Ignore the `stderr` output of the command, only include `stdout`
  - `MergeStderrAndStdout` - Both `stderr` and `stdout` will be passed along as the body of the stream.
  - `StderrInsteadOfStdout` - Only `stderr` will be passed along as the body of the stream. `stdout` will be ignored.

-}
type StderrOutput
    = PrintStderr
    | IgnoreStderr
    | MergeStderrAndStdout
    | StderrInsteadOfStdout


toBadResponse : Maybe BackendTask.Http.Metadata -> RequestsAndPending.ResponseBody -> Maybe BackendTask.Http.Error
toBadResponse maybeResponse body =
    case maybeResponse of
        Just response ->
            if not (response.statusCode >= 200 && response.statusCode < 300) then
                case body of
                    RequestsAndPending.StringBody s ->
                        BackendTask.Http.BadStatus
                            { url = response.url
                            , statusCode = response.statusCode
                            , statusText = response.statusText
                            , headers = response.headers
                            }
                            s
                            |> Just

                    RequestsAndPending.BytesBody bytes ->
                        BackendTask.Http.BadStatus
                            { url = response.url
                            , statusCode = response.statusCode
                            , statusText = response.statusText
                            , headers = response.headers
                            }
                            (Base64.fromBytes bytes |> Maybe.withDefault "")
                            |> Just

                    RequestsAndPending.JsonBody value ->
                        BackendTask.Http.BadStatus
                            { url = response.url
                            , statusCode = response.statusCode
                            , statusText = response.statusText
                            , headers = response.headers
                            }
                            (Encode.encode 0 value)
                            |> Just

                    RequestsAndPending.WhateverBody ->
                        BackendTask.Http.BadStatus
                            { url = response.url
                            , statusCode = response.statusCode
                            , statusText = response.statusText
                            , headers = response.headers
                            }
                            ""
                            |> Just

            else
                Nothing

        Nothing ->
            Nothing


errorToString : BackendTask.Http.Error -> { title : String, body : String }
errorToString error =
    { title = "HTTP Error"
    , body =
        (case error of
            BackendTask.Http.BadUrl string ->
                [ TerminalText.text ("BadUrl " ++ string)
                ]

            BackendTask.Http.Timeout ->
                [ TerminalText.text "Timeout"
                ]

            BackendTask.Http.NetworkError ->
                [ TerminalText.text "NetworkError"
                ]

            BackendTask.Http.BadStatus metadata _ ->
                [ TerminalText.text "BadStatus: "
                , TerminalText.red (String.fromInt metadata.statusCode)
                , TerminalText.text (" " ++ metadata.statusText)
                ]

            BackendTask.Http.BadBody _ string ->
                [ TerminalText.text ("BadBody: " ++ string)
                ]
        )
            |> TerminalText.toString
    }
