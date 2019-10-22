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
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttpRequest as StaticHttpRequest
import Url exposing (Url)


type ToJsPayload pathKey
    = Errors (Dict String String)
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
        |> Codec.variant1 "Errors" Errors (Codec.dict Codec.string)
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
    | FetchHttp StaticHttp.Request
    | Batch (List (Effect pathKey))


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Flags =
    ()


type Model
    = Model


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
                ( StaticHttp.Request
                , Decode.Value
                  ->
                    Result String
                        { view :
                            userModel
                            -> view
                            ->
                                { title : String
                                , body : Html userMsg
                                }
                        , head : List (Head.Tag pathKey)
                        }
                )
        , document : Pages.Document.Document metadata view
        , content : Content
        , toJsPort : Json.Encode.Value -> Cmd Never
        , manifest : Manifest.Config pathKey
        , canonicalSiteUrl : String
        , pathKey : pathKey
        , onPageChange : PagePath pathKey -> userMsg
        }
    --    -> Program userModel userMsg metadata view
    -> Platform.Program () model msg
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
                case narrowMsg msg of
                    Just cliMsg ->
                        update siteMetadata config cliMsg model
                            |> Tuple.mapSecond (perform cliMsgConstructor config.toJsPort)

                    Nothing ->
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

        FetchHttp (StaticHttpRequest.Request { url }) ->
            Http.get
                { url = url
                , expect =
                    Http.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { url = url
                                , response = response
                                }
                                |> cliMsgConstructor
                        )
                }


init toModel contentCache siteMetadata config cliMsgConstructor () =
    ( toModel Model
    , case contentCache of
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
                    SendJsData
                        (Errors
                            (mapKeys
                                (\key -> "/" ++ String.join "/" key)
                                pageErrors
                            )
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
                            performStaticHttpRequests okRequests

                        --                                |> Cmd.map cliMsgConstructor
                        Err errors ->
                            NoEffect

        Err error ->
            SendJsData
                (Errors
                    (mapKeys
                        (\key -> "/" ++ String.join "/" key)
                        error
                    )
                )
      --                (Errors error)
      --                (Json.Encode.object
      --                    [ ( "errors", encodeErrors error )
      --                    , ( "manifest", Manifest.toJson config.manifest )
      --                    ]
      --                )
    )


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
                                    staticResponsesInit okRequests
                                        |> staticResponsesUpdate
                                            { url = url
                                            , response =
                                                okResponse
                                            }

                                Err error ->
                                    Debug.todo "TODO handle error"

                        Err errors ->
                            Dict.empty
            in
            ( model
            , SendJsData
                (Success
                    (ToJsSuccessPayload
                        (encodeStaticResponses staticResponses)
                        config.manifest
                    )
                )
              --                (Json.Encode.object
              --                    [ ( "manifest", Manifest.toJson config.manifest )
              --                    , ( "pages", encodeStaticResponses staticResponses )
              --                    ]
              --                )
            )


performStaticHttpRequests : List ( PagePath pathKey, ( StaticHttp.Request, Decode.Value -> Result error value ) ) -> Effect pathKey
performStaticHttpRequests staticRequests =
    -- @@@@@@@@ TODO
    --    NoEffect
    staticRequests
        |> List.map
            --            (\( pagePath, ( StaticHttpRequest.Request { url }, fn ) ) ->
            (\( pagePath, ( request, fn ) ) ->
                --                Http.get
                --                    { url = url
                --                    , expect =
                --                        Http.expectString
                --                            (\response ->
                --                                GotStaticHttpResponse
                --                                    { url = url
                --                                    , response = response
                --                                    }
                --                            )
                --                    }
                --                NoEffect
                FetchHttp request
            )
        |> Batch


staticResponsesInit : List ( PagePath pathKey, ( StaticHttp.Request, Decode.Value -> Result error value ) ) -> StaticResponses
staticResponsesInit list =
    list
        |> List.map (\( path, ( staticRequest, fn ) ) -> ( PagePath.toString path, NotFetched staticRequest ))
        |> Dict.fromList


staticResponsesUpdate : { url : String, response : String } -> StaticResponses -> StaticResponses
staticResponsesUpdate newEntry staticResponses =
    staticResponses



-- TODO should I change the data structure?
--        |> Dict.update newEntry.url
--            (\maybeEntry ->
--                SuccessfullyFetched (StaticHttpRequest.Request { url = newEntry.url }) newEntry.response
--                    |> Just
--            )


encodeStaticResponses : StaticResponses -> Dict String (Dict String String)
encodeStaticResponses staticResponses =
    staticResponses
        |> Dict.map
            (\path result ->
                (case result of
                    NotFetched (StaticHttpRequest.Request { url }) ->
                        Dict.fromList
                            [ ( url
                              , ""
                              )
                            ]

                    SuccessfullyFetched (StaticHttpRequest.Request { url }) jsonResponseString ->
                        Dict.fromList
                            [ ( url, jsonResponseString ) ]

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
    = NotFetched StaticHttp.Request
    | SuccessfullyFetched StaticHttp.Request String
    | ErrorFetching StaticHttp.Request
    | ErrorDecoding StaticHttp.Request


staticResponseForPage :
    List ( PagePath pathKey, metadata )
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            ( StaticHttp.Request
            , Decode.Value
              ->
                Result String
                    { view :
                        userModel
                        -> view
                        ->
                            { title : String
                            , body : Html userMsg
                            }
                    , head : List (Head.Tag pathKey)
                    }
            )
        )
    ->
        Result (List String)
            (List
                ( PagePath pathKey
                , ( StaticHttp.Request
                  , Decode.Value
                    ->
                        Result String
                            { view :
                                userModel
                                -> view
                                ->
                                    { title : String
                                    , body : Html userMsg
                                    }
                            , head : List (Head.Tag pathKey)
                            }
                  )
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
