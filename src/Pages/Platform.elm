module Pages.Platform exposing (application, Program, Page)

{-| Configure your `elm-pages` Program, similar to a `Browser.application`.

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


{-| This is the entry point for your `elm-pages` application.

This is similar to how you set up a regular Elm application using `Browser.application`, but with a few differences.

  - `view` has access to `StaticHttp` data (see [Pages.StaticHttp](#Pages.StaticHttp)).
  - `view` is able to set `head` tags which can be used for site metadata and SEO data.
  - `manifest` lets you configure the manifest.json for your PWA (Progressive Web App).
  - `canonicalSiteUrl` is the default domain for your `<head>` tags for SEO purposes (you can override it with `canonicalUrlOverride`,
    see <Head.Seo>. Learn more about canonical URLs and why they are important [in this article](https://yoast.com/rel-canonical/).
  - `internals` is an opaque data type with some internal boilerplate from your `elm-pages` content. You should pass it `internals = Pages.internals`.

Otherwise, you have a standard Elm app which


## `elm-pages` Lifecycle

It's helpful to understand the `elm-pages` lifecycle and how it compares to a vanilla elm app (i.e. a `Browser.application`).


### Generate Step (`elm-pages build`)

Whereas a vanilla Elm app simply compiles your Elm code at build time, `elm-pages` performs some lifecycle events at this stage.

  - Performs all `StaticHttp.Request`s (see <Pages.StaticHttp>) for every static page in your app. The StaticHttp Responses are stored in JSON
    files called `content.json` (one JSON file for each static page in your site).
  - Pre-renders HTML pages, including the `<head>` tags for the page from your `view`'s `head`.
  - Optimizes image assets and copies over files from `static` folder to the `dist` folder.


### Initial Load (from user's browser)

The user will see the pre-rendered HTML when they initially load a page on your `elm-pages` site (unless you are in dev mode, i.e. `elm-pages develop`, in
which case there is no pre-rendering).


### Hydration

  - Fetch all the `StaticHttp` responses and page data (the `content.json` file for the current page).
  - The Elm app hydrates and starts executing and running your Elm app's `init` function and `update` loop (not just the pre-rendered HTML content).
    At this point, all of your `subscriptions`, etc. will behave as they would in a regular Elm application.
  - The app will now run as a single-page app. When you hover over a link to another static page on your current site,
    it will pre-fetch the page data (`content.json` file), so that the page load is instant.

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
    , generateFiles :
        List
            { path : PagePath pathKey
            , frontmatter : metadata
            }
        ->
            List
                { path : List String
                , content : String
                }
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
        , generateFiles = config.generateFiles
        , toJsPort = config.internals.toJsPort
        , manifest = config.manifest
        , canonicalSiteUrl = config.canonicalSiteUrl
        , onPageChange = config.onPageChange
        , pathKey = config.internals.pathKey
        }


{-| The `Program` type for an `elm-pages` app.
-}
type alias Program model msg metadata view =
    Pages.Internal.Platform.Program model msg metadata view


{-| -}
type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }
