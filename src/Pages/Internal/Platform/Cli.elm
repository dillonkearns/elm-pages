module Pages.Internal.Platform.Cli exposing
    ( Content
    , Effect(..)
    , Flags
    , Model
    , Msg(..)
    , Page
    , ToJsPayload(..)
    , ToJsSuccessPayload
    , cliApplication
    , init
    , toJsCodec
    , update
    )

import BuildError exposing (BuildError)
import Codec exposing (Codec)
import Dict exposing (Dict)
import Dict.Extra
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Http
import Pages.ImagePath as ImagePath
import Pages.Internal.ApplicationType as ApplicationType exposing (ApplicationType)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp exposing (RequestDetails)
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import SecretsDict exposing (SecretsDict)
import Set exposing (Set)
import TerminalText as Terminal


type ToJsPayload pathKey
    = Errors String
    | Success (ToJsSuccessPayload pathKey)


type alias ToJsSuccessPayload pathKey =
    { pages : Dict String (Dict String String)
    , manifest : Manifest.Config pathKey
    , filesToGenerate : List FileToGenerate
    , staticHttpCache : Dict String String
    , errors : List String
    }


type alias FileToGenerate =
    { path : List String
    , content : String
    }


toJsCodec : Codec (ToJsPayload pathKey)
toJsCodec =
    Codec.custom
        (\errorsTag success value ->
            case value of
                Errors errorList ->
                    errorsTag errorList

                Success { pages, manifest, filesToGenerate, errors, staticHttpCache } ->
                    success (ToJsSuccessPayload pages manifest filesToGenerate staticHttpCache errors)
        )
        |> Codec.variant1 "Errors" Errors Codec.string
        |> Codec.variant1 "Success"
            Success
            successCodec
        |> Codec.buildCustom


stubManifest : Manifest.Config pathKey
stubManifest =
    { backgroundColor = Nothing
    , categories = []
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Nothing
    , startUrl = PagePath.external ""
    , shortName = Just "elm-pages"
    , sourceIcon = ImagePath.external ""
    }


successCodec : Codec (ToJsSuccessPayload pathKey)
successCodec =
    Codec.object ToJsSuccessPayload
        |> Codec.field "pages"
            .pages
            (Codec.dict (Codec.dict Codec.string))
        |> Codec.field "manifest"
            .manifest
            (Codec.build Manifest.toJson (Decode.succeed stubManifest))
        |> Codec.field "filesToGenerate"
            .filesToGenerate
            (Codec.build
                (\list ->
                    list
                        |> Json.Encode.list
                            (\item ->
                                Json.Encode.object
                                    [ ( "path", item.path |> String.join "/" |> Json.Encode.string )
                                    , ( "content", item.content |> Json.Encode.string )
                                    ]
                            )
                )
                (Decode.succeed [])
            )
        |> Codec.field "staticHttpCache"
            .staticHttpCache
            (Codec.dict Codec.string)
        |> Codec.field "errors" .errors (Codec.list Codec.string)
        |> Codec.buildObject


type Effect pathKey
    = NoEffect
    | SendJsData (ToJsPayload pathKey)
    | FetchHttp { masked : RequestDetails, unmasked : RequestDetails }
    | Batch (List (Effect pathKey))


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Flags =
    Decode.Value


type alias Model =
    { staticResponses : StaticResponses
    , secrets : SecretsDict
    , errors : List BuildError
    , allRawResponses : Dict String (Maybe String)
    , mode : Mode
    }


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Pages.Http.Error String }


