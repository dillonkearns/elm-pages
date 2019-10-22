module Pages.Internal.Platform exposing (Content, Flags, Model, Msg, Page, Parser, Program, application, cliApplication)

import Browser
import Browser.Navigation
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Html.Attributes
import Http
import Json.Decode as Decode
import Json.Encode
import List.Extra
import Mark
import Pages.ContentCache as ContentCache exposing (ContentCache)
import Pages.Document
import Pages.Internal.Platform.Cli
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
                            """ 123456789 """

                        viewFnResult =
                            (viewFn
                                (cache
                                    |> Result.map (ContentCache.extractMetadata pathKey)
                                    |> Result.withDefault []
                                 -- TODO handle error better
                                )
                                { path = pagePath, frontmatter = metadata }
                                |> Tuple.second
                            )
                                viewResult.staticData
                    in
                    case viewResult.body of
                        Ok viewList ->
                            case viewFnResult of
                                Ok okViewFn ->
                                    okViewFn.view model.userModel viewList

                                Err error ->
                                    { title = "Parsing error"
                                    , body =
                                        Html.text <|
                                            "Could not load static data - TODO better error here."
                                                ++ error
                                    }

                        Err error ->
                            Debug.todo "asdf"

                --                            { title = "Parsing error"
                --                            , body = Html.text error
                --                            }
                ContentCache.NeedContent extension a ->
                    { title = "", body = Html.text "" }

                --                    Debug.todo (Debug.toString a)
                ContentCache.Unparsed extension a b ->
                    --                    Debug.todo (Debug.toString b)
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
        , body |> Html.map UserMsg |> Html.map AppMsg
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
    ()


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
    -> Content
    -> (Maybe (PagePath pathKey) -> ( userModel, Cmd userMsg ))
    -> Flags
    -> Url
    -> Browser.Navigation.Key
    -> ( ModelDetails userModel metadata view, Cmd (AppMsg userMsg metadata view) )
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
                                headFnResult =
                                    viewFn
                                        (ContentCache.extractMetadata pathKey okCache)
                                        { path = pagePath
                                        , frontmatter = frontmatter
                                        }
                                        |> Tuple.second

                                --                                        """ 123456789 """
                                --                                        "asdfasdf"
                                --                                        |> .head
                            in
                            Cmd.batch
                                [ userCmd |> Cmd.map UserMsg
                                , contentCache
                                    |> ContentCache.lazyLoad document url
                                    |> Task.attempt UpdateCache
                                ]

                        --                            case headFnResult |> Result.map .head of
                        --                                Ok head ->
                        --                                    Cmd.batch
                        --                                        [ head
                        --                                            |> encodeHeads canonicalSiteUrl url.path
                        --                                            |> toJsPort
                        --                                        , userCmd |> Cmd.map UserMsg
                        --                                        , contentCache
                        --                                            |> ContentCache.lazyLoad document url
                        --                                            |> Task.attempt UpdateCache
                        --                                        ]
                        --
                        --                                Err error ->
                        --                                    Debug.todo error
                        --                                    Cmd.none
                        _ ->
                            --                            Cmd.none
                            Debug.todo "Error"

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
    = AppMsg (AppMsg userMsg metadata view)
    | CliMsg Pages.Internal.Platform.Cli.Msg


type AppMsg userMsg metadata view
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | UserMsg userMsg
    | UpdateCache (Result Http.Error (ContentCache metadata view))
    | UpdateCacheAndUrl Url (Result Http.Error (ContentCache metadata view))


type Model userModel userMsg metadata view
    = Model (ModelDetails userModel metadata view)
    | CliModel Pages.Internal.Platform.Cli.Model


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
    -> ( ModelDetails userModel metadata view, Cmd (AppMsg userMsg metadata view) )
update pathKey onPageChangeMsg toJsPort document userUpdate msg model =
    case msg of
        AppMsg appMsg ->
            case appMsg of
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

        CliMsg _ ->
            ( model, Cmd.none )


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
    -> Platform.Program Flags (Model userModel userMsg metadata view) (Msg userMsg metadata view)
application config =
    Browser.application
        { init =
            \flags url key ->
                init config.pathKey config.canonicalSiteUrl config.document (config.toJsPort >> Cmd.map never) config.view config.content config.init flags url key
                    |> Tuple.mapFirst Model
                    |> Tuple.mapSecond (Cmd.map AppMsg)
        , view =
            \outerModel ->
                case outerModel of
                    Model model ->
                        view config.pathKey config.content config.view model

                    CliModel _ ->
                        { title = "Error"
                        , body = [ Html.text "Unexpected state" ]
                        }
        , update =
            \msg outerModel ->
                case outerModel of
                    Model model ->
                        update config.pathKey config.onPageChange (config.toJsPort >> Cmd.map never) config.document config.update msg model
                            |> Tuple.mapFirst Model
                            |> Tuple.mapSecond (Cmd.map AppMsg)

                    CliModel _ ->
                        ( outerModel, Cmd.none )
        , subscriptions =
            \outerModel ->
                case outerModel of
                    Model model ->
                        config.subscriptions model.userModel
                            |> Sub.map UserMsg
                            |> Sub.map AppMsg

                    CliModel _ ->
                        Sub.none
        , onUrlChange = UrlChanged >> AppMsg
        , onUrlRequest = LinkClicked >> AppMsg
        }


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
cliApplication =
    Pages.Internal.Platform.Cli.cliApplication CliMsg
        (\msg ->
            case msg of
                CliMsg cliMsg ->
                    Just cliMsg

                _ ->
                    Nothing
        )
        CliModel
        (\model ->
            case model of
                CliModel cliModel ->
                    Just cliModel

                _ ->
                    Nothing
        )


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



--
--    Http.get
--        { url = ""
--        , expect =
--            Http.expectString
--                (\response ->
--                    GotStaticHttpResponse
--                        { url = "TODO url"
--                        , response = response
--                        }
--                )
--        }


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
