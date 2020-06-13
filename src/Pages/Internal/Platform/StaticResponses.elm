module Pages.Internal.Platform.StaticResponses exposing (..)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Dict.Extra
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload exposing (ToJsPayload)
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp exposing (RequestDetails)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import SecretsDict exposing (SecretsDict)
import Set
import TerminalText as Terminal


type StaticResponses
    = StaticResponses (Dict String StaticHttpResult)


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String (Result () String))


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


error : StaticResponses
error =
    StaticResponses Dict.empty


init :
    Dict String (Maybe String)
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    ->
        { config
            | content : Content
            , generateFiles :
                List
                    { path : PagePath pathKey
                    , frontmatter : metadata
                    , body : String
                    }
                ->
                    StaticHttp.Request
                        (List
                            (Result String
                                { path : List String
                                , content : String
                                }
                            )
                        )
        }
    -> List ( PagePath pathKey, StaticHttp.Request value )
    -> StaticResponses
init staticHttpCache siteMetadataResult config list =
    let
        generateFilesRequest : StaticHttp.Request (List (Result String { path : List String, content : String }))
        generateFilesRequest =
            config.generateFiles siteMetadataWithContent

        generateFilesStaticRequest =
            ( -- we don't want to include the CLI-only StaticHttp responses in the production bundle
              -- since that data is only needed to run these functions during the build step
              -- in the future, this could be refactored to have a type to represent this more clearly
              cliDictKey
            , NotFetched (generateFilesRequest |> StaticHttp.map (\_ -> ())) Dict.empty
            )

        siteMetadataWithContent =
            siteMetadataResult
                |> Result.withDefault []
                |> List.map
                    (\( pagePath, metadata ) ->
                        let
                            contentForPage =
                                config.content
                                    |> List.filterMap
                                        (\( path, { body } ) ->
                                            let
                                                pagePathToGenerate =
                                                    PagePath.toString pagePath

                                                currentContentPath =
                                                    "/" ++ (path |> String.join "/")
                                            in
                                            if pagePathToGenerate == currentContentPath then
                                                Just body

                                            else
                                                Nothing
                                        )
                                    |> List.head
                                    |> Maybe.andThen identity
                        in
                        { path = pagePath
                        , frontmatter = metadata
                        , body = contentForPage |> Maybe.withDefault ""
                        }
                    )
    in
    list
        |> List.map
            (\( path, staticRequest ) ->
                let
                    entry =
                        NotFetched (staticRequest |> StaticHttp.map (\_ -> ())) Dict.empty

                    updatedEntry =
                        staticHttpCache
                            |> dictCompact
                            |> Dict.toList
                            |> List.foldl
                                (\( hashedRequest, response ) entrySoFar ->
                                    entrySoFar
                                        |> addEntry
                                            staticHttpCache
                                            hashedRequest
                                            (Ok response)
                                )
                                entry
                in
                ( PagePath.toString path
                , updatedEntry
                )
            )
        |> List.append [ generateFilesStaticRequest ]
        |> Dict.fromList
        |> StaticResponses


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
        , staticResponses =
            case model.staticResponses of
                StaticResponses staticResponses ->
                    staticResponses
                        |> Dict.map
                            (\pageUrl entry ->
                                case entry of
                                    NotFetched request rawResponses ->
                                        let
                                            realUrls =
                                                updatedAllResponses
                                                    |> dictCompact
                                                    |> StaticHttpRequest.resolveUrls ApplicationType.Cli request
                                                    |> Tuple.second
                                                    |> List.map Secrets.maskedLookup
                                                    |> List.map HashRequest.hash

                                            includesUrl =
                                                List.member
                                                    (HashRequest.hash newEntry.request.masked)
                                                    realUrls
                                        in
                                        if includesUrl then
                                            let
                                                updatedRawResponses =
                                                    Dict.insert
                                                        (HashRequest.hash newEntry.request.masked)
                                                        newEntry.response
                                                        rawResponses
                                            in
                                            NotFetched request updatedRawResponses

                                        else
                                            entry
                            )
                        |> StaticResponses
    }


addEntry :
    Dict String (Maybe String)
    -> String
    -> Result () String
    -> StaticHttpResult
    -> StaticHttpResult
addEntry globalRawResponses hashedRequest rawResponse ((NotFetched request rawResponses) as entry) =
    let
        realUrls =
            globalRawResponses
                |> dictCompact
                |> StaticHttpRequest.resolveUrls ApplicationType.Cli request
                |> Tuple.second
                |> List.map Secrets.maskedLookup
                |> List.map HashRequest.hash

        includesUrl =
            List.member
                hashedRequest
                realUrls
    in
    if includesUrl then
        let
            updatedRawResponses =
                Dict.insert
                    hashedRequest
                    rawResponse
                    rawResponses
        in
        NotFetched request updatedRawResponses

    else
        entry


encode : Mode -> StaticResponses -> Dict String (Dict String String)
encode mode (StaticResponses staticResponses) =
    staticResponses
        |> Dict.filter
            (\key value ->
                key /= cliDictKey
            )
        |> Dict.map
            (\path result ->
                case result of
                    NotFetched request rawResponsesDict ->
                        let
                            relevantResponses =
                                Dict.map
                                    (\_ ->
                                        -- TODO avoid running this code at all if there are errors here
                                        Result.withDefault ""
                                    )
                                    rawResponsesDict

                            strippedResponses : Dict String String
                            strippedResponses =
                                -- TODO should this return an Err and handle that here?
                                StaticHttpRequest.strippedResponses ApplicationType.Cli request relevantResponses
                        in
                        case mode of
                            Mode.Dev ->
                                relevantResponses

                            Mode.Prod ->
                                strippedResponses
            )


