port module Main exposing (main)

import Json.Decode as Decode
import Lcov
import Lcov.Decode exposing (decodeCoverageData)


port input : (Decode.Value -> msg) -> Sub msg


port output : String -> Cmd msg


type Msg
    = Received Decode.Value


main : Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update =
            \(Received val) _ ->
                case Decode.decodeValue decodeCoverageData val of
                    Ok modules ->
                        ( (), output (Lcov.generate modules) )

                    Err err ->
                        ( (), output ("ERROR: " ++ Decode.errorToString err) )
        , subscriptions = \_ -> input Received
        }
