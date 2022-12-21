module Pages.Internal.Platform.StaticResponses exposing (NextStep(..), batchUpdate, empty, nextStep, renderApiRequest)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import List.Extra
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)


empty : a -> DataSource a
empty a =
    DataSource.succeed a


renderApiRequest :
    DataSource response
    -> DataSource response
renderApiRequest request =
    request


batchUpdate :
    List
        { request : HashRequest.Request
        , response : RequestsAndPending.Response
        }
    ->
        { model
            | staticResponses : DataSource a
            , allRawResponses : RequestsAndPending
        }
    ->
        { model
            | staticResponses : DataSource a
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
    = Continue (List HashRequest.Request) (StaticHttpRequest.RawRequest value)
    | Finish value
    | FinishedWithErrors (List BuildError)


nextStep :
    { model
        | staticResponses : DataSource a
        , errors : List BuildError
        , allRawResponses : RequestsAndPending
    }
    -> NextStep route a
nextStep ({ allRawResponses, errors } as model) =
    let
        staticRequestsStatus : StaticHttpRequest.Status a
        staticRequestsStatus =
            allRawResponses
                |> StaticHttpRequest.cacheRequestResolution model.staticResponses

        ( ( pendingRequests, completedValue ), urlsToPerform, progressedDataSource ) =
            case staticRequestsStatus of
                StaticHttpRequest.Incomplete newUrlsToFetch nextReq ->
                    ( ( True, Nothing ), newUrlsToFetch, nextReq )

                StaticHttpRequest.Complete value ->
                    ( ( False, Just value )
                    , []
                    , DataSource.succeed value
                    )

                StaticHttpRequest.HasPermanentError _ _ ->
                    ( ( False, Nothing )
                    , []
                    , DataSource.fail "TODO this shouldn't happen"
                    )
    in
    if pendingRequests then
        let
            newThing : List HashRequest.Request
            newThing =
                urlsToPerform
                    |> List.Extra.uniqueBy HashRequest.hash
        in
        Continue newThing progressedDataSource

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
        if List.length allErrors > 0 then
            FinishedWithErrors allErrors

        else
            case completedValue of
                Just completed ->
                    Finish completed

                Nothing ->
                    FinishedWithErrors
                        [ BuildError.internal "TODO error message"
                        ]