type alias Config pathKey userMsg userModel metadata view =
    { init :
        Maybe
            { path : PagePath pathKey
            , query : Maybe String
            , fragment : Maybe String
            }
        -> ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view :
        List ( PagePath pathKey, metadata )
        ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
        ->
            StaticHttp.Request
                { view : userModel -> view -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
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
    , canonicalSiteUrl : String
    , pathKey : pathKey
    , onPageChange :
        { path : PagePath pathKey
        , query : Maybe String
        , fragment : Maybe String
        }
        -> userMsg
    }


cliApplication :
    (Msg -> msg)
    -> (msg -> Maybe Msg)
    -> (Model -> model)
    -> (model -> Maybe Model)
    -> Config pathKey userMsg userModel metadata view
    -> Platform.Program Flags model msg
cliApplication cliMsgConstructor narrowMsg toModel fromModel config =
    let
        contentCache =
            ContentCache.init config.document config.content Nothing

        siteMetadata =
            contentCache
                |> Result.map
                    (\cache -> cache |> ContentCache.extractMetadata config.pathKey)
                |> Result.mapError (List.map Tuple.second)
    in
    Platform.worker
        { init =
            \flags ->
                init toModel contentCache siteMetadata config flags
                    |> Tuple.mapSecond (perform cliMsgConstructor config.toJsPort)
        , update =
            \msg model ->
                case ( narrowMsg msg, fromModel model ) of
                    ( Just cliMsg, Just cliModel ) ->
                        update siteMetadata config cliMsg cliModel
                            |> Tuple.mapSecond (perform cliMsgConstructor config.toJsPort)
                            |> Tuple.mapFirst toModel

                    _ ->
                        ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


type Mode
    = Prod
    | Dev


modeDecoder =
    Decode.string
        |> Decode.andThen
            (\mode ->
                if mode == "prod" then
                    Decode.succeed Prod

                else
                    Decode.succeed Dev
            )


perform : (Msg -> msg) -> (Json.Encode.Value -> Cmd Never) -> Effect pathKey -> Cmd msg
perform cliMsgConstructor toJsPort effect =
    case effect of
        NoEffect ->
            Cmd.none

        SendJsData value ->
            value
                |> Codec.encoder toJsCodec
                |> toJsPort
                |> Cmd.map never

        Batch list ->
            list
                |> List.map (perform cliMsgConstructor toJsPort)
                |> Cmd.batch

        FetchHttp ({ unmasked, masked } as requests) ->
            -- let
            --     _ =
            --         Debug.log "Fetching" masked.url
            -- in
            Http.request
                { method = unmasked.method
                , url = unmasked.url
                , headers = unmasked.headers |> List.map (\( key, value ) -> Http.header key value)
                , body =
                    case unmasked.body of
                        StaticHttpBody.EmptyBody ->
                            Http.emptyBody

                        StaticHttpBody.StringBody contentType string ->
                            Http.stringBody contentType string

                        StaticHttpBody.JsonBody value ->
                            Http.jsonBody value
                , expect =
                    Pages.Http.expectString
                        (\response ->
                            (GotStaticHttpResponse >> cliMsgConstructor)
                                { request = requests
                                , response = response
                                }
                        )
                , timeout = Nothing
                , tracker = Nothing
                }


init :
    (Model -> model)
    -> ContentCache.ContentCache metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Config pathKey userMsg userModel metadata view
    -> Decode.Value
    -> ( model, Effect pathKey )
init toModel contentCache siteMetadata config flags =
    case
        Decode.decodeValue
            (Decode.map3 (\a b c -> ( a, b, c ))
                (Decode.field "secrets" SecretsDict.decoder)
                (Decode.field "mode" modeDecoder)
                (Decode.field "staticHttpCache"
                    (Decode.dict
                        (Decode.string
                            |> Decode.map Just
                        )
                    )
                )
            )
            flags
    of
        Ok ( secrets, mode, staticHttpCache ) ->
            case contentCache of
                Ok _ ->
                    case ContentCache.pagesWithErrors contentCache of
                        [] ->
                            let
                                requests =
                                    Result.andThen
                                        (\metadata ->
                                            staticResponseForPage metadata config.view
                                        )
                                        siteMetadata

                                staticResponses : StaticResponses
                                staticResponses =
                                    case requests of
                                        Ok okRequests ->
                                            staticResponsesInit staticHttpCache siteMetadata config okRequests

                                        Err errors ->
                                            -- TODO need to handle errors better?
                                            staticResponsesInit staticHttpCache siteMetadata config []

                                ( updatedRawResponses, effect ) =
                                    sendStaticResponsesIfDone config siteMetadata mode secrets staticHttpCache [] staticResponses
                            in
                            ( Model staticResponses secrets [] updatedRawResponses mode |> toModel
                            , effect
                            )

                        pageErrors ->
                            let
                                requests =
                                    Result.andThen
                                        (\metadata ->
                                            staticResponseForPage metadata config.view
                                        )
                                        siteMetadata

                                staticResponses : StaticResponses
                                staticResponses =
                                    case requests of
                                        Ok okRequests ->
                                            staticResponsesInit staticHttpCache siteMetadata config okRequests

                                        Err errors ->
                                            -- TODO need to handle errors better?
                                            staticResponsesInit staticHttpCache siteMetadata config []
                            in
                            updateAndSendPortIfDone
                                config
                                siteMetadata
                                (Model
                                    staticResponses
                                    secrets
                                    pageErrors
                                    staticHttpCache
                                    mode
                                )
                                toModel

                Err metadataParserErrors ->
                    updateAndSendPortIfDone
                        config
                        siteMetadata
                        (Model Dict.empty
                            secrets
                            (metadataParserErrors |> List.map Tuple.second)
                            staticHttpCache
                            mode
                        )
                        toModel

        Err error ->
            updateAndSendPortIfDone
                config
                siteMetadata
                (Model Dict.empty
                    SecretsDict.masked
                    [ { title = "Internal Error"
                      , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                      , fatal = True
                      }
                    ]
                    Dict.empty
                    Dev
                )
                toModel


updateAndSendPortIfDone :
    Config pathKey userMsg userModel metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Model
    -> (Model -> model)
    -> ( model, Effect pathKey )
updateAndSendPortIfDone config siteMetadata model toModel =
    let
        ( updatedAllRawResponses, effect ) =
            sendStaticResponsesIfDone
                config
                siteMetadata
                model.mode
                model.secrets
                model.allRawResponses
                model.errors
                model.staticResponses
    in
    ( { model | allRawResponses = updatedAllRawResponses } |> toModel
    , effect
    )


type alias PageErrors =
    Dict String String


update :
    Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Config pathKey userMsg userModel metadata view
    -> Msg
    -> Model
    -> ( Model, Effect pathKey )
update siteMetadata config msg model =
    case msg of
        GotStaticHttpResponse { request, response } ->
            let
                -- _ =
                --     Debug.log "Got response" request.masked.url
                --
                updatedModel =
                    (case response of
                        Ok okResponse ->
                            staticResponsesUpdate
                                { request = request
                                , response = Result.mapError (\_ -> ()) response
                                }
                                model

                        Err error ->
                            { model
                                | errors =
                                    List.append
                                        model.errors
                                        [ { title = "Static HTTP Error"
                                          , message =
                                                [ Terminal.text "I got an error making an HTTP request to this URL: "

                                                -- TODO include HTTP method, headers, and body
                                                , Terminal.yellow <| Terminal.text request.masked.url
                                                , Terminal.text "\n\n"
                                                , case error of
                                                    Pages.Http.BadStatus metadata body ->
                                                        Terminal.text <|
                                                            String.join "\n"
                                                                [ "Bad status: " ++ String.fromInt metadata.statusCode
                                                                , "Status message: " ++ metadata.statusText
                                                                , "Body: " ++ body
                                                                ]

                                                    Pages.Http.BadUrl _ ->
                                                        -- TODO include HTTP method, headers, and body
                                                        Terminal.text <| "Invalid url: " ++ request.masked.url

                                                    Pages.Http.Timeout ->
                                                        Terminal.text "Timeout"

                                                    Pages.Http.NetworkError ->
                                                        Terminal.text "Network error"
                                                ]
                                          , fatal = True
                                          }
                                        ]
                            }
                    )
                        |> staticResponsesUpdate
                            -- TODO for hash pass in RequestDetails here
                            { request = request
                            , response = Result.mapError (\_ -> ()) response
                            }

                ( updatedAllRawResponses, effect ) =
                    sendStaticResponsesIfDone config siteMetadata updatedModel.mode updatedModel.secrets updatedModel.allRawResponses updatedModel.errors updatedModel.staticResponses
            in
            ( { updatedModel | allRawResponses = updatedAllRawResponses }
            , effect
            )


dictCompact : Dict String (Maybe a) -> Dict String a
dictCompact dict =
    dict
        |> Dict.Extra.filterMap (\key value -> value)


performStaticHttpRequests : Dict String (Maybe String) -> SecretsDict -> List ( String, StaticHttp.Request a ) -> Result (List BuildError) (List { unmasked : RequestDetails, masked : RequestDetails })
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

                        Err error ->
                            Err [ error ]

                Err errorsSoFar ->
                    case result of
                        Ok _ ->
                            Err errorsSoFar

                        Err error ->
                            Err <| error :: errorsSoFar
        )
        (Ok [])
        results


cliDictKey : String
cliDictKey =
    "////elm-pages-CLI////"


staticResponsesInit : Dict String (Maybe String) -> Result (List BuildError) (List ( PagePath pathKey, metadata )) -> Config pathKey userMsg userModel metadata view -> List ( PagePath pathKey, StaticHttp.Request value ) -> StaticResponses
staticResponsesInit staticHttpCache siteMetadataResult config list =
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


staticResponsesUpdate : { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result () String } -> Model -> Model
staticResponsesUpdate newEntry model =
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
            Dict.map
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
                model.staticResponses
    }


