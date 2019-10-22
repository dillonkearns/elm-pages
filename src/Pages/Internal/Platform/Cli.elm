module Pages.Internal.Platform.Cli exposing (Content, Flags, Model, Msg, Page, Parser, Program, cliApplication)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import Mark
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttpRequest as StaticHttpRequest
import Url exposing (Url)


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Program userModel userMsg metadata view =
    Platform.Program Flags (Model userModel userMsg metadata view) (Msg userMsg metadata view)


type alias Flags =
    ()


type Msg userMsg metadata view
    = AppMsg (AppMsg userMsg metadata view)
    | CliMsg CliMsgType


type AppMsg userMsg metadata view
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error (ContentCache metadata view))
    | UpdateCacheAndUrl Url (Result Http.Error (ContentCache metadata view))


type Model userModel userMsg metadata view
    = Model (ModelDetails userModel metadata view)
    | CliModel


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


type CliMsgType
    = GotStaticHttpResponse { url : String, response : Result Http.Error String }


cliApplication :
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
    -> Program userModel userMsg metadata view
cliApplication config =
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
                ( CliModel
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
                                config.toJsPort
                                    (Json.Encode.object
                                        [ ( "errors", encodeErrors pageErrors )
                                        , ( "manifest", Manifest.toJson config.manifest )
                                        , ( "pages", encodeStaticResponses staticResponses )
                                        ]
                                    )
                                    |> Cmd.map never

                            --(Msg userMsg metadata view)
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
                                Cmd.batch
                                    [ case requests of
                                        Ok okRequests ->
                                            performStaticHttpRequests okRequests
                                                |> Cmd.map CliMsg

                                        Err errors ->
                                            Cmd.none
                                    ]

                    Err error ->
                        config.toJsPort
                            (Json.Encode.object
                                [ ( "errors", encodeErrors error )
                                , ( "manifest", Manifest.toJson config.manifest )
                                ]
                            )
                            |> Cmd.map never
                )
        , update =
            \msg model ->
                case msg of
                    CliMsg (GotStaticHttpResponse { url, response }) ->
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
                        , config.toJsPort
                            (Json.Encode.object
                                [ ( "manifest", Manifest.toJson config.manifest )
                                , ( "pages", encodeStaticResponses staticResponses )
                                ]
                            )
                            |> Cmd.map never
                        )

                    _ ->
                        ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


performStaticHttpRequests : List ( PagePath pathKey, ( StaticHttp.Request, Decode.Value -> Result error value ) ) -> Cmd CliMsgType
performStaticHttpRequests staticRequests =
    staticRequests
        |> List.map
            (\( pagePath, ( StaticHttpRequest.Request { url }, fn ) ) ->
                Http.get
                    { url = url
                    , expect =
                        Http.expectString
                            (\response ->
                                GotStaticHttpResponse
                                    { url = url
                                    , response = response
                                    }
                            )
                    }
            )
        |> Cmd.batch


staticResponsesInit : List ( PagePath pathKey, ( StaticHttp.Request, Decode.Value -> Result error value ) ) -> StaticResponses
staticResponsesInit list =
    list
        |> List.map (\( path, ( staticRequest, fn ) ) -> ( PagePath.toString path, NotFetched staticRequest ))
        |> Dict.fromList


staticResponsesUpdate : { url : String, response : String } -> StaticResponses -> StaticResponses
staticResponsesUpdate newEntry staticResponses =
    staticResponses
        |> Dict.update newEntry.url
            (\maybeEntry ->
                SuccessfullyFetched (StaticHttpRequest.Request { url = newEntry.url }) newEntry.response
                    |> Just
            )


encodeStaticResponses : StaticResponses -> Json.Encode.Value
encodeStaticResponses staticResponses =
    staticResponses
        |> Dict.toList
        |> List.map
            (\( path, result ) ->
                ( path
                , case result of
                    NotFetched (StaticHttpRequest.Request { url }) ->
                        Json.Encode.object
                            [ ( url
                              , Json.Encode.string ""
                              )
                            ]

                    SuccessfullyFetched (StaticHttpRequest.Request { url }) jsonResponseString ->
                        Json.Encode.object
                            [ ( url
                              , Json.Encode.string jsonResponseString
                              )
                            ]

                    ErrorFetching request ->
                        Json.Encode.string "ErrorFetching"

                    ErrorDecoding request ->
                        Json.Encode.string "ErrorDecoding"
                )
            )
        |> Json.Encode.object


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
