module Pages.StaticHttpRequest exposing (Request(..), resolve, resolveUrls, urls)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Pages.Internal.Secrets
import Secrets exposing (Secrets)


type Request value
    = Request ( List (Secrets -> Result BuildError String), Dict String String -> Result String (Request value) )
    | Done value


urls : Request value -> List (Secrets -> Result BuildError String)
urls request =
    case request of
        Request ( urlList, lookupFn ) ->
            urlList

        Done value ->
            []


resolve : Request value -> Dict String String -> Result String value
resolve request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn rawResponses of
                Ok nextRequest ->
                    resolve nextRequest rawResponses

                Err error ->
                    Err "TODO error message"

        Done value ->
            Ok value


resolveUrls : Request value -> Dict String String -> ( Bool, List (Secrets -> Result BuildError String) )
resolveUrls request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            let
                _ =
                    Debug.log "!!!!!! resolving" (urlList |> List.map Pages.Internal.Secrets.useFakeSecrets)
            in
            case lookupFn rawResponses of
                Ok nextRequest ->
                    resolveUrls nextRequest rawResponses
                        |> Tuple.mapSecond ((++) urlList)

                Err error ->
                    let
                        _ =
                            --                            Debug.log "!!!!!! ERROR" (urlList |> List.map Pages.Internal.Secrets.useFakeSecrets)
                            Debug.log "!!!!!! ERROR" error
                    in
                    ( False
                    , urlList
                    )

        Done value ->
            let
                _ =
                    Debug.log "!!!!!! Reached DONE!" value
            in
            ( True, [] )
