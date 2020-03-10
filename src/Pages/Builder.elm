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
            Maybe
                ({ path : PagePath pathKey
                 , query : Maybe String
                 , fragment : Maybe String
                 }
                 -> userMsg
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
        -> ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
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
    -> Builder pathKey userModel userMsg metadata view { canAddSubscriptions : (), canAddPageChangeMsg : () }
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
    -> Builder pathKey userModel msg metadata view { builderState | canAddPageChangeMsg : () }
    -> Builder pathKey userModel msg metadata view builderState
withPageChangeMsg onPageChangeMsg (Builder builder) =
    Builder { builder | onPageChange = Just onPageChangeMsg }


addGlobalHeadTags :
    List (Head.Tag pathKey)
    -> Builder pathKey userModel userMsg metadata view builderState
    -> Builder pathKey userModel userMsg metadata view builderState
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
