module BackendTask.Shell exposing
    ( Command
    , sh
    , command, exec
    , withTimeout
    , stdout, run, text
    , pipe
    , binary, tryJson, map, tryMap
    )

{-|

@docs Command


## Executing Commands

@docs sh

@docs command, exec

@docs withTimeout


## Capturing Output

@docs stdout, run, text


## Piping Commands

@docs pipe


## Output Decoders

@docs binary, tryJson, map, tryMap

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Base64
import Bytes exposing (Bytes)
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


{-| -}
command : String -> List String -> Command String
command command_ args =
    Command
        { command = [ subCommand command_ args ]
        , quiet = False
        , timeout = Nothing
        , decoder = Ok
        }


subCommand : String -> List String -> SubCommand
subCommand command_ args =
    { command = command_
    , args = args
    , timeout = Nothing
    }


type alias SubCommand =
    { command : String
    , args : List String
    , timeout : Maybe Int
    }


{-| -}
type Command stdout
    = Command
        { command : List SubCommand
        , quiet : Bool
        , timeout : Maybe Int
        , decoder : String -> Result String stdout
        }


{-| -}
map : (a -> b) -> Command a -> Command b
map mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Result.map mapFn
        }


{-| -}
tryMap : (a -> Result String b) -> Command a -> Command b
tryMap mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Result.andThen mapFn
        }


{-| -}
binary : Command String -> Command Bytes
binary (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = Base64.toBytes >> Result.fromMaybe "Failed to decode base64 output."
        }


{-| Applies to each individual command in the pipeline.
-}
withTimeout : Int -> Command stdout -> Command stdout
withTimeout timeout (Command command_) =
    Command { command_ | timeout = Just timeout }


{-| -}
text : Command stdout -> BackendTask FatalError String
text command_ =
    command_
        |> run
        |> BackendTask.map .stdout
        |> BackendTask.quiet
        |> BackendTask.allowFatal



--redirect : Command -> ???


{-| -}
stdout : Command stdout -> BackendTask FatalError stdout
stdout ((Command command_) as fullCommand) =
    fullCommand
        |> run
        |> BackendTask.quiet
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\output ->
                case output.stdout |> command_.decoder of
                    Ok okStdout ->
                        BackendTask.succeed okStdout

                    Err message ->
                        BackendTask.fail
                            (FatalError.build
                                { title = "stdout decoder failed"
                                , body = "The stdout decoder failed with the following message: \n\n" ++ message
                                }
                            )
            )


{-| -}
pipe : Command to -> Command from -> Command to
pipe (Command to) (Command from) =
    Command
        { command = from.command ++ to.command
        , quiet = to.quiet
        , timeout = to.timeout
        , decoder = to.decoder
        }


{-| -}
run :
    Command stdout
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : { output : String, stderr : String, stdout : String, statusCode : Int }
            }
            { output : String, stderr : String, stdout : String }
run (Command options_) =
    shell__ options_.command True


{-| -}
exec : Command stdout -> BackendTask FatalError ()
exec (Command options_) =
    shell__ options_.command False
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())


{-| -}
tryJson : Decoder a -> Command String -> Command a
tryJson jsonDecoder command_ =
    command_
        |> tryMap
            (\jsonString ->
                jsonString
                    |> Decode.decodeString jsonDecoder
                    |> Result.mapError Decode.errorToString
            )


{-| -}
sh : String -> List String -> BackendTask FatalError ()
sh command_ args =
    command command_ args |> exec


{-| -}
shell__ :
    List SubCommand
    -> Bool
    ->
        BackendTask
            { fatal : FatalError
            , recoverable :
                { output : String
                , stderr : String
                , stdout : String
                , statusCode : Int
                }
            }
            { output : String
            , stderr : String
            , stdout : String
            }
shell__ commandsAndArgs captureOutput =
    BackendTask.Internal.Request.request
        { name = "shell"
        , body = BackendTask.Http.jsonBody (commandsAndArgsEncoder commandsAndArgs captureOutput)
        , expect = BackendTask.Http.expectJson commandDecoder
        }
        |> BackendTask.andThen
            (\rawOutput ->
                if rawOutput.exitCode == 0 then
                    BackendTask.succeed
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        }

                else
                    FatalError.recoverable { title = "Shell command error", body = "Exit status was " ++ String.fromInt rawOutput.exitCode }
                        { output = rawOutput.output
                        , stderr = rawOutput.stderr
                        , stdout = rawOutput.stdout
                        , statusCode = rawOutput.exitCode
                        }
                        |> BackendTask.fail
            )


commandsAndArgsEncoder : List SubCommand -> Bool -> Encode.Value
commandsAndArgsEncoder commandsAndArgs captureOutput =
    Encode.object
        [ ( "captureOutput", Encode.bool captureOutput )
        , ( "commands"
          , Encode.list
                (\sub ->
                    Encode.object
                        [ ( "command", Encode.string sub.command )
                        , ( "args", Encode.list Encode.string sub.args )
                        , ( "timeout", sub.timeout |> nullable Encode.int )
                        ]
                )
                commandsAndArgs
          )
        ]


nullable : (a -> Encode.Value) -> Maybe a -> Encode.Value
nullable encoder =
    Maybe.map encoder >> Maybe.withDefault Encode.null


type alias RawOutput =
    { exitCode : Int
    , output : String
    , stderr : String
    , stdout : String
    }


commandDecoder : Decoder RawOutput
commandDecoder =
    Decode.map4 RawOutput
        (Decode.field "errorCode" Decode.int)
        (Decode.field "output" Decode.string)
        (Decode.field "stderrOutput" Decode.string)
        (Decode.field "stdoutOutput" Decode.string)
