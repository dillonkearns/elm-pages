module View.Static exposing (StaticId(..), StaticOnlyData, adopt, backendTask, map, map2, render, static, view, wrap)

{-| This module provides primitives for "static regions" - parts of the view
that are pre-rendered at build time and adopted by the virtual-dom on the client
without re-rendering.

Static regions enable dead-code elimination of heavy dependencies like markdown
parsers and syntax highlighters while preserving the server-rendered HTML.


## How it works

1.  Define a top-level function: `myStaticView : () -> View.Static`
2.  At build time, this function is called and the HTML is extracted
3.  The function is transformed to return `adopt "hash"` (hash of HTML content)
4.  On initial page load, `adopt` finds existing DOM with matching `data-static` attribute
5.  On SPA navigation, `adopt` uses HTML from `static-regions.json`
6.  The virtual-dom "adopts" this DOM without re-rendering


## Usage

Define static content as a top-level function in your route module:

    staticContent : () -> View.Static
    staticContent () =
        Html.div []
            [ Markdown.toHtml markdownSource
            , SyntaxHighlight.toHtml codeBlock
            ]

Then embed it in your view:

    view app model =
        { body =
            [ View.embedStatic (staticContent ())
            , dynamicContent model
            ]
        }

At build time, `staticContent` is transformed to:

    staticContent : () -> View.Static
    staticContent _ =
        View.Static.adopt "a7f3b2c1"

@docs StaticId, adopt, render, static


## Static-Only Data

@docs StaticOnlyData, wrap, map, map2, backendTask, view

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy
import Pages.Internal.StaticOnlyData as Internal


{-| A marker type that identifies a static region. This is used internally
by the virtual-dom codemod to detect static adoption thunks.

Note: This type has two variants to prevent elm-optimize-level-2 from "unboxing"
it. Single-variant types get optimized away, but we need the $ property to be
preserved so the codemod can detect static region thunks.
-}
type StaticId
    = StaticId String
    | StaticId_DoNotUse_PreventUnboxing Never


{-| Render static content with a data-static attribute for extraction.
Used at build time - the HTML is extracted and stored in static-regions.json.

In the final client bundle, calls to static view functions are replaced with
`adopt`, so this function is only used during the build/server rendering phase.
-}
render : String -> Html Never -> Html Never
render id content =
    Html.div
        [ Attr.attribute "data-static" id
        ]
        [ content ]


{-| Adopt a static region by ID (hash). On initial page load, this will find
and adopt existing pre-rendered DOM with `data-static="<id>"`. On SPA navigation,
this will use HTML from the `static-regions.json` file.

This function returns `Html Never` because static content cannot produce messages.
Use `Html.map never` or `View.embedStatic` to embed in your view.

    -- A static view function after build-time transformation:
    staticContent : () -> View.Static
    staticContent _ =
        View.Static.adopt "a7f3b2c1"

-}
adopt : String -> Html Never
adopt id =
    Html.Lazy.lazy adoptThunk (StaticId id)


{-| Internal thunk function. This is never actually called on the client because
the virtual-dom codemod intercepts static region thunks before they're evaluated.
-}
adoptThunk : StaticId -> Html Never
adoptThunk _ =
    -- This is never called in production due to the codemod intercept.
    Html.text ""


{-| Mark content as static for build-time rendering.

This wraps content with a `data-static` attribute using a placeholder marker.
The build process assigns indices to these markers in DOM order, and the
elm-review transformation replaces `View.static` calls with `View.adopt "index"`.

The placeholder marker `__STATIC__` is replaced during extraction with actual
indices (0, 1, 2, etc.) based on the order of static regions in the rendered HTML.

-}
static : Html Never -> Html Never
static content =
    Html.div
        [ Attr.attribute "data-static" "__STATIC__"
        ]
        [ content ]


{-| Opaque wrapper for data that should only be used in static regions.

This data is:

  - Resolved at build time via BackendTask
  - NOT included in content.dat (discarded after rendering)
  - Only accessible through `Static.view`

This enables heavy data (parsed markdown ASTs, large datasets, etc.) to be used
for rendering static HTML without bloating the client bundle.

-}
type alias StaticOnlyData a =
    Internal.StaticOnlyData a


{-| Wrap data to mark it as static-only.

Use this in your BackendTask to create StaticOnlyData:

    staticData : BackendTask FatalError (StaticOnlyData MarkdownAst)
    staticData =
        loadAndParseMarkdown "content.md"
            |> BackendTask.map View.Static.wrap

-}
wrap : a -> StaticOnlyData a
wrap =
    Internal.StaticOnlyData


{-| Transform static-only data by applying a function to its contents.

This is safe to use at build time (in `head` functions, `data` functions, etc.).
On the client, the elm-review codemod transforms `View.Static.backendTask` to
`BackendTask.fail`, so the code path using `map` is never reached.

    head : App Data ActionData RouteParams {} -> List Head.Tag
    head app =
        View.Static.map app.data.staticContent
            (\content ->
                Seo.summary
                    { title = content.metadata.title
                    , description = content.metadata.description
                    }
            )

-}
map : StaticOnlyData a -> (a -> b) -> b
map staticData fn =
    fn (Internal.unwrap staticData)


{-| Combine two static-only data values by applying a function to both.

    View.Static.map2 app.data.metadata app.data.body
        (\meta body ->
            { title = meta.title
            , renderedBody = renderMarkdown body
            }
        )

-}
map2 : StaticOnlyData a -> StaticOnlyData b -> (a -> b -> c) -> c
map2 staticDataA staticDataB fn =
    fn (Internal.unwrap staticDataA) (Internal.unwrap staticDataB)


{-| Create a BackendTask that produces static-only data.

This is the recommended way to create StaticOnlyData. The elm-review codemod
transforms `View.Static.backendTask expr` to `BackendTask.fail` on the client,
enabling DCE of the wrapped BackendTask and its dependencies.

    staticContent : BackendTask FatalError (StaticOnlyData MarkdownAst)
    staticContent =
        View.Static.backendTask (parseMarkdown "content.md")

-}
backendTask : BackendTask FatalError a -> BackendTask FatalError (StaticOnlyData a)
backendTask task =
    BackendTask.map wrap task


{-| Render static content using static-only data.

This is the only way to access data wrapped in `StaticOnlyData`. The data is
unwrapped and passed to your render function, then the result is marked as
a static region.

    View.Static.view app.data.staticContent
        (\ast ->
            Markdown.toHtml ast
        )

At build time, this renders the content with the data. The elm-review codemod
transforms this to `View.adopt "id"`, eliminating both the data and render
function from the client bundle.

-}
view : StaticOnlyData a -> (a -> Html Never) -> Html Never
view staticData renderFn =
    Internal.unwrap staticData
        |> renderFn
        |> static
