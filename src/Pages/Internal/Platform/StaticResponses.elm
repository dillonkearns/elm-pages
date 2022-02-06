module Pages.Internal.Platform.StaticResponses exposing (FinishKind(..), NextStep(..), StaticResponses, batchUpdate, empty, nextStep, renderApiRequest, renderSingleRoute)

import ApiRoute
import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import DataSource.Http exposing (RequestDetails)
import Dict exposing (Dict)
import Dict.Extra
import Html exposing (Html)
import HtmlPrinter exposing (htmlToString)
import Internal.ApiRoute exposing (ApiRoute(..))
import Json.Encode
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import Path exposing (Path)
import RequestsAndPending exposing (RequestsAndPending)
import Set exposing (Set)
import TerminalText as Terminal


type StaticResponses
    = ApiRequest StaticHttpResult
    | StaticResponses StaticHttpResult
    | CheckIfHandled (DataSource (Maybe NotFoundReason)) StaticHttpResult StaticHttpResult


type StaticHttpResult
    = NotFetched (DataSource ()) (Dict String (Result () String))


empty : StaticResponses
empty =
    StaticResponses
        (NotFetched (DataSource.succeed ()) Dict.empty)


buildTimeFilesRequest :
    { config
        | apiRoutes :
            (Html Never -> String)
            -> List (ApiRoute.ApiRoute ApiRoute.Response)
    }
    -> DataSource (List (Result String { path : List String, content : String }))
buildTimeFilesRequest config =
    config.apiRoutes htmlToString
        |> List.map
            (\(ApiRoute handler) ->
                handler.buildTimeRoutes
                    |> DataSource.andThen
                        (\paths ->
                            paths
                                |> List.map
                                    (\path ->
                                        handler.matchesToResponse path
                                            |> DataSource.map
                                                (\maybeResponse ->
                                                    case maybeResponse of
                                                        Nothing ->
                                                            Err ""

                                                        Just response ->
                                                            Ok { path = path |> String.split "/", content = response |> Json.Encode.encode 0 }
                                                )
                                    )
                                |> DataSource.combine
                        )
            )
        |> DataSource.combine
        |> DataSource.map List.concat


renderSingleRoute :
    { config
        | routeToPath : route -> List String
    }
    -> { path : Path, frontmatter : route }
    -> DataSource a
    -> DataSource (Maybe NotFoundReason)
    -> StaticResponses
renderSingleRoute config pathAndRoute request cliData =
    CheckIfHandled cliData
        (NotFetched
            (cliData
                |> DataSource.map (\_ -> ())
            )
            Dict.empty
        )
        (NotFetched (DataSource.map (\_ -> ()) request) Dict.empty)


renderApiRequest :
    DataSource response
    -> StaticResponses
renderApiRequest request =
    ApiRequest
        (NotFetched
            (request |> DataSource.map (\_ -> ()))
            Dict.empty
        )


batchUpdate :
    List
        { request : RequestDetails
        , response : String
        }
    ->
        { model
            | staticResponses : StaticResponses
            , allRawResponses : Dict String (Maybe String)
        }
    ->
        { model
            | staticResponses : StaticResponses
            , allRawResponses : Dict String (Maybe String)
        }
batchUpdate newEntries model =
    let
        newResponses : Dict String String
        newResponses =
            newEntries
                |> List.map
                    (\newEntry ->
                        ( HashRequest.hash newEntry.request, newEntry.response )
                    )
                |> Dict.fromList

        updatedAllResponses : Dict String (Maybe String)
        updatedAllResponses =
            Dict.merge
                (\key a -> Dict.insert key (Just a))
                (\key a _ -> Dict.insert key (Just a))
                (\key b -> Dict.insert key b)
                newResponses
                model.allRawResponses
                Dict.empty
    in
    { model
        | allRawResponses = updatedAllResponses
    }


encode : RequestsAndPending -> StaticHttpResult -> Result (List BuildError) RequestsAndPending
encode requestsAndPending staticResponses =
    case staticResponses of
        NotFetched request _ ->
            StaticHttpRequest.strippedResponsesEncode request requestsAndPending
                |> Result.map
                    (Dict.map
                        (\key value ->
                            Just value
                        )
                    )


type NextStep route
    = Continue (Dict String (Maybe String)) (List RequestDetails) (Maybe (List route))
    | Finish (FinishKind route)


type FinishKind route
    = ApiResponse
    | Errors (List BuildError)
    | Page RequestsAndPending


