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
    { staticResponses : StaticResponses, secrets : Secrets }


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
                |> Result.mapError
                    (\error ->
                        error
                            |> Dict.toList
                            |> List.map (\( path, errorString ) -> errorString)
                    )
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


init toModel contentCache siteMetadata config cliMsgConstructor flags =
    case Decode.decodeValue (Decode.field "secrets" Secrets.decoder) flags |> Debug.log "SECRETS" of
        Ok secrets ->
            (case contentCache of
                Ok _ ->
                    case contentCache |> ContentCache.pagesWithErrors of
                        Just pageErrors ->
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
                            case Decode.decodeValue (Decode.field "secrets" Decode.string) flags of
                                Ok _ ->
                                    ( Model staticResponses secrets |> toModel
                                    , SendJsData
                                        (Errors <|
                                            pageErrorsToString
                                                (mapKeys
                                                    (\key -> "/" ++ String.join "/" key)
                                                    pageErrors
                                                )
                                        )
                                    )

                                Err error ->
                                    ( Model staticResponses Secrets.empty |> toModel
                                    , SendJsData
                                        (Errors <| "Failed to parse flags: " ++ Decode.errorToString error)
                                    )

                        Nothing ->
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
                                            ( Model staticResponses secrets |> toModel, staticRequestsEffect )

                                        Err error ->
                                            ( Model staticResponses secrets |> toModel
                                            , Errors "TODO real error here" |> SendJsData
                                              -- TODO send real error message
                                            )

                                --                                |> Cmd.map cliMsgConstructor
                                Err errors ->
                                    ( Model staticResponses secrets |> toModel, NoEffect )

                Err error ->
                    ( Model Dict.empty secrets |> toModel
                    , SendJsData
                        (Errors <|
                            pageErrorsToString
                                (mapKeys
                                    (\key -> "/" ++ String.join "/" key)
                                    error
                                )
                        )
                    )
             --                (Errors error)
             --                (Json.Encode.object
             --                    [ ( "errors", encodeErrors error )
             --                    , ( "manifest", Manifest.toJson config.manifest )
             --                    ]
             --                )
            )

        Err error ->
            ( Model Dict.empty Secrets.empty |> toModel
            , SendJsData
                (Errors <| "Failed to parse flags: " ++ Decode.errorToString error)
            )


type alias PageErrors =
    Dict String String


pageErrorsToString : PageErrors -> String
pageErrorsToString pageErrors =
    "TODO"


update :
    Result (List String) (List ( PagePath pathKey, metadata ))
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
                            case response of
                                Ok okResponse ->
                                    model.staticResponses
                                        |> staticResponsesUpdate
                                            { url = url
                                            , response =
                                                okResponse
                                            }

                                Err error ->
                                    Debug.todo (Debug.toString error)

                        Err errors ->
                            Debug.todo "TODO handle error"
            in
            ( { model | staticResponses = staticResponses }
            , sendStaticResponsesIfDone staticResponses config.manifest
            )


performStaticHttpRequests : Secrets -> List ( PagePath pathKey, StaticHttp.Request a ) -> Result String (Effect pathKey)
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
            )
        |> combineSimple
        |> Result.map Batch


combineSimple : List (Result x a) -> Result x (List a)
combineSimple =
    List.foldr (Result.map2 (::)) (Ok [])


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


staticResponsesUpdate : { url : String, response : String } -> StaticResponses -> StaticResponses
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

                    _ ->
                        entry
            )


sendStaticResponsesIfDone : StaticResponses -> Manifest.Config pathKey -> Effect pathKey
sendStaticResponsesIfDone staticResponses manifest =
    let
        pendingRequests =
            staticResponses
                |> Dict.toList
                |> List.any
                    (\( path, result ) ->
                        case result of
                            NotFetched (StaticHttpRequest.Request ( urls, _ )) rawResponses ->
                                if List.length urls == (rawResponses |> Dict.keys |> List.length) then
                                    False

                                else
                                    True

                            _ ->
                                False
                    )

        failedRequests =
            staticResponses
                |> Dict.Extra.filterMap
                    (\path result ->
                        case result of
                            NotFetched (StaticHttpRequest.Request ( urls, lookup )) rawResponses ->
                                case lookup rawResponses of
                                    Ok _ ->
                                        Nothing

                                    Err error ->
                                        Just error

                            _ ->
                                Nothing
                    )
    in
    if pendingRequests then
        NoEffect

    else
        SendJsData
            (if failedRequests |> Dict.isEmpty then
                Success
                    (ToJsSuccessPayload
                        (encodeStaticResponses staticResponses)
                        manifest
                    )

             else
                Errors <| pageErrorsToString failedRequests
            )


encodeStaticResponses : StaticResponses -> Dict String (Dict String String)
encodeStaticResponses staticResponses =
    staticResponses
        |> Dict.map
            (\path result ->
                (case result of
                    NotFetched (StaticHttpRequest.Request ( urls, lookup )) rawResponsesDict ->
                        rawResponsesDict

                    ErrorFetching request ->
                        --                        Json.Encode.string "ErrorFetching"
                        Dict.empty

                    ErrorDecoding request ->
                        Dict.empty
                 --                        Json.Encode.string "ErrorDecoding"
                 --                        ( "", "" )
                )
            )



--        |> Dict.fromList


type alias StaticResponses =
    Dict String StaticHttpResult


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String String)
    | ErrorFetching (StaticHttpRequest.Request ())
    | ErrorDecoding (StaticHttpRequest.Request ())


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
        Result (List String)
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
