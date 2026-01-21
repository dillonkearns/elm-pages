module View.Static exposing (StaticId(..), adopt)

{-| This module provides primitives for "static regions" - parts of the view
that are pre-rendered at build time and adopted by the virtual-dom on the client
without re-rendering.

Static regions enable dead-code elimination of heavy dependencies like markdown
parsers and syntax highlighters while preserving the server-rendered HTML.


## How it works

1.  At build time, static content is rendered to HTML strings
2.  The HTML is embedded in the page and also included in page data for SPA navigation
3.  On initial page load, `adopt` finds existing DOM with matching `data-static` attribute
4.  On SPA navigation, `adopt` parses the HTML string into DOM
5.  The virtual-dom "adopts" this DOM without re-rendering
6.  Because the thunk refs are stable, the region is never diffed or updated

@docs StaticId, adopt

-}

import Html exposing (Html)
import Html.Lazy


{-| A marker type that identifies a static region. This is used internally
by the virtual-dom codemod to detect static adoption thunks.
-}
type StaticId
    = StaticId String


{-| Adopt a static region by ID. On initial page load, this will find and adopt
existing pre-rendered DOM with `data-static="<id>"`. On SPA navigation, this will
parse the provided HTML string into DOM.

    view : Html msg
    view =
        div []
            [ View.Static.adopt "rendered-markdown" staticHtmlFromData
            , button [ onClick Increment ] [ text "+" ]
            ]

The first argument is the region ID (must match the `data-static` attribute).
The second argument is the HTML fallback string (empty on initial load, actual
HTML on SPA navigation).

**Important:** This function uses `Html.Lazy.lazy2` internally with stable refs.
The virtual-dom codemod intercepts this thunk and handles adoption. The actual
function body (`\_ _ -> Html.text ""`) is never called on the client.

-}
adopt : String -> String -> Html msg
adopt id htmlFallback =
    Html.Lazy.lazy2 adoptThunk (StaticId id) htmlFallback


{-| Internal thunk function. This is never actually called on the client because
the virtual-dom codemod intercepts static region thunks before they're evaluated.

The function exists to satisfy the type system and provide a fallback for
non-patched environments (like tests or elm reactor).
-}
adoptThunk : StaticId -> String -> Html msg
adoptThunk _ _ =
    -- This is never called in production due to the codemod intercept.
    -- If it IS called, it means the codemod didn't work, so we return empty.
    Html.text ""
