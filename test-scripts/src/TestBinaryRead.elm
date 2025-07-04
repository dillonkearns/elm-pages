module TestBinaryRead exposing (run)

import BackendTask
import BackendTask.File
import Bytes
import Bytes.Decode
import FatalError
import Json.Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    BackendTask.File.binaryFile "elm.json"
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\bytes ->
                case Bytes.Decode.decode (Bytes.Decode.string (Bytes.width bytes)) bytes of
                    Nothing ->
                        BackendTask.fail (FatalError.fromString "Failed to decode file as string")

                    Just str ->
                        case Json.Decode.decodeString Json.Decode.value str of
                            Ok _ ->
                                Script.log "elm.json read successfully"

                            Err _ ->
                                BackendTask.fail (FatalError.fromString "Failed to decode file as json")
            )
        |> Script.withoutCliOptions
