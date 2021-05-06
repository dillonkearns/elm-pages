module Pages.Internal.Platform.StaticResponses exposing (NextStep(..), StaticResponses, error, init, nextStep, renderApiRequest, renderSingleRoute, update)

import ApiHandler
import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import DataSource.Http exposing (RequestDetails)
import Dict exposing (Dict)
import Dict.Extra
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsPayload)
import Pages.PagePath exposing (PagePath)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import Secrets
import SecretsDict exposing (SecretsDict)
import Set
import TerminalText as Terminal


type StaticResponses
    = GettingInitialData StaticHttpResult
    | ApiRequest StaticHttpResult
    | StaticResponses (Dict String StaticHttpResult)


type StaticHttpResult
    = NotFetched (DataSource.DataSource ()) (Dict String (Result () String))


error : StaticResponses
error =
    StaticResponses Dict.empty


init :
    { config
        | getStaticRoutes : DataSource.DataSource (List route)
        , site : SiteConfig route siteData
        , data : route -> DataSource.DataSource pageData
        , sharedData : DataSource.DataSource sharedData
    }
    -> StaticResponses
init config =
    NotFetched
        (DataSource.map3 (\_ _ _ -> ())
            (config.getStaticRoutes
                |> DataSource.andThen
                    (\resolvedRoutes ->
                        config.site resolvedRoutes |> .data
                    )
            )
            (buildTimeFilesRequest config.site)
            config.sharedData
        )
        Dict.empty
        |> GettingInitialData


