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
import Secrets exposing (Secrets)
import Set
import StaticHttp
import TerminalText as Terminal
import Url exposing (Url)


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
    | FetchHttp String String
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
    { staticResponses : StaticResponses, secrets : Secrets, errors : List Error }


type Error
    = MissingSecret BuildError
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
    = GotStaticHttpResponse { url : String, response : Result Http.Error String }


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
                init toModel contentCache siteMetadata config cliMsgConstructor flags
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

        FetchHttp unmaskedUrl maskedUrl ->
            Http.get
                { url = unmaskedUrl
                , expect =
                    Http.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { url = maskedUrl
                                , response = response
                                }
                                |> cliMsgConstructor
                        )
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
    -> f
    -> Decode.Value
    -> ( model, Effect pathKey )
init toModel contentCache siteMetadata config cliMsgConstructor flags =
    case Decode.decodeValue (Decode.field "secrets" Secrets.decoder) flags of
        Ok secrets ->
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
                                            Dict.empty
                            in
                            case requests of
                                Ok okRequests ->
                                    case performStaticHttpRequests secrets okRequests of
                                        Ok staticRequestsEffect ->
                                            ( Model staticResponses secrets [] |> toModel
                                            , Batch
                                                [ staticRequestsEffect
                                                , sendStaticResponsesIfDone [] staticResponses config.manifest
                                                ]
                                            )

                                        Err errors ->
                                            ( Model staticResponses secrets errors |> toModel
                                              -- TODO write a test case for this
                                              -- TODO should this be using Dict.empty, or some unrecoverable error flag in Model?
                                            , sendStaticResponsesIfDone errors Dict.empty config.manifest
                                            )

                                Err errors ->
                                    -- TODO print errors here?
                                    ( Model staticResponses
                                        secrets
                                        (errors |> List.map InternalError)
                                        |> toModel
                                    , NoEffect
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
                                            Dict.empty
                            in
                            ( Model staticResponses secrets (pageErrors |> List.map MetadataDecodeError) |> toModel
                            , sendStaticResponsesIfDone
                                (pageErrors |> List.map MetadataDecodeError)
                                staticResponses
                                config.manifest
                            )

                Err metadataParserErrors ->
                    ( Model Dict.empty
                        secrets
                        (metadataParserErrors
                            |> List.map Tuple.second
                            |> List.map MetadataDecodeError
                        )
                        |> toModel
                    , sendStaticResponsesIfDone
                        (metadataParserErrors
                            |> List.map Tuple.second
                            |> List.map MetadataDecodeError
                        )
                        Dict.empty
                        config.manifest
                    )

        Err error ->
            ( Model Dict.empty
                Secrets.empty
                [ InternalError <| { message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ] }
                ]
                |> toModel
            , sendStaticResponsesIfDone
                [ InternalError <| { message = [ Terminal.text <| "Failed to parse flags: " ++ Decode.errorToString error ] }
                ]
                Dict.empty
                config.manifest
            )


type alias PageErrors =
    Dict String String


pageErrorsToString : PageErrors -> String
pageErrorsToString pageErrors =
    pageErrors
        |> Dict.toList
        |> List.map
            (\( pagePath, error ) ->
                pagePath
                    ++ "\n\n"
                    ++ error
            )
        |> String.join "\n\n"


update :
    Result (List BuildError) (List ( PagePath pathKey, metadata ))
    ->
        { config
            | --            update : userMsg -> userModel -> ( userModel, Cmd userMsg )
              --            , subscriptions : userModel -> Sub userMsg
              view :
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

            --            , document : Pages.Document.Document metadata view
            --            , content : Content
            --            , toJsPort : Json.Encode.Value -> Cmd Never
            , manifest : Manifest.Config pathKey

            --            , canonicalSiteUrl : String
            --            , pathKey : pathKey
            --            , onPageChange : PagePath pathKey -> userMsg
        }
    -> Msg
    -> Model
    -> ( Model, Effect pathKey )
update siteMetadata config msg model =
    case msg of
        GotStaticHttpResponse { url, response } ->
            let
                updatedModel =
                    case response of
                        Ok okResponse ->
                            { model
                                | staticResponses =
                                    model.staticResponses
                                        |> staticResponsesUpdate
                                            { url = url
                                            , response =
                                                response |> Result.mapError (\_ -> ())
                                            }
                            }

                        Err error ->
                            { model
                                | errors =
                                    model.errors
                                        ++ [ FailedStaticHttpRequestError
                                                { message =
                                                    [ Terminal.text "I got an error making an HTTP request to this URL: "
                                                    , Terminal.yellow <| Terminal.text url
                                                    , Terminal.text "\n\n"
                                                    , case error of
                                                        Http.BadStatus code ->
                                                            Terminal.text <| "Bad status: " ++ String.fromInt code

                                                        Http.BadUrl _ ->
                                                            Terminal.text <| "Invalid url: " ++ url

                                                        Http.Timeout ->
                                                            Terminal.text "Timeout"

                                                        Http.NetworkError ->
                                                            Terminal.text "Network error"

                                                        Http.BadBody string ->
                                                            Terminal.text "Network error"
                                                    ]
                                                }
                                           ]
                                , staticResponses =
                                    model.staticResponses
                                        |> staticResponsesUpdate
                                            { url = url
                                            , response =
                                                response |> Result.mapError (\_ -> ())
                                            }
                            }
            in
            ( updatedModel
            , sendStaticResponsesIfDone updatedModel.errors updatedModel.staticResponses config.manifest
            )