addEntry : Dict String (Maybe String) -> String -> Result () String -> StaticHttpResult -> StaticHttpResult
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


isJust : Maybe a -> Bool
isJust maybeValue =
    case maybeValue of
        Just _ ->
            True

        Nothing ->
            False


sendStaticResponsesIfDone :
    Config pathKey userMsg userModel metadata view
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    -> Mode
    -> SecretsDict
    -> Dict String (Maybe String)
    -> List BuildError
    -> StaticResponses
    -> ( Dict String (Maybe String), Effect pathKey )
sendStaticResponsesIfDone config siteMetadata mode secrets allRawResponses errors staticResponses =
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

            ( updatedAllRawResponses, newEffect ) =
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
                                            FetchHttp secureUrl
                                        )
                                    |> Batch
                        in
                        ( newAllRawResponses, newThing )

                    Err error ->
                        ( allRawResponses
                        , SendJsData <|
                            (Errors <| BuildError.errorsToString (error ++ failedRequests ++ errors))
                        )
        in
        ( updatedAllRawResponses, newEffect )

    else
        let
            updatedAllRawResponses =
                Dict.empty

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

            --generatedFiles : StaticHttp.Request (List (Result String { path : List String, content : String }))
            --generatedFiles : List (Result String { path : List String, content : String })
            generatedFiles =
                mythingy2
                    |> Result.withDefault []

            mythingy2 : Result StaticHttpRequest.Error (List (Result String { path : List String, content : String }))
            mythingy2 =
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

                                Err error ->
                                    Just
                                        { title = "Generate Files Error"
                                        , message =
                                            [ Terminal.text "I encountered an Err from your generateFiles function. Message:\n"
                                            , Terminal.text <| "Error: " ++ error
                                            ]
                                        , fatal = True
                                        }
                        )

            allErrors : List BuildError
            allErrors =
                errors ++ failedRequests ++ generatedFileErrors
        in
        ( updatedAllRawResponses
        , toJsPayload
            (encodeStaticResponses mode staticResponses)
            config.manifest
            generatedOkayFiles
            allRawResponses
            allErrors
        )


