module View.Static exposing (StaticId(..), adopt, render)

{-| This module provides primitives for "static regions" - parts of the view
that are pre-rendered at build time and adopted by the virtual-dom on the client
without re-rendering.

Static regions enable dead-code elimination of heavy dependencies like markdown
parsers and syntax highlighters while preserving the server-rendered HTML.


## How it works

1.  At build time, `render` outputs HTML with a `data-static` attribute
2.  The build process extracts static regions and stores them in `static-regions.dat`
3.  The client bundle transforms `render` calls into `adopt` calls (via elm-review)
4.  On initial page load, `adopt` finds existing DOM with matching `data-static` attribute
5.  On SPA navigation, `adopt` uses HTML from `static-regions.dat`
6.  The virtual-dom "adopts" this DOM without re-rendering

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


{-| Render a static region. On the server, this outputs the content wrapped
in a container with `data-static` attribute. On the client (after elm-review
transformation), this becomes an `adopt` call.

    view : Data -> Html msg
    view data =
        div []
            [ View.Static.render "markdown"
                (Markdown.toHtml data.markdownSource)
            , button [ onClick Increment ] [ text "+" ]
            ]

Arguments:

  - `id` - Unique identifier for this static region
  - `content` - The actual content to render (only runs on server)

**Note:** The elm-review codemod transforms this to `adopt id` in the client
bundle, so `content` is never evaluated on the client. The fallback HTML for
SPA navigation is automatically extracted from the build output.

-}
render : String -> Html msg -> Html msg
render id content =
    -- On server: renders content wrapped with data-static attribute
    -- On client (after codemod): this entire call becomes `adopt id`
    Html.div
        [ Attr.attribute "data-static" id
        ]
        [ content ]


{-| Adopt a static region by ID. On initial page load, this will find and adopt
existing pre-rendered DOM with `data-static="<id>"`. On SPA navigation, this will
use HTML from the `static-regions.dat` file.

This function is typically not called directly - use `render` instead, which
gets transformed to `adopt` by the elm-review codemod.

    -- After elm-review transformation, this:
    View.Static.render "markdown" content

    -- Becomes this:
    View.Static.adopt "markdown"

-}
adopt : String -> Html msg
adopt id =
    Html.Lazy.lazy adoptThunk (StaticId id)


{-| Internal thunk function. This is never actually called on the client because
the virtual-dom codemod intercepts static region thunks before they're evaluated.
-}
adoptThunk : StaticId -> Html msg
adoptThunk _ =
    -- This is never called in production due to the codemod intercept.
    Html.text ""