buildTimeFilesRequest : SiteConfig route siteData -> DataSource (List (Result String { path : List String, content : String }))
buildTimeFilesRequest config =
    let
        allRoutes =
            []
    in
    config allRoutes
        |> .files
        |> List.map
            (\handler ->
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
                                                            Ok { path = path |> String.split "/", content = response.body }
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
    -> { path : PagePath, frontmatter : route }
    -> DataSource.DataSource a
    -> DataSource.DataSource b
    -> StaticResponses
renderSingleRoute config pathAndRoute request cliData =
    [ ( config.routeToPath pathAndRoute.frontmatter |> String.join "/"
      , NotFetched
            (request |> DataSource.map (\_ -> ()))
            Dict.empty
      )
    , ( cliDictKey
      , NotFetched
            (cliData |> DataSource.map (\_ -> ()))
            Dict.empty
      )
    ]
        |> Dict.fromList
        |> StaticResponses


renderApiRequest :
    config
    -> DataSource response
    -> StaticResponses
renderApiRequest config request =
    ApiRequest
        (NotFetched
            (request |> DataSource.map (\_ -> ()))
            Dict.empty
        )


update :
    { request :
        { masked : RequestDetails, unmasked : RequestDetails }
    , response : Result () String
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
update newEntry model =
    let
        updatedAllResponses =
            -- @@@@@@@@@ TODO handle errors here, change Dict to have `Result` instead of `Maybe`
            Dict.insert
                (HashRequest.hash newEntry.request.masked)
                (Just <| Result.withDefault "TODO" newEntry.response)
                model.allRawResponses
    in
    { model
        | allRawResponses = updatedAllResponses
    }


encode : RequestsAndPending -> Mode -> Dict String StaticHttpResult -> Dict String (Dict String String)
encode requestsAndPending mode staticResponses =
    staticResponses
        |> Dict.filter
            (\key _ ->
                key /= cliDictKey
            )
        |> Dict.map
            (\_ result ->
                case result of
                    NotFetched request _ ->
                        case mode of
                            Mode.Dev ->
                                StaticHttpRequest.strippedResponses ApplicationType.Cli request requestsAndPending

                            Mode.Prod ->
                                StaticHttpRequest.strippedResponses ApplicationType.Cli request requestsAndPending

                            Mode.ElmToHtmlBeta ->
                                StaticHttpRequest.strippedResponses ApplicationType.Cli request requestsAndPending
            )


cliDictKey : String
cliDictKey =
    "////elm-pages-CLI////"


type NextStep route
    = Continue (Dict String (Maybe String)) (List { masked : RequestDetails, unmasked : RequestDetails }) (Maybe (List route))
    | Finish ToJsPayload


nextStep :
    { config
        | getStaticRoutes : DataSource.DataSource (List route)
        , routeToPath : route -> List String
        , data : route -> DataSource.DataSource pageData
        , sharedData : DataSource.DataSource sharedData
        , site : SiteConfig route siteData
    }
    ->
        { model
            | staticResponses : StaticResponses
            , secrets : SecretsDict
            , errors : List BuildError
            , allRawResponses : Dict String (Maybe String)
            , mode : Mode
        }
    -> Maybe (List route)
    -> ( StaticResponses, NextStep route )
nextStep config ({ mode, secrets, allRawResponses, errors } as model) maybeRoutes =
    let
        staticResponses =
            case model.staticResponses of
                StaticResponses s ->
                    s

                GettingInitialData initialData ->
                    Dict.singleton cliDictKey initialData

                ApiRequest staticHttpResult ->
                    Dict.singleton cliDictKey staticHttpResult

        generatedFiles : List (Result String { path : List String, content : String })
        generatedFiles =
            resolvedGenerateFilesResult |> Result.withDefault []

        resolvedGenerateFilesResult : Result StaticHttpRequest.Error (List (Result String { path : List String, content : String }))
        resolvedGenerateFilesResult =
            StaticHttpRequest.resolve ApplicationType.Cli
                (buildTimeFilesRequest config.site)
                (allRawResponses |> Dict.Extra.filterMap (\_ value -> Just value))

        generatedOkayFiles : List { path : List String, content : String }
        generatedOkayFiles =
            generatedFiles
                |> List.filterMap
                    (\result ->
                        case result of
                            Ok ok ->
                                Just ok

                            Err _ ->
                                Nothing
                    )

        generatedFileErrors : List BuildError
        generatedFileErrors =
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

        allErrors : List BuildError
        allErrors =
            errors ++ failedRequests ++ generatedFileErrors

        pendingRequests =
            staticResponses
                |> Dict.Extra.any
                    (\_ entry ->
                        case entry of
                            NotFetched request rawResponses ->
                                let
                                    staticRequestsStatus =
                                        allRawResponses
                                            |> StaticHttpRequest.cacheRequestResolution ApplicationType.Cli request

                                    hasPermanentError =
                                        case staticRequestsStatus of
                                            StaticHttpRequest.HasPermanentError _ ->
                                                True

                                            _ ->
                                                False

                                    hasPermanentHttpError =
                                        not (List.isEmpty errors)

                                    ( allUrlsKnown, knownUrlsToFetch ) =
                                        case staticRequestsStatus of
                                            StaticHttpRequest.Incomplete newUrlsToFetch ->
                                                ( False, newUrlsToFetch )

                                            _ ->
                                                ( True, [] )

                                    fetchedAllKnownUrls =
                                        (rawResponses
                                            |> Dict.keys
                                            |> Set.fromList
                                            |> Set.union (allRawResponses |> Dict.keys |> Set.fromList)
                                        )
                                            |> Set.diff
                                                (knownUrlsToFetch
                                                    |> List.map Secrets.maskedLookup
                                                    |> List.map HashRequest.hash
                                                    |> Set.fromList
                                                )
                                            |> Set.isEmpty
                                in
                                if hasPermanentHttpError || hasPermanentError || (allUrlsKnown && fetchedAllKnownUrls) then
                                    False

                                else
                                    True
                    )

        failedRequests =
            staticResponses
                |> Dict.toList
                |> List.concatMap
                    (\( path, NotFetched request _ ) ->
                        let
                            staticRequestsStatus =
                                StaticHttpRequest.cacheRequestResolution
                                    ApplicationType.Cli
                                    request
                                    usableRawResponses

                            usableRawResponses : RequestsAndPending
                            usableRawResponses =
                                allRawResponses

                            maybePermanentError =
                                case staticRequestsStatus of
                                    StaticHttpRequest.HasPermanentError theError ->
                                        Just theError

                                    _ ->
                                        Nothing

                            decoderErrors =
                                maybePermanentError
                                    |> Maybe.map (StaticHttpRequest.toBuildError path)
                                    |> Maybe.map List.singleton
                                    |> Maybe.withDefault []
                        in
                        decoderErrors
                    )
    in
    if pendingRequests then
        let
            requestContinuations : List ( String, DataSource.DataSource () )
            requestContinuations =
                staticResponses
                    |> Dict.toList
                    |> List.map
                        (\( path, NotFetched request _ ) ->
                            ( path, request )
                        )
        in
        case
            performStaticHttpRequests allRawResponses secrets requestContinuations
        of
            Ok urlsToPerform ->
                let
                    newAllRawResponses =
                        Dict.union allRawResponses dictOfNewUrlsToPerform

                    dictOfNewUrlsToPerform =
                        urlsToPerform
                            |> List.map .masked
                            |> List.map HashRequest.hash
                            |> List.map (\hashedUrl -> ( hashedUrl, Nothing ))
                            |> Dict.fromList

                    maskedToUnmasked : Dict String { masked : RequestDetails, unmasked : RequestDetails }
                    maskedToUnmasked =
                        urlsToPerform
                            --                                    |> List.map (\secureUrl -> ( Pages.Internal.Secrets.masked secureUrl, secureUrl ))
                            |> List.map
                                (\secureUrl ->
                                    --                                            ( hashUrl secureUrl, { unmasked = secureUrl, masked = secureUrl } )
                                    ( HashRequest.hash secureUrl.masked, secureUrl )
                                )
                            |> Dict.fromList

                    alreadyPerformed =
                        allRawResponses
                            |> Dict.keys
                            |> Set.fromList

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

            Err error_ ->
                ( model.staticResponses, Finish (ToJsPayload.Errors <| (error_ ++ failedRequests ++ errors)) )

    else
        case model.staticResponses of
            GettingInitialData (NotFetched _ _) ->
                let
                    resolvedRoutes : Result StaticHttpRequest.Error (List route)
                    resolvedRoutes =
                        StaticHttpRequest.resolve ApplicationType.Cli
                            (DataSource.map3
                                (\routes _ _ ->
                                    routes
                                )
                                config.getStaticRoutes
                                (buildTimeFilesRequest config.site)
                                config.sharedData
                            )
                            (allRawResponses |> Dict.Extra.filterMap (\_ value -> Just value))
                in
                case resolvedRoutes of
                    Ok staticRoutes ->
                        let
                            newState =
                                staticRoutes
                                    |> List.map
                                        (\route ->
                                            let
                                                entry =
                                                    NotFetched
                                                        (DataSource.map2 (\_ _ -> ())
                                                            config.sharedData
                                                            (config.data route)
                                                        )
                                                        Dict.empty
                                            in
                                            ( config.routeToPath route |> String.join "/"
                                            , entry
                                            )
                                        )
                                    |> Dict.fromList
                                    |> StaticResponses

                            newThing =
                                []
                        in
                        ( newState
                        , Continue allRawResponses newThing (Just staticRoutes)
                        )

                    Err error_ ->
                        ( model.staticResponses
                        , Finish
                            (ToJsPayload.Errors <|
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
                ( model.staticResponses
                , ToJsPayload.toJsPayload
                    (encode allRawResponses mode staticResponses)
                    generatedOkayFiles
                    allRawResponses
                    allErrors
                    -- TODO send all global head tags on initial call
                    |> Finish
                )

            ApiRequest _ ->
                ( model.staticResponses
                , ToJsPayload.ApiResponse
                    |> Finish
                )


performStaticHttpRequests :
    Dict String (Maybe String)
    -> SecretsDict
    -> List ( String, DataSource.DataSource a )
    -> Result (List BuildError) (List { unmasked : RequestDetails, masked : RequestDetails })
performStaticHttpRequests allRawResponses secrets staticRequests =
    staticRequests
        -- TODO look for performance bottleneck in this double nesting
        |> List.map
            (\( _, request ) ->
                allRawResponses
                    |> StaticHttpRequest.resolveUrls ApplicationType.Cli request
                    |> Tuple.second
            )
        |> List.concat
        -- TODO prevent duplicates... can't because Set needs comparable
        --        |> Set.fromList
        --        |> Set.toList
        |> List.map
            (\urlBuilder ->
                urlBuilder
                    |> Secrets.lookup secrets
                    |> Result.map
                        (\unmasked ->
                            { unmasked = unmasked
                            , masked = Secrets.maskedLookup urlBuilder
                            }
                        )
            )
        |> combineMultipleErrors
        |> Result.mapError List.concat


combineMultipleErrors : List (Result error a) -> Result (List error) (List a)
combineMultipleErrors results =
    List.foldr
        (\result soFarResult ->
            case soFarResult of
                Ok soFarOk ->
                    case result of
                        Ok value ->
                            value :: soFarOk |> Ok

                        Err error_ ->
                            Err [ error_ ]

                Err errorsSoFar ->
                    case result of
                        Ok _ ->
                            Err errorsSoFar

                        Err error_ ->
                            Err <| error_ :: errorsSoFar
        )
        (Ok [])
        results