dictCompact : Dict String (Maybe a) -> Dict String a
dictCompact dict =
    dict
        |> Dict.Extra.filterMap (\key value -> value)


cliDictKey : String
cliDictKey =
    "////elm-pages-CLI////"


type NextStep pathKey
    = Continue (Dict String (Maybe String)) (List { masked : RequestDetails, unmasked : RequestDetails })
    | Finish (ToJsPayload pathKey)


nextStep :
    { config
        | content : Content
        , manifest : Manifest.Config pathKey
        , generateFiles :
            List
                { path : PagePath pathKey
                , frontmatter : metadata
                , body : String
                }
            ->
                StaticHttp.Request
                    (List
                        (Result String
                            { path : List String
                            , content : String
                            }
                        )
                    )
    }
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Mode
    -> SecretsDict
    -> Dict String (Maybe String)
    -> List BuildError
    -> StaticResponses
    -> NextStep pathKey
nextStep config siteMetadata mode secrets allRawResponses errors (StaticResponses staticResponses) =
    let
        pendingRequests =
            staticResponses
                |> Dict.Extra.any
                    (\path entry ->
                        case entry of
                            NotFetched request rawResponses ->
                                let
                                    usableRawResponses : Dict String String
                                    usableRawResponses =
                                        Dict.Extra.filterMap
                                            (\key value ->
                                                value
                                                    |> Result.map Just
                                                    |> Result.withDefault Nothing
                                            )
                                            rawResponses

                                    hasPermanentError =
                                        usableRawResponses
                                            |> StaticHttpRequest.permanentError ApplicationType.Cli request
                                            |> isJust

                                    hasPermanentHttpError =
                                        not (List.isEmpty errors)

                                    --|> List.any
                                    --    (\error ->
                                    --        case error of
                                    --            FailedStaticHttpRequestError _ ->
                                    --                True
                                    --
                                    --            _ ->
                                    --                False
                                    --    )
                                    ( allUrlsKnown, knownUrlsToFetch ) =
                                        StaticHttpRequest.resolveUrls
                                            ApplicationType.Cli
                                            request
                                            (rawResponses |> Dict.map (\key value -> value |> Result.withDefault ""))

                                    fetchedAllKnownUrls =
                                        (knownUrlsToFetch
                                            |> List.map Secrets.maskedLookup
                                            |> List.map HashRequest.hash
                                            |> Set.fromList
                                            |> Set.size
                                        )
                                            == (rawResponses |> Dict.keys |> List.length)
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
                    (\( path, NotFetched request rawResponses ) ->
                        let
                            usableRawResponses : Dict String String
                            usableRawResponses =
                                rawResponses
                                    |> Dict.Extra.filterMap
                                        (\key value ->
                                            value
                                                |> Result.map Just
                                                |> Result.withDefault Nothing
                                        )

                            maybePermanentError =
                                StaticHttpRequest.permanentError
                                    ApplicationType.Cli
                                    request
                                    usableRawResponses

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
                        (\( path, NotFetched request rawResponses ) ->
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
                                (\( maskedUrl, secureUrl ) ->
                                    secureUrl
                                )
                in
                Continue newAllRawResponses newThing

            Err error_ ->
                Finish (ToJsPayload.Errors <| BuildError.errorsToString (error_ ++ failedRequests ++ errors))

    else
        let
            metadataForGenerateFiles =
                siteMetadata
                    |> Result.withDefault []
                    |> List.map
                        (\( pagePath, metadata ) ->
                            let
                                contentForPage =
                                    config.content
                                        |> List.filterMap
                                            (\( path, { body } ) ->
                                                let
                                                    pagePathToGenerate =
                                                        PagePath.toString pagePath

                                                    currentContentPath =
                                                        String.join "/" path
                                                in
                                                if pagePathToGenerate == currentContentPath then
                                                    Just body

                                                else
                                                    Nothing
                                            )
                                        |> List.head
                                        |> Maybe.andThen identity
                            in
                            { path = pagePath
                            , frontmatter = metadata
                            , body = contentForPage |> Maybe.withDefault ""
                            }
                        )

            generatedFiles : List (Result String { path : List String, content : String })
            generatedFiles =
                resolvedGenerateFilesResult
                    |> Result.withDefault []

            resolvedGenerateFilesResult : Result StaticHttpRequest.Error (List (Result String { path : List String, content : String }))
            resolvedGenerateFilesResult =
                StaticHttpRequest.resolve ApplicationType.Cli
                    (config.generateFiles metadataForGenerateFiles)
                    (allRawResponses |> Dict.Extra.filterMap (\key value -> value))

            generatedOkayFiles : List { path : List String, content : String }
            generatedOkayFiles =
                generatedFiles
                    |> List.filterMap
                        (\result ->
                            case result of
                                Ok ok ->
                                    Just ok

                                _ ->
                                    Nothing
                        )

            generatedFileErrors : List { title : String, message : List Terminal.Text, fatal : Bool }
            generatedFileErrors =
                generatedFiles
                    |> List.filterMap
                        (\result ->
                            case result of
                                Ok ok ->
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
        in
        ToJsPayload.toJsPayload
            (encode mode (StaticResponses staticResponses))
            config.manifest
            generatedOkayFiles
            allRawResponses
            allErrors
            |> Finish


performStaticHttpRequests :
    Dict String (Maybe String)
    -> SecretsDict
    -> List ( String, StaticHttp.Request a )
    -> Result (List BuildError) (List { unmasked : RequestDetails, masked : RequestDetails })
performStaticHttpRequests allRawResponses secrets staticRequests =
    staticRequests
        |> List.map
            (\( pagePath, request ) ->
                allRawResponses
                    |> dictCompact
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


isJust : Maybe a -> Bool
isJust maybeValue =
    case maybeValue of
        Just _ ->
            True

        Nothing ->
            False
