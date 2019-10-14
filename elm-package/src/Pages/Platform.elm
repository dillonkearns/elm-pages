module Pages.Platform exposing (Flags, Model, Msg, Page, Parser, Program, application, cliApplication)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Html.Attributes
import Http
import Json.Decode
import Json.Encode
import List.Extra
import Mark
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttpRequest as StaticHttpRequest
import Result.Extra
import Task exposing (Task)
import Url exposing (Url)


dropTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias Program userModel userMsg metadata view =
    Platform.Program Flags (Model userModel userMsg metadata view) (Msg userMsg metadata view)


mainView :
    pathKey
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
        )
    -> ModelDetails userModel metadata view
    -> { title : String, body : Html userMsg }
mainView pathKey pageView model =
    case model.contentCache of
        Ok site ->
            pageViewOrError pathKey pageView model model.contentCache

        -- TODO these lookup helpers should not need it to be a Result
        Err errors ->
            { title = "Error parsing"
            , body = ContentCache.errorView errors
            }


urlToPagePath : pathKey -> Url -> PagePath pathKey
urlToPagePath pathKey url =
    url.path
        |> dropTrailingSlash
        |> String.split "/"
        |> List.drop 1
        |> PagePath.build pathKey


pageViewOrError :
    pathKey
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
        )
    -> ModelDetails userModel metadata view
    -> ContentCache metadata view
    -> { title : String, body : Html userMsg }
pageViewOrError pathKey viewFn model cache =
    case ContentCache.lookup pathKey cache model.url of
        Just ( pagePath, entry ) ->
            case entry of
                ContentCache.Parsed metadata viewResult ->
                    let
                        dummyInputString =
                            "TODO"

                        staticData =
                            (viewFn
                                (cache
                                    |> Result.map (ContentCache.extractMetadata pathKey)
                                    |> Result.withDefault []
                                 -- TODO handle error better
                                )
                                { path = pagePath, frontmatter = metadata }
                                |> .staticRequest
                                |> StaticHttpRequest.parser
                            )
                                dummyInputString

                        pageView =
                            viewFn
                                (cache
                                    |> Result.map (ContentCache.extractMetadata pathKey)
                                    |> Result.withDefault []
                                 -- TODO handle error better
                                )
                                { path = pagePath, frontmatter = metadata }
                                |> .view
                    in
                    case viewResult of
                        Ok viewList ->
                            pageView staticData model.userModel viewList

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
    pathKey
    -> Content
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
        )
    -> ModelDetails userModel metadata view
    -> Browser.Document (Msg userMsg metadata view)
view pathKey content viewFn model =
    let
        { title, body } =
            mainView pathKey viewFn model
    in
    { title = title
    , body =
        [ onViewChangeElement model.url
        , body |> Html.map UserMsg
        ]
    }


onViewChangeElement currentUrl =
    -- this is a hidden tag
    -- it is used from the JS-side to reliably
    -- check when Elm has changed pages
    -- (and completed rendering the view)
    Html.div
        [ Html.Attributes.attribute "data-url" (Url.toString currentUrl)
        , Html.Attributes.attribute "display" "none"
        ]
        []


encodeHeads : String -> String -> List (Head.Tag pathKey) -> Json.Encode.Value
encodeHeads canonicalSiteUrl currentPagePath head =
    Json.Encode.list (Head.toJson canonicalSiteUrl currentPagePath) head


