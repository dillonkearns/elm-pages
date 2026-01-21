module View.Static exposing (StaticId(..), adopt, render)

{-| This module provides primitives for "static regions" - parts of the view
that are pre-rendered at build time and adopted by the virtual-dom on the client
without re-rendering.

Static regions enable dead-code elimination of heavy dependencies like markdown
parsers and syntax highlighters while preserving the server-rendered HTML.


## How it works

1.  At build time, `render` outputs HTML with a `data-static` attribute
2.  The client bundle transforms `render` calls into `adopt` calls (via elm-review)
3.  On initial page load, `adopt` finds existing DOM with matching `data-static` attribute
4.  On SPA navigation, `adopt` parses the HTML string from page data
5.  The virtual-dom "adopts" this DOM without re-rendering

@docs StaticId, adopt, render

-}

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy


{-| A marker type that identifies a static region. This is used internally
by the virtual-dom codemod to detect static adoption thunks.
-}
type StaticId
    = StaticId String


{-| Render a static region. On the server, this outputs the content wrapped
in a container with `data-static` attribute. On the client (after elm-review
transformation), this becomes an `adopt` call.

    view : StaticData -> Html msg
    view staticData =
        div []
            [ View.Static.render "markdown"
                staticData.renderedMarkdown  -- fallback HTML for SPA nav
                (div [] [ Html.text "Server-rendered content here" ])
            , button [ onClick Increment ] [ text "+" ]
            ]

Arguments:

  - `id` - Unique identifier for this static region
  - `fallbackHtml` - Pre-rendered HTML string for SPA navigation
  - `content` - The actual content to render (only runs on server)

**Note:** The elm-review codemod transforms this to `adopt id fallbackHtml`
in the client bundle, so `content` is never evaluated on the client.

-}
render : String -> String -> Html msg -> Html msg
render id fallbackHtml content =
    -- On server: renders content wrapped with data-static attribute
    -- On client (after codemod): this entire call becomes `adopt id fallbackHtml`
    Html.div
        [ Attr.attribute "data-static" id
        ]
        [ content ]


{-| Adopt a static region by ID. On initial page load, this will find and adopt
existing pre-rendered DOM with `data-static="<id>"`. On SPA navigation, this will
parse the provided HTML string into DOM.

This function is typically not called directly - use `render` instead, which
gets transformed to `adopt` by the elm-review codemod.

    -- After elm-review transformation, this:
    View.Static.render "markdown" fallbackHtml content

    -- Becomes this:
    View.Static.adopt "markdown" fallbackHtml

-}
adopt : String -> String -> Html msg
adopt id htmlFallback =
    Html.Lazy.lazy2 adoptThunk (StaticId id) htmlFallback


{-| Internal thunk function. This is never actually called on the client because
the virtual-dom codemod intercepts static region thunks before they're evaluated.
-}
adoptThunk : StaticId -> String -> Html msg
adoptThunk _ _ =
    -- This is never called in production due to the codemod intercept.
    Html.text ""