nextStep :
    { config
        | getStaticRoutes : DataSource (List route)
        , routeToPath : route -> List String
        , data : route -> DataSource pageData
        , sharedData : DataSource sharedData
        , site : Maybe (SiteConfig siteData)
        , apiRoutes : (Html Never -> String) -> List (ApiRoute.ApiRoute ApiRoute.Response)
    }
    ->
        { model
            | staticResponses : StaticResponses
            , errors : List BuildError
            , allRawResponses : Dict String (Maybe String)
        }
    -> Maybe (List route)
    -> ( StaticResponses, NextStep route )
nextStep config ({ allRawResponses, errors } as model) maybeRoutes =
    let
        staticResponses : StaticHttpResult
        staticResponses =
            case model.staticResponses of
                StaticResponses s ->
                    s

                ApiRequest staticHttpResult ->
                    staticHttpResult

                CheckIfHandled _ staticHttpResult _ ->
                    staticHttpResult

        pendingRequests : Bool
        pendingRequests =
            case staticResponses of
                NotFetched request rawResponses ->
                    let
                        staticRequestsStatus : StaticHttpRequest.Status ()
                        staticRequestsStatus =
                            allRawResponses
                                |> StaticHttpRequest.cacheRequestResolution request

                        hasPermanentError : Bool
                        hasPermanentError =
                            case staticRequestsStatus of
                                StaticHttpRequest.HasPermanentError _ ->
                                    True

                                _ ->
                                    False

                        hasPermanentHttpError : Bool
                        hasPermanentHttpError =
                            not (List.isEmpty errors)

                        ( allUrlsKnown, knownUrlsToFetch ) =
                            case staticRequestsStatus of
                                StaticHttpRequest.Incomplete newUrlsToFetch ->
                                    ( False, newUrlsToFetch )

                                _ ->
                                    ( True, [] )

                        fetchedAllKnownUrls : Bool
                        fetchedAllKnownUrls =
                            (rawResponses
                                |> Dict.keys
                                |> Set.fromList
                                |> Set.union (allRawResponses |> Dict.keys |> Set.fromList)
                            )
                                |> Set.diff
                                    (knownUrlsToFetch
                                        |> List.map HashRequest.hash
                                        |> Set.fromList
                                    )
                                |> Set.isEmpty
                    in
                    if hasPermanentHttpError || hasPermanentError || (allUrlsKnown && fetchedAllKnownUrls) then
                        False

                    else
                        True
    in
    if pendingRequests then
        let
            requestContinuations : DataSource ()
            requestContinuations =
                case staticResponses of
                    NotFetched request _ ->
                        request
        in
        case
            performStaticHttpRequests allRawResponses requestContinuations
        of
            urlsToPerform ->
                let
                    newAllRawResponses : Dict String (Maybe String)
                    newAllRawResponses =
                        Dict.union allRawResponses dictOfNewUrlsToPerform

                    dictOfNewUrlsToPerform : Dict String (Maybe String)
                    dictOfNewUrlsToPerform =
                        urlsToPerform
                            |> List.map HashRequest.hash
                            |> List.map (\hashedUrl -> ( hashedUrl, Nothing ))
                            |> Dict.fromList

                    maskedToUnmasked : Dict String RequestDetails
                    maskedToUnmasked =
                        urlsToPerform
                            --                                    |> List.map (\secureUrl -> ( Pages.Internal.Secrets.masked secureUrl, secureUrl ))
                            |> List.map
                                (\secureUrl ->
                                    --                                            ( hashUrl secureUrl, { unmasked = secureUrl, masked = secureUrl } )
                                    ( HashRequest.hash secureUrl, secureUrl )
                                )
                            |> Dict.fromList

                    alreadyPerformed : Set String
                    alreadyPerformed =
                        allRawResponses
                            |> Dict.keys
                            |> Set.fromList

                    newThing : List RequestDetails
                    newThing =
                        maskedToUnmasked
                            |> Dict.Extra.removeMany alreadyPerformed
                            |> Dict.toList
                            |> List.map
                                (\( _, secureUrl ) ->
                                    secureUrl
                                )
                in
                ( model.staticResponses, Continue newAllRawResponses newThing maybeRoutes )

    else
        case model.staticResponses of
            StaticResponses _ ->
                --let
                --    siteStaticData =
                --        StaticHttpRequest.resolve ApplicationType.Cli
                --            config.site.staticData
                --            (allRawResponses |> Dict.Extra.filterMap (\_ value -> Just value))
                --            |> Result.mapError (StaticHttpRequest.toBuildError "Site.elm")
                --in
                --case siteStaticData of
                --    Err siteStaticDataError ->
                --        ( staticResponses_
                --        , ToJsPayload.toJsPayload
                --            (encode allRawResponses mode staticResponses)
                --            generatedOkayFiles
                --            allRawResponses
                --            (siteStaticDataError :: allErrors)
                --            |> Finish
                --        )
                --
                --    Ok okSiteStaticData ->
                let
                    allErrors : List BuildError
                    allErrors =
                        let
                            failedRequests : List BuildError
                            failedRequests =
                                case staticResponses of
                                    NotFetched request _ ->
                                        let
                                            staticRequestsStatus : StaticHttpRequest.Status ()
                                            staticRequestsStatus =
                                                StaticHttpRequest.cacheRequestResolution
                                                    request
                                                    usableRawResponses

                                            usableRawResponses : RequestsAndPending
                                            usableRawResponses =
                                                allRawResponses

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

                            generatedFileErrors : List BuildError
                            generatedFileErrors =
                                let
                                    generatedFiles : List (Result String { path : List String, content : String })
                                    generatedFiles =
                                        resolvedGenerateFilesResult |> Result.withDefault []

                                    resolvedGenerateFilesResult : Result StaticHttpRequest.Error (List (Result String { path : List String, content : String }))
                                    resolvedGenerateFilesResult =
                                        StaticHttpRequest.resolve
                                            (buildTimeFilesRequest config)
                                            (allRawResponses |> Dict.Extra.filterMap (\_ value -> Just value))
                                in
                                generatedFiles
                                    |> List.filterMap
                                        (\result ->
                                            case result of
                                                Ok _ ->
                                                    Nothing

                                                Err error_ ->
                                                    Just
                                                        { title = "Generate Files Error"
                                                        , message =
                                                            [ Terminal.text "I encountered an Err from your generateFiles function. Message:\n"
                                                            , Terminal.text <| "Error: " ++ error_
                                                            ]
                                                        , path = "Site.elm"
                                                        , fatal = True
                                                        }
                                        )
                        in
                        errors ++ failedRequests ++ generatedFileErrors
                in
                ( model.staticResponses
                , case encode allRawResponses staticResponses of
                    Ok encodedResponses ->
                        -- TODO send all global head tags on initial call
                        if List.length allErrors > 0 then
                            allErrors
                                |> Errors
                                |> Finish

                        else
                            Page encodedResponses
                                |> Finish

                    Err buildErrors ->
                        (allErrors ++ buildErrors)
                            |> Errors
                            |> Finish
                )

            ApiRequest _ ->
                ( model.staticResponses
                , ApiResponse
                    |> Finish
                )

            CheckIfHandled pageFoundDataSource (NotFetched _ _) andThenRequest ->
                let
                    pageFoundResult : Result StaticHttpRequest.Error (Maybe NotFoundReason)
                    pageFoundResult =
                        StaticHttpRequest.resolve
                            pageFoundDataSource
                            (allRawResponses |> Dict.Extra.filterMap (\_ value -> Just value))
                in
                case pageFoundResult of
                    Ok Nothing ->
                        nextStep config { model | staticResponses = StaticResponses andThenRequest } maybeRoutes

                    Ok (Just _) ->
                        ( empty
                        , Finish ApiResponse
                          -- TODO should there be a new type for 404response? Or something else?
                        )

                    Err error_ ->
                        let
                            failedRequests : List BuildError
                            failedRequests =
                                case staticResponses of
                                    NotFetched request _ ->
                                        let
                                            staticRequestsStatus : StaticHttpRequest.Status ()
                                            staticRequestsStatus =
                                                StaticHttpRequest.cacheRequestResolution
                                                    request
                                                    usableRawResponses

                                            usableRawResponses : RequestsAndPending
                                            usableRawResponses =
                                                allRawResponses

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
                        ( model.staticResponses
                        , Finish
                            (Errors <|
                                ([ StaticHttpRequest.toBuildError
                                    -- TODO give more fine-grained error reference
                                    "get static routes"
                                    error_
                                 ]
                                    ++ failedRequests
                                    ++ errors
                                )
                            )
                        )


performStaticHttpRequests :
    Dict String (Maybe String)
    -> DataSource a
    -> List RequestDetails
performStaticHttpRequests allRawResponses request =
    StaticHttpRequest.resolveUrls request allRawResponses