type alias Flags =
    {}


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
    pathKey
    -> String
    -> Pages.Document.Document metadata view
    -> (Json.Encode.Value -> Cmd (Msg userMsg metadata view))
    ->
        (List ( PagePath pathKey, metadata )
         ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
         ->
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
        )
    -> Content
    -> (Maybe (PagePath pathKey) -> ( userModel, Cmd userMsg ))
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel metadata view, Cmd (Msg userMsg metadata view) )
init pathKey canonicalSiteUrl document toJsPort viewFn content initUserModel flags url key =
    let
        contentCache =
            ContentCache.init document content
    in
    case contentCache of
        Ok okCache ->
            let
                ( userModel, userCmd ) =
                    initUserModel maybePagePath

                cmd =
                    case ( maybePagePath, maybeMetadata ) of
                        ( Just pagePath, Just frontmatter ) ->
                            let
                                head =
                                    viewFn
                                        (ContentCache.extractMetadata pathKey okCache)
                                        { path = pagePath
                                        , frontmatter = frontmatter
                                        }
                                        |> .head
                            in
                            Cmd.batch
                                [ head
                                    |> encodeHeads canonicalSiteUrl url.path
                                    |> toJsPort
                                , userCmd |> Cmd.map UserMsg
                                , contentCache
                                    |> ContentCache.lazyLoad document url
                                    |> Task.attempt UpdateCache
                                ]

                        _ ->
                            Cmd.none

                ( maybePagePath, maybeMetadata ) =
                    case ContentCache.lookupMetadata pathKey (Ok okCache) url of
                        Just ( pagePath, metadata ) ->
                            ( Just pagePath, Just metadata )

                        Nothing ->
                            ( Nothing, Nothing )
            in
            ( { key = key
              , url = url
              , userModel = userModel
              , contentCache = contentCache
              }
            , cmd
            )

        Err _ ->
            let
                ( userModel, userCmd ) =
                    initUserModel Nothing
            in
            ( { key = key
              , url = url
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


update :
    pathKey
    -> (PagePath pathKey -> userMsg)
    -> (Json.Encode.Value -> Cmd (Msg userMsg metadata view))
    -> Pages.Document.Document metadata view
    -> (userMsg -> userModel -> ( userModel, Cmd userMsg ))
    -> Msg userMsg metadata view
    -> ModelDetails userModel metadata view
    -> ( ModelDetails userModel metadata view, Cmd (Msg userMsg metadata view) )
update pathKey onPageChangeMsg toJsPort document userUpdate msg model =
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
                    let
                        ( userModel, userCmd ) =
                            userUpdate
                                (onPageChangeMsg (url |> urlToPagePath pathKey))
                                model.userModel
                    in
                    ( { model
                        | url = url
                        , contentCache = updatedCache
                        , userModel = userModel
                      }
                    , userCmd |> Cmd.map UserMsg
                    )

                Err _ ->
                    -- TODO handle error
                    ( { model | url = url }, Cmd.none )


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document view


application :
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
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg metadata view)
    , manifest : Manifest.Config pathKey
    , canonicalSiteUrl : String
    , pathKey : pathKey
    , onPageChange : PagePath pathKey -> userMsg
    }
    -> Program userModel userMsg metadata view
application config =
    Browser.application
        { init =
            \flags url key ->
                init config.pathKey config.canonicalSiteUrl config.document config.toJsPort config.view config.content config.init flags url key
                    |> Tuple.mapFirst Model
        , view =
            \outerModel ->
                case outerModel of
                    Model model ->
                        view config.pathKey config.content config.view model

                    CliModel ->
                        { title = "Error"
                        , body = [ Html.text "Unexpected state" ]
                        }
        , update =
            \msg outerModel ->
                case outerModel of
                    Model model ->
                        update config.pathKey config.onPageChange config.toJsPort config.document config.update msg model |> Tuple.mapFirst Model

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
            { view :
                staticData
                -> userModel
                -> view
                ->
                    { title : String
                    , body : Html userMsg
                    }
            , head : List (Head.Tag pathKey)
            , staticRequest : StaticHttp.Request staticData
            }
    , document : Pages.Document.Document metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg metadata view)
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
    in
    Platform.worker
        { init =
            \flags ->
                ( CliModel
                , case contentCache of
                    Ok _ ->
                        case contentCache |> ContentCache.pagesWithErrors of
                            Just pageErrors ->
                                config.toJsPort
                                    (Json.Encode.object
                                        [ ( "errors", encodeErrors pageErrors )
                                        , ( "manifest", Manifest.toJson config.manifest )
                                        ]
                                    )

                            Nothing ->
                                config.toJsPort
                                    (Json.Encode.object
                                        [ ( "manifest", Manifest.toJson config.manifest )
                                        ]
                                    )

                    Err error ->
                        config.toJsPort
                            (Json.Encode.object
                                [ ( "errors", encodeErrors error )
                                , ( "manifest", Manifest.toJson config.manifest )
                                ]
                            )
                )
        , update = \msg model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


encodeErrors errors =
    errors
        |> Json.Encode.dict
            (\path -> "/" ++ String.join "/" path)
            (\errorsForPath -> Json.Encode.string errorsForPath)
