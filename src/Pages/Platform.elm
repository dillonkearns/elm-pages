module Pages.Platform exposing (application, Program, Page)

{-| TODO

@docs application, Program, Page

-}

import Head
import Html exposing (Html)
import Pages.Document as Document
import Pages.Internal
import Pages.Internal.Platform
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


{-| TODO
-}
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
            StaticHttp.Request
                { view : userModel -> view -> { title : String, body : Html userMsg }
                , head : List (Head.Tag pathKey)
                }
    , documents : List ( String, Document.DocumentHandler metadata view )
    , manifest : Pages.Manifest.Config pathKey
    , onPageChange : PagePath pathKey -> userMsg
    , canonicalSiteUrl : String
    , internals : Pages.Internal.Internal pathKey
    }
    -> Program userModel userMsg metadata view
application config =
    (case config.internals.applicationType of
        Pages.Internal.Browser ->
            Pages.Internal.Platform.application

        Pages.Internal.Cli ->
            Pages.Internal.Platform.cliApplication
    )
    <|
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , document = Document.fromList config.documents
        , content = config.internals.content
        , toJsPort = config.internals.toJsPort
        , manifest = config.manifest
        , canonicalSiteUrl = config.canonicalSiteUrl
        , onPageChange = config.onPageChange
        , pathKey = config.internals.pathKey
        }


{-| TODO
-}
type alias Program model msg metadata view =
    Pages.Internal.Platform.Program model msg metadata view


{-| TODO
-}
type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }
