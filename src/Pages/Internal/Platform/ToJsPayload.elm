module Pages.Internal.Platform.ToJsPayload exposing (..)

import BuildError
import Dict exposing (Dict)
import Pages.Manifest as Manifest
import TerminalText as Terminal


type ToJsPayload pathKey
    = Errors String
    | Success (ToJsSuccessPayload pathKey)


type alias ToJsSuccessPayload pathKey =
    { pages : Dict String (Dict String String)
    , manifest : Manifest.Config pathKey
    , filesToGenerate : List FileToGenerate
    , staticHttpCache : Dict String String
    , errors : List String
    }


type alias FileToGenerate =
    { path : List String
    , content : String
    }


toJsPayload :
    Dict String (Dict String String)
    -> Manifest.Config pathKey
    -> List FileToGenerate
    -> Dict String (Maybe String)
    -> List { title : String, message : List Terminal.Text, fatal : Bool }
    -> ToJsPayload pathKey
toJsPayload encodedStatic manifest generated allRawResponses allErrors =
    if allErrors |> List.filter .fatal |> List.isEmpty then
        Success
            (ToJsSuccessPayload
                encodedStatic
                manifest
                generated
                (allRawResponses
                    |> Dict.toList
                    |> List.filterMap
                        (\( key, maybeValue ) ->
                            maybeValue
                                |> Maybe.map (\value -> ( key, value ))
                        )
                    |> Dict.fromList
                )
                (List.map BuildError.errorToString allErrors)
            )

    else
        Errors <| BuildError.errorsToString allErrors
