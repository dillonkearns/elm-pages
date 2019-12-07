module Pages.Internal.Platform.Cli exposing
    ( Content
    , Effect(..)
    , Flags
    , Model
    , Msg(..)
    , Page
    , Parser
    , ToJsPayload(..)
    , ToJsSuccessPayload
    , cliApplication
    , init
    , toJsCodec
    , update
    )

import Browser.Navigation
import BuildError exposing (BuildError)
import Codec exposing (Codec)
import Dict exposing (Dict)
import Dict.Extra
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import Mark
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.ImagePath as ImagePath
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import SecretsDict exposing (SecretsDict)
import Set exposing (Set)
import StaticHttp exposing (RequestDetails)
import TerminalText as Terminal
import Url exposing (Url)


log message value =
    value


type ToJsPayload pathKey
    = Errors String
    | Success (ToJsSuccessPayload pathKey)


type alias ToJsSuccessPayload pathKey =
    { pages : Dict String (Dict String String)
    , manifest : Manifest.Config pathKey
    }


toJsCodec : Codec (ToJsPayload pathKey)
toJsCodec =
    Codec.custom
        (\errors success value ->
            case value of
                Errors errorList ->
                    errors errorList

                Success { pages, manifest } ->
                    success (ToJsSuccessPayload pages manifest)
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
    , errors : List Error
    , allRawResponses : Dict String (Maybe String)
    , mode : Mode
    }


type Error
    = MissingSecrets (List BuildError)
    | MetadataDecodeError BuildError
    | InternalError BuildError
    | FailedStaticHttpRequestError BuildError


type alias ErrorContext =
    { path : List String
    }


type alias ModelDetails userModel metadata view =
    { key : Browser.Navigation.Key
    , url : Url.Url
    , contentCache : ContentCache metadata view
    , userModel : userModel
    }


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document view


type Msg
    = GotStaticHttpResponse { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result Http.Error String }


cliApplication :
    (Msg -> msg)
    -> (msg -> Maybe Msg)
    -> (Model -> model)
    -> (model -> Maybe Model)
    ->
        { init : Maybe (PagePath pathKey) -> ( userModel, Cmd userMsg )
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
        , manifest : Manifest.Config pathKey
        , canonicalSiteUrl : String
        , pathKey : pathKey
        , onPageChange : PagePath pathKey -> userMsg
        }
    --    -> Program userModel userMsg metadata view
    -> Platform.Program Flags model msg
cliApplication cliMsgConstructor narrowMsg toModel fromModel config =
    let
        contentCache =
            ContentCache.init config.document config.content

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
            let
                _ =
                    log "Fetching" masked.url
            in
            Http.request
                { method = unmasked.method
                , url = unmasked.url
                , headers = unmasked.headers |> List.map (\( key, value ) -> Http.header key value)
                , body = Http.emptyBody
                , expect =
                    Http.expectString
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
    ->
        { config
            | view :
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
            , manifest : Manifest.Config pathKey
        }
    -> Decode.Value
    -> ( model, Effect pathKey )
init toModel contentCache siteMetadata config flags =
    case
        Decode.decodeValue
            (Decode.map2 Tuple.pair
                (Decode.field "secrets" SecretsDict.decoder)
                (Decode.field "mode" modeDecoder)
            )
            flags
    of
        Ok ( secrets, mode ) ->
            case contentCache of
                Ok _ ->
                    case contentCache |> ContentCache.pagesWithErrors of
                        [] ->
                            let
                                requests =
                                    siteMetadata
                                        |> Result.andThen
                                            (\metadata ->
                                                staticResponseForPage metadata config.view
                                            )

                                staticResponses : StaticResponses
                                staticResponses =
                                    case requests of
                                        Ok okRequests ->
                                            staticResponsesInit okRequests

                                        Err errors ->
                                            -- TODO need to handle errors better?
                                            staticResponsesInit []

                                ( updatedRawResponses, effect ) =
                                    sendStaticResponsesIfDone mode secrets Dict.empty [] staticResponses config.manifest
                            in
                            ( Model staticResponses secrets [] updatedRawResponses mode |> toModel
                            , effect
                            )

                        pageErrors ->
                            let
                                requests =
                                    siteMetadata
                                        |> Result.andThen
                                            (\metadata ->
                                                staticResponseForPage metadata config.view
                                            )

                                staticResponses : StaticResponses
                                staticResponses =
                                    case requests of
                                        Ok okRequests ->
                                            staticResponsesInit okRequests

                                        Err errors ->
                                            -- TODO need to handle errors better?
                                            staticResponsesInit []
                            in
                            updateAndSendPortIfDone
                                (Model
                                    staticResponses
                                    secrets
                                    (pageErrors |> List.map MetadataDecodeError)
                                    Dict.empty
                                    mode
                                )
                                toModel
                                config.manifest

                Err metadataParserErrors ->
                    updateAndSendPortIfDone
                        (Model Dict.empty
                            secrets
                            (metadataParserErrors
                                |> List.map Tuple.second
                                |> List.map MetadataDecodeError
                            )
                            Dict.empty
                            mode
                        )
                        toModel
                        config.manifest

        Err error ->
            updateAndSendPortIfDone
                (Model Dict.empty
                    SecretsDict.masked
                    [ InternalError <|
                        { title = "Internal Error"
                        , message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ]
                        }
                    ]
                    Dict.empty
                    Dev
                )
                toModel
                config.manifest


updateAndSendPortIfDone : Model -> (Model -> model) -> Manifest.Config pathKey -> ( model, Effect pathKey )
updateAndSendPortIfDone model toModel manifest =
    let
        ( updatedAllRawResponses, effect ) =
            sendStaticResponsesIfDone
                model.mode
                model.secrets
                model.allRawResponses
                model.errors
                model.staticResponses
                manifest
    in
    ( { model | allRawResponses = updatedAllRawResponses } |> toModel
    , effect
    )


type alias PageErrors =
    Dict String String


update :
    Result (List BuildError) (List ( PagePath pathKey, metadata ))
    ->
        { config
            | view :
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
            , manifest : Manifest.Config pathKey
        }
    -> Msg
    -> Model
    -> ( Model, Effect pathKey )
update siteMetadata config msg model =
    case msg of
        GotStaticHttpResponse { request, response } ->
            let
                _ =
                    log "Got response" request.masked.url

                updatedModel =
                    (case response of
                        Ok okResponse ->
                            staticResponsesUpdate
                                { request = request
                                , response =
                                    response |> Result.mapError (\_ -> ())
                                }
                                model

                        Err error ->
                            { model
                                | errors =
                                    model.errors
                                        ++ [ FailedStaticHttpRequestError
                                                { title = "Static HTTP Error"
                                                , message =
                                                    [ Terminal.text "I got an error making an HTTP request to this URL: "

                                                    -- TODO include HTTP method, headers, and body
                                                    , Terminal.yellow <| Terminal.text request.masked.url
                                                    , Terminal.text "\n\n"
                                                    , case error of
                                                        Http.BadStatus code ->
                                                            Terminal.text <| "Bad status: " ++ String.fromInt code

                                                        Http.BadUrl _ ->
                                                            -- TODO include HTTP method, headers, and body
                                                            Terminal.text <| "Invalid url: " ++ request.masked.url

                                                        Http.Timeout ->
                                                            Terminal.text "Timeout"

                                                        Http.NetworkError ->
                                                            Terminal.text "Network error"

                                                        Http.BadBody string ->
                                                            Terminal.text "Unable to parse HTTP response body"
                                                    ]
                                                }
                                           ]
                            }
                    )
                        |> staticResponsesUpdate
                            -- TODO for hash pass in RequestDetails here
                            { request = request
                            , response =
                                response |> Result.mapError (\_ -> ())
                            }

                ( updatedAllRawResponses, effect ) =
                    sendStaticResponsesIfDone updatedModel.mode updatedModel.secrets updatedModel.allRawResponses updatedModel.errors updatedModel.staticResponses config.manifest
            in
            ( { updatedModel | allRawResponses = updatedAllRawResponses }
            , effect
            )


dictCompact : Dict String (Maybe a) -> Dict String a
dictCompact dict =
    dict
        |> Dict.Extra.filterMap (\key value -> value)


performStaticHttpRequests : Dict String (Maybe String) -> SecretsDict -> List ( String, StaticHttp.Request a ) -> Result (List Error) (List { unmasked : RequestDetails, masked : RequestDetails })
performStaticHttpRequests allRawResponses secrets staticRequests =
    staticRequests
        |> List.map
            (\( pagePath, request ) ->
                StaticHttpRequest.resolveUrls request
                    (allRawResponses
                        |> dictCompact
                    )
                    |> Tuple.second
            )
        |> List.concat
        -- TODO prevent duplicates... can't because Set needs comparable
        --        |> Set.fromList
        --        |> Set.toList
        |> List.map
            (\urlBuilder ->
                Secrets.lookup secrets urlBuilder
                    |> Result.mapError MissingSecrets
                    |> Result.map
                        (\unmasked ->
                            { unmasked = unmasked, masked = Secrets.maskedLookup urlBuilder }
                        )
            )
        |> combineMultipleErrors


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


staticResponsesInit : List ( PagePath pathKey, StaticHttp.Request value ) -> StaticResponses
staticResponsesInit list =
    list
        |> List.map
            (\( path, staticRequest ) ->
                ( PagePath.toString path
                , NotFetched (staticRequest |> StaticHttp.map (\_ -> ())) Dict.empty
                )
            )
        |> Dict.fromList


hashUrl : RequestDetails -> String
hashUrl requestDetails =
    "["
        ++ requestDetails.method
        ++ "]"
        ++ requestDetails.url
        ++ String.join "," (requestDetails.headers |> List.map (\( key, value ) -> key ++ " : " ++ value))


staticResponsesUpdate : { request : { masked : RequestDetails, unmasked : RequestDetails }, response : Result () String } -> Model -> Model
staticResponsesUpdate newEntry model =
    let
        updatedAllResponses =
            model.allRawResponses
                |> Dict.insert (hashUrl newEntry.request.masked) (Just (newEntry.response |> Result.withDefault "TODO"))
    in
    { model
        | allRawResponses = updatedAllResponses
        , staticResponses =
            model.staticResponses
                |> Dict.map
                    (\pageUrl entry ->
                        case entry of
                            NotFetched request rawResponses ->
                                let
                                    realUrls =
                                        StaticHttpRequest.resolveUrls request
                                            (updatedAllResponses |> dictCompact)
                                            |> Tuple.second
                                            |> List.map Secrets.maskedLookup
                                            |> List.map hashUrl

                                    includesUrl =
                                        List.member (hashUrl newEntry.request.masked)
                                            realUrls
                                in
                                if includesUrl |> log "includesUrl" then
                                    let
                                        updatedRawResponses =
                                            rawResponses
                                                |> Dict.insert (hashUrl newEntry.request.masked) newEntry.response
                                    in
                                    NotFetched request updatedRawResponses

                                else
                                    entry
                    )
    }


printKeys : String -> Dict String a -> Dict String a
printKeys message dict =
    let
        _ =
            log message (dict |> Dict.keys)
    in
    dict


sendStaticResponsesIfDone : Mode -> SecretsDict -> Dict String (Maybe String) -> List Error -> StaticResponses -> Manifest.Config pathKey -> ( Dict String (Maybe String), Effect pathKey )
sendStaticResponsesIfDone mode secrets allRawResponses errors staticResponses manifest =
    let
        pendingRequests =
            staticResponses
                |> Dict.toList
                |> List.any
                    (\( path, entry ) ->
                        case entry of
                            NotFetched request rawResponses ->
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

                                    hasPermanentError =
                                        StaticHttpRequest.permanentError request usableRawResponses
                                            |> Maybe.map (\_ -> True)
                                            |> Maybe.withDefault False

                                    hasPermanentHttpError =
                                        errors
                                            |> List.any
                                                (\error ->
                                                    case error of
                                                        FailedStaticHttpRequestError _ ->
                                                            True

                                                        _ ->
                                                            False
                                                )

                                    ( allUrlsKnown, knownUrlsToFetch ) =
                                        StaticHttpRequest.resolveUrls request
                                            (rawResponses |> Dict.map (\key value -> value |> Result.withDefault ""))

                                    fetchedAllKnownUrls =
                                        (knownUrlsToFetch
                                            |> List.map Secrets.maskedLookup
                                            |> List.map hashUrl
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
                                StaticHttpRequest.permanentError request
                                    usableRawResponses

                            decoderErrors =
                                maybePermanentError
                                    |> Maybe.map (StaticHttpRequest.toBuildError path)
                                    |> Maybe.map FailedStaticHttpRequestError
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
                                Dict.union allRawResponses (dictOfNewUrlsToPerform |> printKeys "dictOfNew")
                                    |> printKeys "COMBINED"

                            dictOfNewUrlsToPerform =
                                urlsToPerform
                                    |> List.map .masked
                                    |> List.map hashUrl
                                    |> List.map (\hashedUrl -> ( hashedUrl, Nothing ))
                                    |> Dict.fromList

                            maskedToUnmasked : Dict String { masked : RequestDetails, unmasked : RequestDetails }
                            maskedToUnmasked =
                                urlsToPerform
                                    --                                    |> List.map (\secureUrl -> ( Pages.Internal.Secrets.masked secureUrl, secureUrl ))
                                    |> List.map
                                        (\secureUrl ->
                                            --                                            ( hashUrl secureUrl, { unmasked = secureUrl, masked = secureUrl } )
                                            ( hashUrl secureUrl.masked, secureUrl )
                                        )
                                    |> Dict.fromList

                            alreadyPerformed =
                                allRawResponses
                                    |> Dict.keys
                                    |> Set.fromList
                                    |> log "already perf"

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
                            (Errors <| errorsToString (error ++ failedRequests ++ errors))
                        )
        in
        ( updatedAllRawResponses, newEffect )

    else
        let
            updatedAllRawResponses =
                Dict.empty
        in
        ( updatedAllRawResponses
        , SendJsData
            (if List.isEmpty errors && List.isEmpty failedRequests then
                Success
                    (ToJsSuccessPayload
                        (encodeStaticResponses mode staticResponses)
                        manifest
                    )

             else
                Errors <| errorsToString (failedRequests ++ errors)
            )
        )


errorsToString : List Error -> String
errorsToString errors =
    errors
        |> List.map errorToString
        |> String.join "\n\n"


errorToString : Error -> String
errorToString error =
    case error of
        MissingSecrets buildErrors ->
            buildErrors
                |> List.map
                    (\buildError ->
                        banner "Missing Secret" ++ buildError.message |> Terminal.toString
                    )
                |> String.join "\n\n"

        MetadataDecodeError buildError ->
            banner "Metadata Decode Error" ++ buildError.message |> Terminal.toString

        InternalError buildError ->
            banner "Internal Error" ++ buildError.message |> Terminal.toString

        FailedStaticHttpRequestError buildError ->
            banner "Failed Static Http Error" ++ buildError.message |> Terminal.toString


banner : String -> List Terminal.Text
banner title =
    [ Terminal.cyan <|
        Terminal.text ("-- " ++ String.toUpper title ++ " ----------------------------------------------------- elm-pages")
    , Terminal.text "\n\n"
    ]


encodeStaticResponses : Mode -> StaticResponses -> Dict String (Dict String String)
encodeStaticResponses mode staticResponses =
    staticResponses
        |> Dict.map
            (\path result ->
                case result of
                    NotFetched request rawResponsesDict ->
                        let
                            relevantResponses =
                                rawResponsesDict
                                    |> Dict.map
                                        (\key value ->
                                            value
                                                -- TODO avoid running this code at all if there are errors here
                                                |> Result.withDefault ""
                                        )

                            strippedResponses : Dict String String
                            strippedResponses =
                                -- TODO should this return an Err and handle that here?
                                StaticHttpRequest.strippedResponses request relevantResponses
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
