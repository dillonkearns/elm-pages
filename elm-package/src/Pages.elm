module Pages exposing (Flags, Model, Msg, Page, Parser, Program, application, cliApplication)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Http
import Json.Decode
import Json.Encode
import Mark
import Pages.Content as Content exposing (Content)
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Manifest as Manifest
import Result.Extra
import Task exposing (Task)
import Url exposing (Url)


type alias Page metadata view =
    { metadata : metadata
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Program userModel userMsg metadata view =
    Platform.Program Flags (Model userModel userMsg metadata view) (Msg userMsg metadata view)


mainView :
    (userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> { title : String, body : Html userMsg }
mainView pageView model =
    case model.contentCache of
        Ok site ->
            pageViewOrError pageView model model.contentCache

        -- TODO these lookup helpers should not need it to be a Result
        Err errorView ->
            { title = "Error parsing"
            , body = errorView
            }


pageViewOrError :
    (userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> ContentCache userMsg metadata view
    -> { title : String, body : Html userMsg }
pageViewOrError pageView model cache =
    case ContentCache.lookup cache model.url of
        Just entry ->
            case entry of
                ContentCache.Parsed metadata viewResult ->
                    case viewResult of
                        Ok viewList ->
                            pageView model.userModel
                                (Result.map ContentCache.extractMetadata cache
                                    |> Result.withDefault []
                                 -- TODO handle error better
                                )
                                { metadata = metadata
                                , view = viewList
                                }

                        Err error ->
                            { title = "Parsing error"
                            , body = Html.text error
                            }

                ContentCache.NeedContent extension _ ->
                    { title = "", body = Html.text "" }

                ContentCache.Unparsed extension _ _ ->
                    { title = "", body = Html.text "" }

        Nothing ->
            { title = "Page not found"
            , body =
                Html.div []
                    [ Html.text "Page not found. Valid routes:\n\n"
                    , cache
                        |> ContentCache.routesForCache
                        |> String.join ", "
                        |> Html.text
                    ]
            }


view :
    Content
    -> (userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg })
    -> ModelDetails userModel userMsg metadata view
    -> Browser.Document (Msg userMsg metadata view)
view content pageView model =
    let
        { title, body } =
            mainView pageView model
    in
    { title = title
    , body =
        [ body
            |> Html.map UserMsg
        ]
    }


encodeHeads : List Head.Tag -> Json.Encode.Value
encodeHeads head =
    Json.Encode.list Head.toJson head


type alias Flags =
    { imageAssets : Json.Decode.Value
    }


combineTupleResults :
    List ( List String, Result error success )
    -> Result error (List ( List String, success ))
combineTupleResults input =
    input
        |> List.map
            (\( path, result ) ->
                result
                    |> Result.map (\success -> ( path, success ))
            )
        |> Result.Extra.combine


init :
    Pages.Document.Document metadata view
    -> (Json.Encode.Value -> Cmd (Msg userMsg metadata view))
    -> (metadata -> List Head.Tag)
    -> Content
    -> ( userModel, Cmd userMsg )
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel userMsg metadata view, Cmd (Msg userMsg metadata view) )
init document toJsPort head content initUserModel flags url key =
    let
        ( userModel, userCmd ) =
            initUserModel

        imageAssets =
            Json.Decode.decodeValue
                (Json.Decode.dict Json.Decode.string)
                flags.imageAssets
                |> Result.withDefault Dict.empty

        contentCache =
            ContentCache.init document content
    in
    case contentCache of
        Ok okCache ->
            ( { key = key
              , url = url
              , imageAssets = imageAssets
              , userModel = userModel
              , contentCache = contentCache
              }
            , Cmd.batch
                ([ Content.lookup (ContentCache.extractMetadata okCache) url
                    |> Maybe.map head
                    |> Maybe.map encodeHeads
                    |> Maybe.map toJsPort
                 , userCmd |> Cmd.map UserMsg |> Just
                 , contentCache
                    |> ContentCache.lazyLoad document url
                    |> Task.attempt UpdateCache
                    |> Just
                 ]
                    |> List.filterMap identity
                )
            )

        Err _ ->
            ( { key = key
              , url = url
              , imageAssets = imageAssets
              , userModel = userModel
              , contentCache = contentCache
              }
            , Cmd.batch
                [ userCmd |> Cmd.map UserMsg
                ]
              -- TODO handle errors better
            )


type Msg userMsg metadata view
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error (ContentCache userMsg metadata view))
    | UpdateCacheAndUrl Url (Result Http.Error (ContentCache userMsg metadata view))


type Model userModel userMsg metadata view
    = Model (ModelDetails userModel userMsg metadata view)
    | CliModel


type alias ModelDetails userModel userMsg metadata view =
    { key : Browser.Navigation.Key
    , url : Url.Url
    , imageAssets : Dict String String
    , contentCache : ContentCache userMsg metadata view
    , userModel : userModel
    }


update :
    Pages.Document.Document metadata view
    -> (userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg metadata view
    -> ModelDetails userModel userMsg metadata view
    -> ( ModelDetails userModel userMsg metadata view, Cmd (Msg userMsg metadata view) )
update document userUpdate msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    let
                        navigatingToSamePage =
                            url.path == model.url.path
                    in
                    if navigatingToSamePage then
                        -- this is a workaround for an issue with anchor fragment navigation
                        -- see https://github.com/elm/browser/issues/39
                        ( model, Browser.Navigation.load (Url.toString url) )

                    else
                        ( model, Browser.Navigation.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Browser.Navigation.load href )

        UrlChanged url ->
            ( model
            , model.contentCache
                |> ContentCache.lazyLoad document url
                |> Task.attempt (UpdateCacheAndUrl url)
            )

        UserMsg userMsg ->
            let
                ( userModel, userCmd ) =
                    userUpdate userMsg model.userModel
            in
            ( { model | userModel = userModel }, userCmd |> Cmd.map UserMsg )

        UpdateCache cacheUpdateResult ->
            case cacheUpdateResult of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok updatedCache ->
                    ( { model | contentCache = updatedCache }, Cmd.none )

                Err _ ->
                    -- TODO handle error
                    ( model, Cmd.none )

        UpdateCacheAndUrl url cacheUpdateResult ->
            case cacheUpdateResult of
                -- TODO can there be race conditions here? Might need to set something in the model
                -- to keep track of the last url change
                Ok updatedCache ->
                    ( { model | url = url, contentCache = updatedCache }, Cmd.none )

                Err _ ->
                    -- TODO handle error
                    ( { model | url = url }, Cmd.none )


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document view


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg metadata view)
    , head : metadata -> List Head.Tag
    , manifest : Manifest.Config pathKey
    }
    -> Program userModel userMsg metadata view
application config =
    Browser.application
        { init =
            \flags url key ->
                init config.document config.toJsPort config.head config.content config.init flags url key
                    |> Tuple.mapFirst Model
        , view =
            \outerModel ->
                case outerModel of
                    Model model ->
                        view config.content config.view model

                    CliModel ->
                        { title = "Error"
                        , body = [ Html.text "Unexpected state" ]
                        }
        , update =
            \msg outerModel ->
                case outerModel of
                    Model model ->
                        update config.document config.update msg model |> Tuple.mapFirst Model

                    CliModel ->
                        ( outerModel, Cmd.none )
        , subscriptions =
            \outerModel ->
                case outerModel of
                    Model model ->
                        config.subscriptions model.userModel
                            |> Sub.map UserMsg

                    CliModel ->
                        Sub.none
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


cliApplication :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg metadata view)
    , head : metadata -> List Head.Tag
    , manifest : Manifest.Config pathKey
    }
    -> Program userModel userMsg metadata view
cliApplication config =
    Platform.worker
        { init =
            \flags ->
                ( CliModel
                , config.toJsPort (Manifest.toJson config.manifest)
                )
        , update = \msg model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