performStaticHttpRequests : Secrets -> List ( PagePath pathKey, StaticHttp.Request a ) -> Result (List Error) (Effect pathKey)
performStaticHttpRequests secrets staticRequests =
    staticRequests
        |> List.map
            (\( pagePath, StaticHttpRequest.Request ( urls, lookup ) ) ->
                urls
            )
        |> List.concat
        -- TODO prevent duplicates... can't because Set needs comparable
        --        |> Set.fromList
        --        |> Set.toList
        |> List.map
            (\urlBuilder ->
                urlBuilder secrets
                    |> Result.map
                        (\unmasked ->
                            FetchHttp unmasked (Secrets.useFakeSecrets urlBuilder)
                        )
                    |> Result.mapError MissingSecret
            )
        |> combineMultipleErrors
        |> Result.map Batch


combineSimple : List (Result x a) -> Result x (List a)
combineSimple =
    List.foldr (Result.map2 (::)) (Ok [])


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


staticResponsesUpdate : { url : String, response : Result () String } -> StaticResponses -> StaticResponses
staticResponsesUpdate newEntry staticResponses =
    staticResponses
        |> Dict.map
            (\pageUrl entry ->
                case entry of
                    NotFetched (StaticHttpRequest.Request ( urls, lookup )) rawResponses ->
                        let
                            realUrls =
                                urls
                                    |> List.map
                                        (\urlBuilder ->
                                            Secrets.useFakeSecrets urlBuilder
                                        )

                            includesUrl =
                                List.member newEntry.url realUrls
                        in
                        if includesUrl then
                            let
                                updatedRawResponses =
                                    rawResponses
                                        |> Dict.insert newEntry.url newEntry.response
                            in
                            NotFetched (StaticHttpRequest.Request ( urls, lookup )) updatedRawResponses

                        else
                            entry
            )


sendStaticResponsesIfDone : List Error -> StaticResponses -> Manifest.Config pathKey -> Effect pathKey
sendStaticResponsesIfDone errors staticResponses manifest =
    let
        pendingRequests =
            staticResponses
                |> Dict.toList
                |> List.any
                    (\( path, entry ) ->
                        case entry of
                            NotFetched (StaticHttpRequest.Request ( urls, _ )) rawResponses ->
                                if List.length urls == (rawResponses |> Dict.keys |> List.length) then
                                    False

                                else
                                    True
                    )

        failedRequests =
            staticResponses
                |> Dict.toList
                |> List.concatMap
                    (\( path, NotFetched (StaticHttpRequest.Request ( urls, lookup )) rawResponses ) ->
                        case rawResponsesResult rawResponses of
                            Ok responses ->
                                case lookup responses of
                                    Ok _ ->
                                        []

                                    Err error ->
                                        { message =
                                            [ Terminal.text path
                                            , Terminal.text "\n\n"
                                            , Terminal.text error
                                            ]
                                        }
                                            -- TODO should this be a decoding http error instead?
                                            |> FailedStaticHttpRequestError
                                            |> List.singleton

                            Err error ->
                                error
                                    |> List.map FailedStaticHttpRequestError
                    )
    in
    if pendingRequests then
        NoEffect

    else
        SendJsData
            (if List.isEmpty errors && List.isEmpty failedRequests then
                Success
                    (ToJsSuccessPayload
                        (encodeStaticResponses staticResponses)
                        manifest
                    )

             else
                Errors <| errorsToString (failedRequests ++ errors)
            )


rawResponsesResult : Dict String (Result () String) -> Result (List BuildError) (Dict String String)
rawResponsesResult dict =
    dict
        |> Dict.toList
        |> List.map
            (\( key, result ) ->
                --                Debug.todo ""
                result
                    |> Result.map
                        (\okValue ->
                            ( key, okValue )
                        )
                    |> Result.mapError
                        (\_ ->
                            { message = []
                            }
                        )
            )
        |> combineMultipleErrors
        |> Result.map Dict.fromList


errorsToString : List Error -> String
errorsToString errors =
    errors
        |> List.map errorToString
        |> String.join "\n\n"


errorToString : Error -> String
errorToString error =
    case error of
        MissingSecret buildError ->
            banner "Missing Secret" :: buildError.message |> Terminal.toString

        MetadataDecodeError buildError ->
            banner "Metadata Decode Error" :: buildError.message |> Terminal.toString

        InternalError buildError ->
            banner "Internal Error" :: buildError.message |> Terminal.toString

        FailedStaticHttpRequestError buildError ->
            banner "Failed Static Http Error" :: buildError.message |> Terminal.toString


banner title =
    Terminal.cyan <|
        Terminal.text ("-- " ++ String.toUpper title ++ " ----------------------------------------------------- elm-pages\n\n")


encodeStaticResponses : StaticResponses -> Dict String (Dict String String)
encodeStaticResponses staticResponses =
    staticResponses
        |> Dict.map
            (\path result ->
                case result of
                    NotFetched (StaticHttpRequest.Request ( urls, lookup )) rawResponsesDict ->
                        rawResponsesDict
                            |> Dict.map
                                (\key value ->
                                    value
                                        -- TODO avoid running this code at all if there are errors here
                                        |> Result.withDefault ""
                                )
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


encodeErrors : Dict (List String) String -> Json.Encode.Value
encodeErrors errors =
    errors
        |> Json.Encode.dict
            (\path -> "/" ++ String.join "/" path)
            (\errorsForPath -> Json.Encode.string errorsForPath)


mapKeys : (comparable -> comparable1) -> Dict comparable v -> Dict comparable1 v
mapKeys keyMapper dict =
    Dict.foldl
        (\k v acc ->
            Dict.insert (keyMapper k) v acc
        )
        Dict.empty
        dict
