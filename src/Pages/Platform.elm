module Pages.Platform exposing
    ( Builder, init, toProgram
    , Program, Page
    , withGlobalHeadTags, withFileGenerator
    )

{-| Configure your `elm-pages` Program, similar to a `Browser.application`.

This is the entry point for your `elm-pages` application.

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


## Basic application config

@docs Builder, init, toProgram

@docs Program, Page


## Additional application config

@docs withGlobalHeadTags, withFileGenerator

-}

import Head
import Html exposing (Html)
import Json.Decode
import Pages.Document as Document
import Pages.Internal
import Pages.Internal.Platform
import Pages.Manifest
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


{-| You can [`init`](#init) a `Builder`, and then turn it to a [`Program`](#Program) with [`toProgram`](#toProgram).

That gives you the basic options, then you can [include optional configuration](#additional-application-config).

-}
type Builder pathKey model msg metadata view
    = Builder
        { init :
            Maybe
                { path :
                    { path : PagePath pathKey
                    , query : Maybe String
                    , fragment : Maybe String
                    }
                , metadata : metadata
                }
            -> ( model, Cmd msg )
        , update : msg -> model -> ( model, Cmd msg )
        , subscriptions : metadata -> PagePath pathKey -> model -> Sub msg
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
                 , metadata : metadata
                 }
                 -> msg
                )
        , canonicalSiteUrl : String
        , internals : Pages.Internal.Internal pathKey
        }


{-| Pass the initial required configuration for your `elm-pages` application.

Here's a basic example.

    import Pages.Platform

    main : Pages.Platform.Program Model Msg Metadata View
    main =
        Pages.Platform.init
            { init = init
            , view = view
            , update = update
            , subscriptions = subscriptions
            , documents =
                [ { extension = "md"
                  , metadata = Metadata.decoder
                  , body = MarkdownRenderer.view
                  }
                ]
            , onPageChange = Just OnPageChange
            , manifest = manifest
            , canonicalSiteUrl = canonicalSiteUrl
            , internals = Pages.internals
            }
            |> Pages.Platform.toProgram

-}
init :
    { init :
        Maybe
            { path :
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : metadata
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
    , subscriptions : metadata -> PagePath pathKey -> model -> Sub msg
    , documents :
        List
            { extension : String
            , metadata : Json.Decode.Decoder metadata
            , body : String -> Result String view
            }
    , onPageChange :
        Maybe
            ({ path : PagePath pathKey
             , query : Maybe String
             , fragment : Maybe String
             , metadata : metadata
             }
             -> msg
            )
    , manifest : Pages.Manifest.Config pathKey
    , canonicalSiteUrl : String
    , internals : Pages.Internal.Internal pathKey
    }
    -> Builder pathKey model msg metadata view
init config =
    Builder
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , documents = config.documents |> List.map Document.parser
        , manifest = config.manifest
        , onPageChange = config.onPageChange
        , generateFiles = \_ -> StaticHttp.succeed []
        , canonicalSiteUrl = config.canonicalSiteUrl
        , internals = config.internals
        }


{-| Add some head tags that will be included on every page of your `elm-pages` site.
-}
withGlobalHeadTags :
    List (Head.Tag pathKey)
    -> Builder pathKey model msg metadata view
    -> Builder pathKey model msg metadata view
withGlobalHeadTags globalHeadTags (Builder config) =
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


{-| Include files to be generated. Any `Err` values will turn into a build error.

You can use StaticHttp data here, and it won't be included in your production build (it will just be fetched as needed
during the build step). You also have access to all of your site's pages, with their path, metadata, and body.

Some use cases are to generate

  - A sitemap
  - An RSS feed
  - A robots.txt file
  - Podcast feeds
  - Configuration files (e.g. Netlify CMS config)

```elm
    import Pages.Platform

    withRobotsTxt builder =
    builder
        |> Pages.Platform.withFileGenerator
            (\siteMetadata ->
                StaticHttp.succeed
                    [ Ok
                        { path = [ "robots.txt" ]
                        , content = """
User-agent: *
Disallow: /cgi-bin/
                        """
                        }
                    ]
            )
```

-}
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
    -> Builder pathKey model msg metadata view
    -> Builder pathKey model msg metadata view
withFileGenerator generateFiles (Builder config) =
    Builder
        { config
            | generateFiles =
                \data ->
                    StaticHttp.map2 (++)
                        (generateFiles data)
                        (config.generateFiles data)
        }


{-| When you're done with your builder pipeline, you complete it with `Pages.Platform.toProgram`.
-}
toProgram : Builder pathKey model msg metadata view -> Program model msg metadata view pathKey
toProgram (Builder config) =
    application
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


application :
    { init :
        Maybe
            { path :
                { path : PagePath pathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : metadata
            }
        -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : metadata -> PagePath pathKey -> model -> Sub msg
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
             , metadata : metadata
             }
             -> msg
            )
    , canonicalSiteUrl : String
    , internals : Pages.Internal.Internal pathKey
    }
    -> Program model msg metadata view pathKey
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
        , fromJsPort = config.internals.fromJsPort
        , manifest = config.manifest
        , canonicalSiteUrl = config.canonicalSiteUrl
        , onPageChange = config.onPageChange
        , pathKey = config.internals.pathKey
        }


{-| The `Program` type for an `elm-pages` app.
-}
type alias Program model msg metadata view pathKey =
    Pages.Internal.Platform.Program model msg metadata view pathKey


{-| -}
type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }
