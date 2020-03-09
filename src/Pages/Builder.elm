module Pages.Builder exposing (..)

import Head
import Html exposing (Html)
import Pages.Document as Document
import Pages.Internal
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Pages.StaticHttp as StaticHttp


type Builder pathKey userModel userMsg metadata view builderState
    = Builder
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
        , documents : List ( String, Document.DocumentHandler metadata view )
        , manifest : Pages.Manifest.Config pathKey
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
        , onPageChange :
            { path : PagePath pathKey
            , query : Maybe String
            , fragment : Maybe String
            }
            -> userMsg
        , canonicalSiteUrl : String
        , internals : Pages.Internal.Internal pathKey
        }


init :
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
    , documents : List ( String, Document.DocumentHandler metadata view )
    , manifest : Pages.Manifest.Config pathKey
    , onPageChange :
        { path : PagePath pathKey
        , query : Maybe String
        , fragment : Maybe String
        }
        -> userMsg
    , canonicalSiteUrl : String
    , internals : Pages.Internal.Internal pathKey
    }
    -> Builder pathKey userModel userMsg metadata view { canAddSubscriptions : () }
init config =
    Builder
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , documents = []
        , manifest = config.manifest
        , generateFiles = \_ -> StaticHttp.succeed []
        , canonicalSiteUrl = "" --config.canonicalSiteUrl
        , onPageChange = config.onPageChange -- OnPageChange
        , internals = config.internals
        }


withFileGenerator :
    (List { path : PagePath pathKey, frontmatter : metadata, body : String }
     ->
        StaticHttp.Request
            (List
                (Result String
                    { path : List String
                    , content : String
                    }
                )
            )
    )
    -> Builder pathKey userModel userMsg metadata view builderState
    -> Builder pathKey userModel userMsg metadata view builderState
withFileGenerator generateFiles (Builder config) =
    Builder
        { config
            | generateFiles =
                \data ->
                    StaticHttp.map2 (++)
                        (generateFiles data)
                        (config.generateFiles data)
        }


withSubscriptions :
    (userModel -> Sub userMsg)
    -> Builder pathKey userModel userMsg metadata view { builderState | canAddSubscriptions : () }
    -> Builder pathKey userModel userMsg metadata view builderState
withSubscriptions subs (Builder config) =
    Builder { config | subscriptions = subs }


type Model
    = Model


type Msg
    = Msg


type View
    = View


type Metadata
    = Metadata


example : Pages.Platform.Program Model Msg Metadata View
example =
    init
        { init = appInit
        , view = view
        , update = update
        , canonicalSiteUrl = "TODO"
        , manifest = Debug.todo ""
        , subscriptions = Debug.todo ""
        , internals = Debug.todo ""
        , documents = Debug.todo ""
        , onPageChange = Debug.todo ""
        }
        |> withFileGenerator (\_ -> StaticHttp.succeed [])
        |> withSubscriptions (\_ -> Sub.batch [])
        -- COMPILER ERROR!
        --|> withSubscriptions (\_ -> Sub.batch [])
        |> toApplication


update =
    Debug.todo ""


view =
    Debug.todo ""


toApplication : Builder pathKey model msg metadata view builderState -> Pages.Platform.Program model msg metadata view
toApplication (Builder config) =
    Pages.Platform.application
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , documents = []
        , manifest = config.manifest
        , canonicalSiteUrl = "" --config.canonicalSiteUrl
        , generateFiles = config.generateFiles
        , onPageChange = config.onPageChange -- OnPageChange
        , internals = config.internals
        }


appInit : a
appInit =
    Debug.todo ""



--main : Pages.Platform.Program Model Msg Metadata View
--main =
--    Pages.Platform.application
--        { init = init
--        , view = view
--        , update = update
--        , subscriptions = subscriptions
--        , documents = [ markdownDocument ]
--        , manifest = manifest
--        , canonicalSiteUrl = canonicalSiteUrl
--        , generateFiles = generateFiles
--        , onPageChange = OnPageChange
--        , internals = Pages.internals
--        }