toJsPayload :
    Dict String (Dict String String)
    -> Manifest.Config pathKey
    -> List FileToGenerate
    -> Dict String (Maybe String)
    -> List { title : String, message : List Terminal.Text, fatal : Bool }
    -> Effect pathKey
toJsPayload encodedStatic manifest generated allRawResponses allErrors =
    SendJsData <|
        if allErrors |> List.filter .fatal |> List.isEmpty then
            Success
                (ToJsSuccessPayload
                    encodedStatic
                    manifest
                    generated
                    (allRawResponses
                        |> Dict.toList
                        |> List.filterMap
                            (\( key, maybeValue ) ->
                                maybeValue
                                    |> Maybe.map (\value -> ( key, value ))
                            )
                        |> Dict.fromList
                    )
                    (List.map BuildError.errorToString allErrors)
                )

        else
            Errors <| BuildError.errorsToString allErrors


encodeStaticResponses : Mode -> StaticResponses -> Dict String (Dict String String)
encodeStaticResponses mode staticResponses =
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
                            Dev ->
                                relevantResponses

                            Prod ->
                                strippedResponses
            )


type alias StaticResponses =
    Dict String StaticHttpResult


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String (Result () String))


staticResponseForPage :
    List ( PagePath pathKey, metadata )
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            StaticHttpRequest.Request
                { view : userModel -> view -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
        )
    ->
        Result (List BuildError)
            (List
                ( PagePath pathKey
                , StaticHttp.Request
                    { view : userModel -> view -> { title : String, body : Html userMsg }
                    , head : List (Head.Tag pathKey)
                    }
                )
            )
staticResponseForPage siteMetadata viewFn =
    siteMetadata
        |> List.map
            (\( pagePath, frontmatter ) ->
                let
                    thing =
                        viewFn siteMetadata
                            { path = pagePath
                            , frontmatter = frontmatter
                            }
                in
                Ok ( pagePath, thing )
            )
        |> combine


combine : List (Result error ( key, success )) -> Result (List error) (List ( key, success ))
combine list =
    list
        |> List.foldr resultFolder (Ok [])


resultFolder : Result error a -> Result (List error) (List a) -> Result (List error) (List a)
resultFolder current soFarResult =
    case soFarResult of
        Ok soFarOk ->
            case current of
                Ok currentOk ->
                    currentOk
                        :: soFarOk
                        |> Ok

                Err error ->
                    Err [ error ]

        Err soFarErr ->
            case current of
                Ok currentOk ->
                    Err soFarErr

                Err error ->
                    error
                        :: soFarErr
                        |> Err
