module Pages.Internal.Platform.StaticResponses exposing (FinishKind(..), NextStep(..), StaticResponses, batchUpdate, empty, nextStep, renderApiRequest, renderSingleRoute, staticResponsesThing)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)


type StaticResponses a
    = ApiRequest (StaticHttpResult a)
    | StaticResponses (StaticHttpResult a)
    | CheckIfHandled (DataSource (Maybe NotFoundReason)) (StaticHttpResult a)


type StaticHttpResult a
    = NotFetched (DataSource a) (Dict String (Result () String))


empty : a -> StaticResponses a
empty a =
    StaticResponses
        (NotFetched (DataSource.succeed a) Dict.empty)


renderSingleRoute :
    DataSource a
    -> DataSource (Maybe NotFoundReason)
    -> StaticResponses a
renderSingleRoute request cliData =
    CheckIfHandled cliData
        (NotFetched request Dict.empty)


renderApiRequest :
    DataSource response
    -> StaticResponses response
renderApiRequest request =
    ApiRequest (NotFetched request Dict.empty)


staticResponsesThing :
    DataSource response
    -> StaticResponses response
staticResponsesThing request =
    StaticResponses (NotFetched request Dict.empty)


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
    = Continue RequestsAndPending (List HashRequest.Request) (Maybe (List route))
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
            case staticResponses of
                NotFetched request_ _ ->
                    request_

        staticResponses : StaticHttpResult a
        staticResponses =
            case model.staticResponses of
                StaticResponses s ->
                    s

                ApiRequest staticHttpResult ->
                    staticHttpResult

                CheckIfHandled staticHttpResult (NotFetched b _) ->
                    NotFetched
                        (staticHttpResult
                            |> DataSource.andThen
                                (\_ ->
                                    b
                                )
                        )
                        Dict.empty

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

                _ ->
                    ( ( False, Nothing )
                    , []
                    , DataSource.fail "TODO this shouldn't happen"
                    )
    in
    if pendingRequests then
        let
            newAllRawResponses : RequestsAndPending
            newAllRawResponses =
                allRawResponses

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

                    StaticResponses (NotFetched _ _) ->
                        StaticResponses (NotFetched progressedDataSource Dict.empty)

                    CheckIfHandled a b ->
                        -- TODO change this too, or maybe this is fine?
                        --model.staticResponses
                        StaticResponses (NotFetched progressedDataSource Dict.empty)
        in
        ( updatedStaticResponses, Continue newAllRawResponses newThing maybeRoutes )

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
        case model.staticResponses of
            StaticResponses thingy ->
                ( model.staticResponses
                , if List.length allErrors > 0 then
                    FinishedWithErrors allErrors

                  else
                    case completedValue of
                        Just value ->
                            Finish ApiResponse value

                        Nothing ->
                            -- TODO put a real error here
                            FinishedWithErrors []
                )

            ApiRequest _ ->
                ( model.staticResponses
                , if List.length allErrors > 0 then
                    FinishedWithErrors allErrors

                  else
                    case completedValue of
                        Just completed ->
                            Finish ApiResponse completed

                        Nothing ->
                            case completedValue of
                                Just value ->
                                    Finish ApiResponse value

                                Nothing ->
                                    -- TODO put a real error here
                                    FinishedWithErrors []
                )

            CheckIfHandled pageFoundDataSource andThenRequest ->
                let
                    pageFoundResult : Result StaticHttpRequest.Error (Maybe NotFoundReason)
                    pageFoundResult =
                        StaticHttpRequest.resolve
                            pageFoundDataSource
                            allRawResponses
                in
                case pageFoundResult of
                    Ok Nothing ->
                        nextStep { model | staticResponses = StaticResponses andThenRequest } maybeRoutes

                    Ok (Just notFoundReason) ->
                        ( -- TODO is this valid? Avoid this boilerplate with impossible states
                          NotFetched (DataSource.fail "This should never happen") Dict.empty
                            |> StaticResponses
                        , FinishNotFound notFoundReason
                        )

                    Err error_ ->
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
                        ( model.staticResponses
                        , FinishedWithErrors
                            (StaticHttpRequest.toBuildError
                                -- TODO give more fine-grained error reference
                                "get static routes"
                                error_
                                :: failedRequests
                                ++ errors
                            )
                        )
