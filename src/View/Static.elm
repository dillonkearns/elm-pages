module View.Static exposing (StaticId(..), adopt, render, static)

{-| This module provides primitives for "static regions" - parts of the view
that are pre-rendered at build time and adopted by the virtual-dom on the client
without re-rendering.

Static regions enable dead-code elimination of heavy dependencies like markdown
parsers and syntax highlighters while preserving the server-rendered HTML.


## How it works

1.  Wrap content with `View.static` in your route's view function
2.  At build time, this content is rendered and the HTML is extracted
3.  An elm-review codemod transforms `View.static expr` to `View.Static.adopt "id"`
4.  On initial page load, `adopt` finds existing DOM with matching `data-static` attribute
5.  On SPA navigation, `adopt` uses HTML from `content.dat` (static regions are embedded in the page data)
6.  The virtual-dom "adopts" this DOM without re-rendering


## Usage

Use `View.static` in your route's view function:

    view app model =
        { body =
            [ View.static (Markdown.toHtml app.data.content)
            , dynamicContent model
            ]
        }

At build time, the codemod transforms this to:

    view app model =
        { body =
            [ View.Static.adopt "0" |> Html.map never
            , dynamicContent model
            ]
        }

The markdown parser and its dependencies are eliminated from the client bundle via DCE.

@docs StaticId, adopt, render, static

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
Used at build time - the HTML is extracted and embedded in content.dat.

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
this will use HTML from `content.dat` (static regions are embedded in the page data).

This function returns `Html Never` because static content cannot produce messages.
Use `Html.map never` to embed in your view.

    -- A static view function after build-time transformation:
    view app model =
        { body =
            [ View.Static.adopt "0" |> Html.map never
            ]
        }

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
