module Shell exposing (Command(..), binary, command, exec, map, pipe, run, stdout, text, tryJson, tryMap, withQuiet, withTimeout)

import BackendTask exposing (BackendTask)
import Base64
import Bytes exposing (Bytes)
import FatalError exposing (FatalError)
import Json.Decode
import Pages.Script as Script


command : String -> List String -> Command String
command command_ args =
    Command
        { command = [ ( command_, args ) ]
        , quiet = False
        , timeout = Nothing
        , decoder = Just
        }


type Command stdout
    = Command
        { command : List ( String, List String )
        , quiet : Bool
        , timeout : Maybe Int
        , decoder : String -> Maybe stdout
        }


map : (a -> b) -> Command a -> Command b
map mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Maybe.map mapFn
        }


tryMap : (a -> Maybe b) -> Command a -> Command b
tryMap mapFn (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = command_.decoder >> Maybe.andThen mapFn
        }


binary : Command String -> Command Bytes
binary (Command command_) =
    Command
        { command = command_.command
        , quiet = command_.quiet
        , timeout = command_.timeout
        , decoder = Base64.toBytes
        }


withQuiet : Command stdout -> Command stdout
withQuiet (Command options_) =
    Command { options_ | quiet = True }


withTimeout : Int -> Command stdout -> Command stdout
withTimeout timeout (Command command_) =
    Command { command_ | timeout = Just timeout }


text : Command stdout -> BackendTask FatalError String
text command_ =
    command_
        |> withQuiet
        |> run
        |> BackendTask.map .stdout
        |> BackendTask.allowFatal



--redirect : Command -> ???


stdout : Command stdout -> BackendTask FatalError stdout
stdout ((Command command_) as fullCommand) =
    fullCommand
        |> run
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\output ->
                case output.stdout |> command_.decoder of
                    Just okStdout ->
                        BackendTask.succeed okStdout

                    Nothing ->
                        BackendTask.fail (FatalError.fromString "")
            )


pipe : Command to -> Command from -> Command to
pipe (Command to) (Command from) =
    Command
        { command = from.command ++ to.command
        , quiet = to.quiet
        , timeout = to.timeout
        , decoder = to.decoder
        }


run :
    Command stdout
    ->
        BackendTask
            { fatal : FatalError
            , recoverable : { output : String, stderr : String, stdout : String, statusCode : Int }
            }
            { output : String, stderr : String, stdout : String }
run (Command options_) =
    Script.shell options_.command


exec : Command stdout -> BackendTask FatalError ()
exec (Command options_) =
    Script.shell options_.command
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())


example : BackendTask FatalError String
example =
    command "ls" [] |> text


tryJson : Json.Decode.Decoder a -> Command String -> Command a
tryJson jsonDecoder command_ =
    command_
        |> tryMap
            (\jsonString ->
                Json.Decode.decodeString jsonDecoder jsonString
                    |> Result.toMaybe
            )
