module Pages.StaticHttpRequest exposing (Request(..), resolveUrls, urls)

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


resolveUrls : Request value -> Dict String String -> List (Secrets -> Result BuildError String)
resolveUrls request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn rawResponses of
                Ok nextRequest ->
                    let
                        return =
                            urlList ++ resolveUrls nextRequest rawResponses

                        _ =
                            --                            return
                            case nextRequest of
                                Done val ->
                                    ()
                                        |> Debug.log "Nested is Done"

                                _ ->
                                    resolveUrls nextRequest rawResponses
                                        |> List.map Pages.Internal.Secrets.useFakeSecrets
                                        |> Debug.log "NESTED Urls @@@@@"
                                        |> (\_ -> ())
                    in
                    return

                Err error ->
                    let
                        _ =
                            Debug.log "resolveUrls ERROR" error
                    in
                    --                    urlList
                    Debug.todo error

        Done value ->
            []
                |> Debug.log "DONE"
