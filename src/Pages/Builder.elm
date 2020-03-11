module Pages.Builder exposing (..)

import Head
import Html exposing (Html)
import Json.Decode
import Pages.Document as Document exposing (DocumentHandler)
import Pages.Internal
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Pages.StaticHttp as StaticHttp


type Builder pathKey model msg metadata view builderState
    = Builder
        { init :
            Maybe
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            -> ( model, Cmd msg )
        , update : msg -> model -> ( model, Cmd msg )
        , subscriptions : model -> Sub msg
        , view :
            List ( PagePath pathKey, metadata )
            ->
                { path : PagePath pathKey
                , frontmatter : metadata
                }
            ->
                StaticHttp.Request
                    { view : model -> view -> { title : String, body : Html msg }
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
            Maybe
                ({ path : PagePath pathKey
                 , query : Maybe String
                 , fragment : Maybe String
                 }
                 -> msg
                )
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
        -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view :
        List ( PagePath pathKey, metadata )
        ->
            { path : PagePath pathKey
            , frontmatter : metadata
            }
        ->
            StaticHttp.Request
                { view : model -> view -> { title : String, body : Html msg }
                , head : List (Head.Tag pathKey)
                }
    , documents :
        List
            { extension : String
            , metadata : Json.Decode.Decoder metadata
            , body : String -> Result String view
            }
    , manifest : Pages.Manifest.Config pathKey
    , canonicalSiteUrl : String
    , internals : Pages.Internal.Internal pathKey
    }
    -> Builder pathKey model msg metadata view { canAddSubscriptions : (), canAddPageChangeMsg : () }
init config =
    Builder
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = \_ -> Sub.none
        , documents = config.documents |> List.map Document.parser
        , manifest = config.manifest
        , generateFiles = \_ -> StaticHttp.succeed []
        , canonicalSiteUrl = config.canonicalSiteUrl
        , onPageChange = Nothing
        , internals = config.internals
        }


withPageChangeMsg :
    ({ path : PagePath pathKey
     , query : Maybe String
     , fragment : Maybe String
     }
     -> msg
    )
    -> Builder pathKey model msg metadata view { builderState | canAddPageChangeMsg : () }
    -> Builder pathKey model msg metadata view builderState
withPageChangeMsg onPageChangeMsg (Builder builder) =
    Builder { builder | onPageChange = Just onPageChangeMsg }


addGlobalHeadTags :
    List (Head.Tag pathKey)
    -> Builder pathKey model msg metadata view builderState
    -> Builder pathKey model msg metadata view builderState
addGlobalHeadTags globalHeadTags (Builder config) =
    Builder
        { config
            | view =
                \arg1 arg2 ->
                    config.view arg1 arg2
                        |> StaticHttp.map
                            (\fns ->
                                { view = fns.view
                                , head = globalHeadTags ++ fns.head
                                }
                            )
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
    -> Builder pathKey model msg metadata view builderState
    -> Builder pathKey model msg metadata view builderState
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
    (model -> Sub msg)
    -> Builder pathKey model msg metadata view { builderState | canAddSubscriptions : () }
    -> Builder pathKey model msg metadata view builderState
withSubscriptions subs (Builder config) =
    Builder { config | subscriptions = subs }


toApplication : Builder pathKey model msg metadata view builderState -> Pages.Platform.Program model msg metadata view
toApplication (Builder config) =
    Pages.Platform.application
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , documents = config.documents
        , manifest = config.manifest
        , canonicalSiteUrl = config.canonicalSiteUrl
        , generateFiles = config.generateFiles
        , onPageChange = config.onPageChange
        , internals = config.internals
        }
