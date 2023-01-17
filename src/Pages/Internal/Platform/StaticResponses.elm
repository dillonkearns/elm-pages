module Pages.Internal.Platform.StaticResponses exposing (NextStep(..), empty, nextStep, renderApiRequest)

import BackendTask exposing (BackendTask)
import BuildError exposing (BuildError)
import FatalError exposing (FatalError)
import List.Extra
import Pages.Internal.FatalError
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText


empty : a -> BackendTask FatalError a
empty a =
    BackendTask.succeed a


renderApiRequest :
    BackendTask FatalError response
    -> BackendTask FatalError response
renderApiRequest request =
    request


type NextStep route value
    = Continue (List HashRequest.Request) (StaticHttpRequest.RawRequest FatalError value)
    | Finish value
    | FinishedWithErrors (List BuildError)


nextStep :
    RequestsAndPending
    -> BackendTask FatalError a
    ->
        { model
            | errors : List BuildError
        }
    -> NextStep route a
nextStep allRawResponses staticResponses { errors } =
    let
        staticRequestsStatus : StaticHttpRequest.Status FatalError a
        staticRequestsStatus =
            allRawResponses
                |> StaticHttpRequest.cacheRequestResolution staticResponses

        ( ( pendingRequests, completedValue ), urlsToPerform, progressedBackendTask ) =
            case staticRequestsStatus of
                StaticHttpRequest.Incomplete newUrlsToFetch nextReq ->
                    ( ( True, Nothing ), newUrlsToFetch, nextReq )

                StaticHttpRequest.Complete (Err error) ->
                    ( ( False, Just (Err error) )
                    , []
                    , BackendTask.fail error
                    )

                StaticHttpRequest.Complete (Ok value) ->
                    ( ( False, Just (Ok value) )
                    , []
                    , BackendTask.succeed value
                    )

                StaticHttpRequest.HasPermanentError _ ->
                    ( ( False, Nothing )
                    , []
                    , BackendTask.fail (FatalError.fromString "TODO this shouldn't happen")
                    )
    in
    if pendingRequests then
        let
            newThing : List HashRequest.Request
            newThing =
                urlsToPerform
                    |> List.Extra.uniqueBy HashRequest.hash
        in
        Continue newThing progressedBackendTask

    else
        let
            allErrors : List BuildError
            allErrors =
                let
                    failedRequests : List BuildError
                    failedRequests =
                        let
                            maybePermanentError : Maybe StaticHttpRequest.Error
                            maybePermanentError =
                                case staticRequestsStatus of
                                    StaticHttpRequest.HasPermanentError theError ->
                                        Just theError

                                    _ ->
                                        Nothing

                            decoderErrors : List BuildError
                            decoderErrors =
                                maybePermanentError
                                    |> Maybe.map (StaticHttpRequest.toBuildError "TODO PATH")
                                    |> Maybe.map List.singleton
                                    |> Maybe.withDefault []
                        in
                        decoderErrors
                in
                errors ++ failedRequests
        in
        if List.length allErrors > 0 then
            FinishedWithErrors allErrors

        else
            case completedValue of
                Just (Ok completed) ->
                    Finish completed

                Just (Err (Pages.Internal.FatalError.FatalError buildError)) ->
                    FinishedWithErrors
                        [ { title = buildError.title |> String.toUpper
                          , path = "" -- TODO include path here
                          , message = buildError.body |> TerminalText.fromAnsiString
                          , fatal = True
                          }
                        ]

                Nothing ->
                    FinishedWithErrors
                        [ BuildError.internal "TODO error message"
                        ]
