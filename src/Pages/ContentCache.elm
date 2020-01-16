module Pages.ContentCache exposing
    ( ContentCache
    , Entry(..)
    , Page
    , Path
    , errorView
    , extractMetadata
    , init
    , lazyLoad
    , lookup
    , lookupMetadata
    , pagesWithErrors
    , pathForUrl
    , routesForCache
    , update
    )

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
import Mark
import Mark.Error
import Pages.Document as Document exposing (Document)
import Pages.PagePath as PagePath exposing (PagePath)
import Result.Extra
import Task exposing (Task)
import TerminalText as Terminal
import Url exposing (Url)
import Url.Builder


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias ContentCache metadata view =
    Result Errors (Dict Path (Entry metadata view))


type alias Errors =
    List ( Html Never, BuildError )


type alias ContentCacheInner metadata view =
    Dict Path (Entry metadata view)


type Entry metadata view
    = NeedContent String metadata
    | Unparsed String metadata (ContentJson String)
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed metadata (ContentJson (Result ParseError view))


type alias ParseError =
    String


type alias Path =
    List String


extractMetadata : pathKey -> ContentCacheInner metadata view -> List ( PagePath pathKey, metadata )
extractMetadata pathKey cache =
    cache
        |> Dict.toList
        |> List.map (\( path, entry ) -> ( PagePath.build pathKey path, getMetadata entry ))


getMetadata : Entry metadata view -> metadata
getMetadata entry =
    case entry of
        NeedContent extension metadata ->
            metadata

        Unparsed extension metadata _ ->
            metadata

        Parsed metadata _ ->
            metadata


pagesWithErrors : ContentCache metadata view -> List BuildError
pagesWithErrors cache =
    cache
        |> Result.map
            (\okCache ->
                okCache
                    |> Dict.toList
                    |> List.filterMap
                        (\( path, value ) ->
                            case value of
                                Parsed metadata { body } ->
                                    case body of
                                        Err parseError ->
                                            createBuildError path parseError |> Just

                                        _ ->
                                            Nothing

                                _ ->
                                    Nothing
                        )
            )
        |> Result.withDefault []


init :
    Document metadata view
    -> Content
    -> ContentCache metadata view
init document content =
    parseMetadata document content
        |> List.map
            (\tuple ->
                Tuple.mapSecond
                    (\result ->
                        result
                            |> Result.mapError
                                (\error ->
                                    --                            ( Tuple.first tuple, error )
                                    createErrors (Tuple.first tuple) error
                                )
                    )
                    tuple
            )
        |> combineTupleResults
        --|> Result.map
        --    (\soFar ->
        --        soFar
        --            |> List.map
        --                (\( path, entry ) ->
        --                    let
        --                        initialThing =
        --                            case entry of
        --                                NeedContent string metadata ->
        --
        --
        --                                Unparsed string metadata contentJson ->
        --
        --
        --                                Parsed metadata contentJson ->
        --
        --                            --Parsed metadata
        --                            --    { body = renderer rawContent.body
        --                            --    , staticData = rawContent.staticData
        --                            --    }
        --                            --    |> Just
        --                    in
        --                    ( path, entry )
        --                )
        --    )
        --        |> Result.mapError Dict.fromList
        |> Result.map Dict.fromList


createErrors path decodeError =
    ( createHtmlError path decodeError, createBuildError path decodeError )


createBuildError : List String -> String -> BuildError
createBuildError path decodeError =
    { title = "Metadata Decode Error"
    , message =
        [ Terminal.text "I ran into a problem when parsing the metadata for the page with this path: "
        , Terminal.text ("/" ++ (path |> String.join "/"))
        , Terminal.text "\n\n"
        , Terminal.text decodeError
        ]
    }


parseMetadata :
    Document metadata view
    -> List ( List String, { extension : String, frontMatter : String, body : Maybe String } )
    -> List ( List String, Result String (Entry metadata view) )
parseMetadata document content =
    content
        |> List.map
            (\( path, { frontMatter, extension, body } ) ->
                let
                    maybeDocumentEntry =
                        Document.get extension document
                in
                case maybeDocumentEntry of
                    Just documentEntry ->
                        frontMatter
                            |> documentEntry.frontmatterParser
                            |> Result.map
                                (\metadata ->
                                    let
                                        renderer =
                                            \value ->
                                                parseContent extension value document

                                        thing =
                                            Parsed metadata
                                                { body = renderer """

After a round of closed beta testing (thank you to [Brian](https://twitter.com/brianhicks) and the [`elm-conf 2019`](https://2019.elm-conf.com/) organizing team!), I'm excited to share a new static site generator for Elm!

[Matthew Griffith](https://twitter.com/mech_elephant) and I have had a lot of design discussions and sending code snippets back-and-forth to get to the current design. A big thank you to Matthew for the great discussions and, as always, his ability to look at the bigger picture and question basic assumptions to come up with awesome innovations!

## What is `elm-pages` exactly?

Well, this site you're looking at _right now_ is built with `elm-pages`! For example, the raw content for this post is from [`content/blog/introducing-elm-pages.md`](https://github.com/dillonkearns/elm-pages/blob/master/examples/docs/content/blog/introducing-elm-pages.md).

`elm-pages` takes your static content and turns it into a modern, performant, single-page app. You can do anything you can with a regular Elm site, and yet the framework does a lot for you to optimize site performance and minimize tedious work.

I see a lot of "roll your own" Elm static sites out there these days. When you roll your own Elm static site, you often:

- Manage Strings for each page's content (rather than just having a file for each page)
- Wire up the routing for each page manually (or with a hand-made script)
- Add `<meta>` tags for SEO and to make Twitter/Slack/etc. link shares display the right image and title (or just skip it because it's a pain)

I hope that `elm-pages` will make people's lives easier (and their load times faster). But `elm-pages` is for more than just building your blog or portfolio site. There's a movement now called JAMstack (JavaScript, APIs, and Markup) that is solving a broader set of problems with static sites. JAMstack apps do this by pulling in data from external sources, and using modern frontend frameworks to render the content (which then rehydrate into interactive apps). The goal is to move as much work as possible away from the user's browser and into a build step before pushing static files to your CDN host (but without sacrificing functionality). More and more sites are seeing that optimizing performance improves conversion rates and user engagement, and it can also make apps simpler to maintain.

This is just the first release of `elm-pages`, but I've built a prototype for pulling in external data and am refining the design in preparation for the next release. Once that ships, the use cases `elm-pages` can handle will expand to things like ecommerce sites, job boards, and sites with content written by non-technical content editors. You can find a very informative FAQ and resources page about these ideas at [jamstack.org](https://jamstack.org/) (plus a more in-depth definition of the term JAMstack).

## Comparing `elm-pages` and `elmstatic`

`elm-pages` and [`elmstatic`](https://korban.net/elm/elmstatic/) have a lot of differences. At the core, they have two different goals. `elmstatic` generates HTML for you that doesn't include an Elm runtime. It uses Elm as a templating engine to do page layouts. It also makes some assumptions about the structure of your page content, separating `posts` and `pages` and automatically generating post indexes based on the top-level directories within the `posts` folder. It's heavily inspired by traditional static site generators like Jekyll.

`elm-pages` hydrates into a single-page app that includes a full Elm runtime, meaning that you can have whatever client-side interactivity you want. It supports similar use cases to static site generators like [Gatsby](http://gatsbyjs.org). `elm-pages` makes a lot of optimizations by splitting and lazy-loading pages, optimizing image assets, and using service workers for repeat visits. It pre-renders HTML for fast first renders, but because it ships with JavaScript code it is also able to do some performance optimizations to make page changes faster (and without page flashes). So keep in mind that shipping without JavaScript doesn't necessarily mean your site performance suffers! You may have good reasons to want a static site with no JavaScript, but open up a Lighthouse audit and try it out for yourself rather than speculating about performance!

Either framework might be the right fit depending on your goals. I hope this helps illuminate the differences!

## How does `elm-pages` work?

The flow is something like this:

- Put your static content in your `content` folder (it could be Markdown, `elm-markup`, or something else entirely)
- Register Elm functions that define what to do with the [frontmatter](https://jekyllrb.com/docs/front-matter/) (that YAML data at the top of your markup files) and the body of each type of file you want to handle
- Define your app's configuration in pure Elm (just like a regular Elm `Browser.application` but with a few extra functions for SEO and site configuration)
- Run `elm-pages build` and ship your static files (JS, HTML, etc.) to Netlify, Github Pages, or your CDN of choice!

The result is a blazing fast static site that is optimized both for the first load experience, and also uses some caching strategies to improve site performance for repeat visitors. You can look in your dev tools or run a Lighthouse audit on this page to see some of the performance optimizations `elm-pages` does for you!

The way you set up an `elm-pages` app will look familiar if you have some experience with wiring up standard Elm boilerplate:

```elm
main : Pages.Platform.Program Model Msg Metadata (List (Element Msg))
main =
  Pages.application
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    , documents = [ markdownHandler ]
    , head = head
    , manifest = manifest
    , canonicalSiteUrl = "https://elm-pages.com"
    }
```

You can take a look at [the `Main.elm` file for this site](https://github.com/dillonkearns/elm-pages/blob/master/examples/docs/src/Main.elm#L52) to get a better sense of the bigger picture. I'll do a more in-depth explanation of this setup in a future post. The short version is that

`init`, `update`, and `subscriptions` are as you would expect (but maybe a bit simpler since `elm-pages` manages things like the URL for you).

`documents` are where you define how to handle the frontmatter and body of the files in your `content` folder. And the `view` function gives you the result from your frontmatter and body, as well as your `Model`.

`head` is just a function that passes you the metadata for a given page and lets you define tags to put in the `<head>` (mostly for SEO).

`manifest` lets you configure some settings that allow your app to be installed for offline use.

And the end result is that `elm-pages` gets everything it needs about your site in order to optimize it and turn it into a modern, performant site that will get a great Lighthouse audit score! The goal is to make following best practices for a modern, performant static site one of the following:

- Built-in
- Enforced by the Elm compiler
- Or at the very least the path of least resistence

## What makes Elm awesome for building static sites

JAMstack frameworks, like [Gatsby](http://gatsbyjs.org), can make powerful optimizations because they are dealing with strong constraints (specifically, content that is known at build time). Elm is the perfect tool for the JAMstack because it can leverage those constraints and turn them into compiler guarantees. Not only can we do more with static guarantees using Elm, but we can get additional guarantees using Elm's type-system and managed side-effects. It's a virtuous cycle that enables a lot of innovation.

## Why use `elm-pages`?

Let's take a look at a few of the features that make `elm-pages` worthwhile for the users (both the end users, and the team using it to build their site).

### Performance

- Pre-rendered pages for blazing fast first renders and improved SEO
- Your content is loaded as a single-page app behind the scenes, giving you smooth page changes
- Split individual page content and lazy load each page
- Prefetch page content on link hover so page changes are almost instant
- Image assets are optimized
- App skeleton is cached with a service worker (with zero configuration) so it's available offline

One of the early beta sites that used `elm-pages` instantly shaved off over a megabyte for the images on a single page! Optimizations like that need to be built-in and automatic otherwise some things inevitably slip through the cracks.

### Type-safety and simplicity

- The type system guarantees that you use valid images and routes in the right places
- You can even set up a validation to give build errors if there are any broken links or images in your markdown
- You can set up validations to define your own custom rules for your domain! (Maximum title length, tag name from a set to avoid multiple tags with different wording, etc.)

## Progressive Web Apps

[Lighthouse recommends having a Web Manifest file](https://developers.google.com/web/tools/lighthouse/audits/manifest-exists) for your app to allow users to install the app to your home screen and have an appropriate icon, app name, etc.
Elm pages gives you a type-safe way to define a web manifest for your app:

```elm
manifest : Manifest.Config PagesNew.PathKey
manifest =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.white
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.icon
    }
```

Lighthouse will also ding you [if you don't have the appropriately sized icons and favicon images](https://developers.google.com/web/tools/lighthouse/audits/manifest-contains-192px-icon). `elm-pages` guarantees that you will follow these best practices (and gives you the confidence that you haven't made any mistakes). It will automatically generate the recommended set of icons and favicons for you, based on a single source image. And, of course, you get a compile-time guarantee that you are using an image that exists! For example, here's what happens if we try to access an image as `logo` when the actual file is called `icon`.

```haskell
sourceIcon = images.logo
```

We then get this elm compiler error:
![Missing image compiler error](/images/compiler-error.png)

## `elm-pages` is just Elm!

`elm-pages` hydrates into a full-fledged Elm app (the pre-rendered pages are just for faster loads and better SEO). So you can do whatever you need to using Elm and the typed data that `elm-pages` provides you with. In a future post, I'll explain some of the ways that `elm-pages` leverages the Elm type system for a better developer experience. There's a lot to explore here, this really just scratches the surface!

## SEO

One of the main motivations for building `elm-pages` was to make SEO easier and less error-prone. Have you ever seen a link shared on Twitter or elsewhere online that just renders like a plain link? No image, no title, no description. As a user, I'm a little afraid to click those links because I don't have any clues about where it will take me. As a user posting those links, it's very anticlimactic to share the blog post that I lovingly wrote only to see a boring link there in my tweet sharing it with the world.

I'll also be digging into the topic of SEO in a future post, showing how `elm-pages` makes SEO dead simple. For now, you can take a look at [the built-in `elm-pages` SEO module](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Head-Seo) or take a look at [how this site uses the SEO module](https://github.com/dillonkearns/elm-pages/blob/8448bb60b680fb171319988fb716cb21e0345826/examples/docs/src/Main.elm#L294-L400).

## Next steps

There are so many possibilities when you pair Elm with static content! I'm excited to explore this area further with the help of the community. Here are some features that are on my radar.

- Allow users to pass a set of HTTP requests to fetch during the build step (for making CMS or API data available statically in the build)
- An API to programmatically add pages from metadata (rather than just from files in the `content` folder)
- Allow users to configure the caching strategy for service workers (through pure Elm config of course)
- More SEO features (possibly an API for adding structured data, i.e. JSON-LD, for more interactive and engaging search results)

And of course, responding to your feedback! Please don't hesitate to share your thoughts, on everything from the documentation to the developer experience. I'd love to hear from you!

## Getting started with `elm-pages`

If you'd like to try out `elm-pages` for yourself, or look at some code, the best place to start is the [`elm-pages-starter` repo](https://github.com/dillonkearns/elm-pages-starter). See the site live at [elm-pages-starter.netlify.com](https://elm-pages-starter.netlify.com). Let me know your thoughts on Slack, I'd love to hear from you! Or continue the conversation on Twitter!

<Oembed url="https://twitter.com/dillontkearns/status/1176556756249432065" />
"""
                                                , staticData =
                                                    Dict.fromList
                                                        [ ( "{\"method\":\"GET\",\"url\":\"https://api.github.com/repos/dillonkearns/elm-pages\",\"headers\":[],\"body\":{\"type\":\"empty\"}}"
                                                          , "{\"stargazers_count\":137}"
                                                          )
                                                        ]

                                                -- Debug.todo "" -- rawContent.staticData
                                                }
                                    in
                                    -- TODO do I need to handle this case?
                                    --                                        case body of
                                    --                                            Just presentBody ->
                                    --                                                Parsed metadata
                                    --                                                    { body = parseContent extension presentBody document
                                    --                                                    , staticData = ""
                                    --                                                    }
                                    --
                                    --                                            Nothing ->
                                    --NeedContent extension metadata
                                    thing
                                )
                            |> Tuple.pair path

                    Nothing ->
                        Err ("Could not find extension '" ++ extension ++ "'")
                            |> Tuple.pair path
            )


parseContent :
    String
    -> String
    -> Document metadata view
    -> Result String view
parseContent extension body document =
    let
        maybeDocumentEntry =
            Document.get extension document
    in
    case maybeDocumentEntry of
        Just documentEntry ->
            documentEntry.contentParser body

        Nothing ->
            Err ("Could not find extension '" ++ extension ++ "'")


errorView : Errors -> Html msg
errorView errors =
    errors
        --        |> Dict.toList
        |> List.map Tuple.first
        |> List.map (Html.map never)
        |> Html.div
            [ Attr.style "padding" "20px 100px"
            ]


createHtmlError : List String -> String -> Html msg
createHtmlError path error =
    Html.div []
        [ Html.h2 []
            [ Html.text ("/" ++ (path |> String.join "/"))
            ]
        , Html.p [] [ Html.text "I couldn't parse the frontmatter in this page. I ran into this error with your JSON decoder:" ]
        , Html.pre [] [ Html.text error ]
        ]


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")
        |> List.map (\route -> "/" ++ route)


routesForCache : ContentCache metadata view -> List String
routesForCache cacheResult =
    case cacheResult of
        Ok cache ->
            cache
                |> Dict.toList
                |> routes

        Err _ ->
            []


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


renderErrors : ( List String, List Mark.Error.Error ) -> Html msg
renderErrors ( path, errors ) =
    Html.div []
        [ Html.text (path |> String.join "/")
        , errors
            |> List.map (Mark.Error.toHtml Mark.Error.Light)
            |> Html.div []
        ]


combineTupleResults :
    List ( List String, Result error success )
    -> Result (List error) (List ( List String, success ))
combineTupleResults input =
    input
        |> List.map
            (\( path, result ) ->
                result
                    |> Result.map (\success -> ( path, success ))
            )
        |> combine


combine : List (Result error ( List String, success )) -> Result (List error) (List ( List String, success ))
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


{-| Get from the Cache... if it's not already parsed, it will
parse it before returning it and store the parsed version in the Cache
-}
lazyLoad :
    Document metadata view
    -> Url
    -> ContentCache metadata view
    -> Task Http.Error (ContentCache metadata view)
lazyLoad document url cacheResult =
    case cacheResult of
        Err _ ->
            Task.succeed cacheResult

        Ok cache ->
            case Dict.get (pathForUrl url) cache of
                Just entry ->
                    case entry of
                        NeedContent extension _ ->
                            httpTask url
                                |> Task.map
                                    (\downloadedContent ->
                                        update cacheResult
                                            (\value ->
                                                parseContent extension value document
                                            )
                                            url
                                            downloadedContent
                                    )

                        Unparsed extension metadata content ->
                            update cacheResult
                                (\thing ->
                                    parseContent extension thing document
                                )
                                url
                                content
                                |> Task.succeed

                        Parsed _ _ ->
                            Task.succeed cacheResult

                Nothing ->
                    Task.succeed cacheResult


httpTask : Url -> Task Http.Error (ContentJson String)
httpTask url =
    Http.task
        { method = "GET"
        , headers = []
        , url =
            Url.Builder.absolute
                ((url.path |> String.split "/" |> List.filter (not << String.isEmpty))
                    ++ [ "content.json"
                       ]
                )
                []
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.BadUrl_ url_ ->
                            Err (Http.BadUrl url_)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError

                        Http.BadStatus_ metadata body ->
                            Err (Http.BadStatus metadata.statusCode)

                        Http.GoodStatus_ metadata body ->
                            body
                                |> Decode.decodeString contentJsonDecoder
                                |> Result.mapError (\err -> Http.BadBody (Decode.errorToString err))
                )
        , timeout = Nothing
        }


type alias ContentJson body =
    { body : body
    , staticData : Dict String String
    }


contentJsonDecoder : Decode.Decoder (ContentJson String)
contentJsonDecoder =
    Decode.map2 ContentJson
        (Decode.field "body" Decode.string)
        (Decode.field "staticData" (Decode.dict Decode.string))


update :
    ContentCache metadata view
    -> (String -> Result ParseError view)
    -> Url
    -> ContentJson String
    -> ContentCache metadata view
update cacheResult renderer url rawContent =
    case cacheResult of
        Ok cache ->
            Dict.update (pathForUrl url)
                (\entry ->
                    case entry of
                        Just (Parsed metadata view) ->
                            entry

                        Just (Unparsed extension metadata content) ->
                            Parsed metadata
                                { body = renderer content.body
                                , staticData = content.staticData
                                }
                                |> Just

                        Just (NeedContent extension metadata) ->
                            Parsed metadata
                                { body = renderer rawContent.body
                                , staticData = rawContent.staticData
                                }
                                |> Just

                        Nothing ->
                            -- TODO this should never happen
                            Nothing
                )
                cache
                |> Ok

        Err error ->
            -- TODO update this ever???
            -- Should this be something other than the raw HTML, or just concat the error HTML?
            Err error


pathForUrl : Url -> Path
pathForUrl url =
    url.path
        |> dropTrailingSlash
        |> String.split "/"
        |> List.drop 1


lookup :
    pathKey
    -> ContentCache metadata view
    -> Url
    -> Maybe ( PagePath pathKey, Entry metadata view )
lookup pathKey content url =
    case content of
        Ok dict ->
            let
                path =
                    pathForUrl url
            in
            Dict.get path dict
                |> Maybe.map
                    (\entry ->
                        ( PagePath.build pathKey path, entry )
                    )

        Err _ ->
            Nothing


lookupMetadata :
    pathKey
    -> ContentCache metadata view
    -> Url
    -> Maybe ( PagePath pathKey, metadata )
lookupMetadata pathKey content url =
    lookup pathKey content url
        |> Maybe.map
            (\( pagePath, entry ) ->
                case entry of
                    NeedContent _ metadata ->
                        ( pagePath, metadata )

                    Unparsed _ metadata _ ->
                        ( pagePath, metadata )

                    Parsed metadata _ ->
                        ( pagePath, metadata )
            )


dropTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path
