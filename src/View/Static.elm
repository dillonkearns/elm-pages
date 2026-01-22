module View.Static exposing (StaticId(..), adopt, render)

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

@docs StaticId, adopt, render

-}

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy


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
