module Pages.Internal.Platform.StaticResponses exposing (FinishKind(..), NextStep(..), StaticResponses, batchUpdate, empty, nextStep, renderApiRequest)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)


type StaticResponses a
    = ApiRequest (StaticHttpResult a)


type StaticHttpResult a
    = NotFetched (DataSource a) (Dict String (Result () String))


empty : a -> StaticResponses a
empty a =
    ApiRequest
        (NotFetched (DataSource.succeed a) Dict.empty)


renderApiRequest :
    DataSource response
    -> StaticResponses response
renderApiRequest request =
    ApiRequest (NotFetched request Dict.empty)


batchUpdate :
    List
        { request : HashRequest.Request
        , response : RequestsAndPending.Response
        }
    ->
        { model
            | staticResponses : StaticResponses a
            , allRawResponses : RequestsAndPending
        }
    ->
        { model
            | staticResponses : StaticResponses a
            , allRawResponses : RequestsAndPending
        }
batchUpdate newEntries model =
    { model
        | allRawResponses =
            newEntries
                |> List.map
                    (\{ request, response } ->
                        ( HashRequest.hash request
                        , Just response
                        )
                    )
                |> Dict.fromList
    }


type NextStep route value
    = Continue (List HashRequest.Request) (Maybe (List route))
    | Finish (FinishKind route) value
    | FinishNotFound NotFoundReason
    | FinishedWithErrors (List BuildError)


type FinishKind route
    = ApiResponse
    | Errors (List BuildError)


nextStep :
    { model
        | staticResponses : StaticResponses a
        , errors : List BuildError
        , allRawResponses : RequestsAndPending
    }
    -> Maybe (List route)
    -> ( StaticResponses a, NextStep route a )
nextStep ({ allRawResponses, errors } as model) maybeRoutes =
    let
        staticRequestsStatus : StaticHttpRequest.Status a
        staticRequestsStatus =
            allRawResponses
                |> StaticHttpRequest.cacheRequestResolution request

        request : DataSource a
        request =
            case model.staticResponses of
                ApiRequest (NotFetched request_ _) ->
                    request_

        ( ( pendingRequests, completedValue ), urlsToPerform, progressedDataSource ) =
            case staticRequestsStatus of
                StaticHttpRequest.Incomplete newUrlsToFetch nextReq ->
                    ( ( True, Nothing ), newUrlsToFetch, nextReq )

                StaticHttpRequest.Complete value ->
                    -- TODO wire through this completed value and replace the Debug.todo's below
                    ( ( False, Just value )
                    , []
                    , DataSource.succeed value
                    )

                StaticHttpRequest.HasPermanentError error _ ->
                    ( ( False, Nothing )
                    , []
                    , DataSource.fail "TODO this shouldn't happen"
                    )
    in
    if pendingRequests then
        let
            maskedToUnmasked : Dict String HashRequest.Request
            maskedToUnmasked =
                urlsToPerform
                    |> List.map
                        (\secureUrl ->
                            ( HashRequest.hash secureUrl, secureUrl )
                        )
                    |> Dict.fromList

            newThing : List HashRequest.Request
            newThing =
                maskedToUnmasked
                    |> Dict.values

            updatedStaticResponses : StaticResponses a
            updatedStaticResponses =
                case model.staticResponses of
                    ApiRequest (NotFetched _ _) ->
                        ApiRequest (NotFetched progressedDataSource Dict.empty)
        in
        ( updatedStaticResponses, Continue newThing maybeRoutes )

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
                                    StaticHttpRequest.HasPermanentError theError _ ->
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
        ( model.staticResponses
        , if List.length allErrors > 0 then
            FinishedWithErrors allErrors

          else
            case completedValue of
                Just completed ->
                    Finish ApiResponse completed

                Nothing ->
                    FinishedWithErrors
                        [ BuildError.internal "TODO error message"
                        ]
        )
