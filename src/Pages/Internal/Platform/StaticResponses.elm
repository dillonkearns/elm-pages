module Pages.Internal.Platform.StaticResponses exposing (NextStep(..), StaticResponses, error, init, nextStep, update)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Dict.Extra
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsPayload)
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp exposing (RequestDetails)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending exposing (RequestsAndPending)
import Secrets
import SecretsDict exposing (SecretsDict)
import Set
import TerminalText as Terminal


type StaticResponses
    = GettingInitialData StaticHttpResult
    | StaticResponses (Dict String StaticHttpResult)


type StaticHttpResult
    = NotFetched (StaticHttp.Request ()) (Dict String (Result () String))


error : StaticResponses
error =
    StaticResponses Dict.empty


init :
    { config
        | view : List a -> { path : PagePath pathKey, frontmatter : route } -> StaticHttp.Request b
        , getStaticRoutes : StaticHttp.Request (List route)
        , generateFiles :
            StaticHttp.Request
                (List
                    (Result
                        String
                        { path : List String
                        , content : String
                        }
                    )
                )
    }
    -> StaticResponses
init config =
    let
        generateFilesStaticRequest =
            ( -- we don't want to include the CLI-only StaticHttp responses in the production bundle
              -- since that data is only needed to run these functions during the build step
              -- in the future, this could be refactored to have a type to represent this more clearly
              cliDictKey
            , NotFetched (config.generateFiles |> StaticHttp.map (\_ -> ())) Dict.empty
            )

        pathToList pathThing =
            -- TODO remove hardcoding
            { path = PagePath.external "post-1"
            , frontmatter = pathThing
            }

        getStaticRoutesRequest =
            let
                innerThing : List route -> StaticHttp.Request ()
                innerThing staticRoutes =
                    staticRoutes
                        |> List.map pathToList
                        |> List.map
                            (\pathList ->
                                --StaticHttp.fail ""
                                config.view [] pathList |> StaticHttp.map (\_ -> ())
                            )
                        |> StaticHttp.combine
                        |> StaticHttp.map (\_ -> ())

                fetchAllPages : StaticHttp.Request ()
                fetchAllPages =
                    config.getStaticRoutes |> StaticHttp.andThen innerThing
            in
            ( --cliDictKey
              "post-1"
            , NotFetched fetchAllPages Dict.empty
            )
    in
    --[ generateFilesStaticRequest, getStaticRoutesRequest ]
    --    |> Dict.fromList
    --    |> StaticResponses
    NotFetched (config.getStaticRoutes |> StaticHttp.map (\_ -> ())) Dict.empty
        |> GettingInitialData


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


type NextStep pathKey route
    = Continue (Dict String (Maybe String)) (List { masked : RequestDetails, unmasked : RequestDetails }) (Maybe (List route))
    | Finish (ToJsPayload pathKey)


nextStep :
    { config
        | manifest : Manifest.Config pathKey
        , getStaticRoutes : StaticHttp.Request (List route)
        , routeToPath : route -> List String
        , view : List a -> { path : PagePath pathKey, frontmatter : route } -> StaticHttp.Request b
        , pathKey : pathKey
        , generateFiles :
            StaticHttp.Request
                (List
                    (Result
                        String
                        { path : List String
                        , content : String
                        }
                    )
                )
    }
    -> Mode
    -> SecretsDict
    -> RequestsAndPending
    -> List BuildError
    -> StaticResponses
    -> Maybe (List route)
    -> ( StaticResponses, NextStep pathKey route )
nextStep config mode secrets allRawResponses errors staticResponses_ maybeRoutes =
    let
        staticResponses =
            case staticResponses_ of
                StaticResponses s ->
                    s

                GettingInitialData initialData ->
                    Dict.singleton cliDictKey (initialData |> Debug.log "initialData")

        generatedFiles : List (Result String { path : List String, content : String })
        generatedFiles =
            resolvedGenerateFilesResult |> Result.withDefault []

        resolvedGenerateFilesResult : Result StaticHttpRequest.Error (List (Result String { path : List String, content : String }))
        resolvedGenerateFilesResult =
            StaticHttpRequest.resolve ApplicationType.Cli
                config.generateFiles
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
                                --Debug.todo (Debug.toString error_)
                                Nothing
                    )

        generatedFileErrors : List { title : String, message : List Terminal.Text, fatal : Bool }
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
            requestContinuations : List ( String, StaticHttp.Request () )
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
                ( staticResponses_, Continue newAllRawResponses newThing maybeRoutes )

            Err error_ ->
                ( staticResponses_, Finish (ToJsPayload.Errors <| BuildError.errorsToString (error_ ++ failedRequests ++ errors)) )

    else
        case staticResponses_ of
            GettingInitialData (NotFetched _ _) ->
                let
                    resolvedRoutes : Result StaticHttpRequest.Error (List route)
                    resolvedRoutes =
                        StaticHttpRequest.resolve ApplicationType.Cli
                            config.getStaticRoutes
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
                                                        (config.view []
                                                            { path = PagePath.build config.pathKey (config.routeToPath route)
                                                            , frontmatter = route
                                                            }
                                                            |> StaticHttp.map (\_ -> ())
                                                        )
                                                        Dict.empty
                                            in
                                            ( config.routeToPath route |> String.join "/"
                                            , entry
                                            )
                                        )
                                    |> Dict.fromList
                                    |> StaticResponses
                        in
                        nextStep config mode secrets allRawResponses errors newState (Just staticRoutes)

                    Err error_ ->
                        ( staticResponses_
                        , Finish
                            (ToJsPayload.Errors <|
                                BuildError.errorsToString
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

            StaticResponses r ->
                ( staticResponses_
                , ToJsPayload.toJsPayload
                    (encode allRawResponses mode staticResponses)
                    config.manifest
                    generatedOkayFiles
                    allRawResponses
                    allErrors
                    |> Finish
                )


performStaticHttpRequests :
    Dict String (Maybe String)
    -> SecretsDict
    -> List ( String, StaticHttp.Request a )
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
