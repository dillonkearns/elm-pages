module View exposing (View, map, freeze)

{-| View module for elm-pages.

@docs View, map, freeze

-}

import Html.Styled
import View.Static


{-| -}
type alias View msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


{-| -}
map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


{-| Mark content as frozen for build-time rendering and client-side adoption.

Frozen content is:

  - Rendered at build time and included in the HTML
  - Adopted by the client without re-rendering
  - Eligible for dead-code elimination (the rendering code is removed from the client bundle)

Usage:

    view app shared =
        { title = "My Page"
        , body =
            [ h1 [] [ text app.data.title ]  -- Persistent, sent to client
            , View.freeze (renderMarkdown app.data.content)  -- Ephemeral, DCE'd
            , button [ onClick Increment ] [ text (String.fromInt model.counter) ]
            ]
        }

The content passed to `View.freeze` must be `Html Never` (no event handlers).
This ensures the frozen content cannot produce messages and is purely presentational.

Fields from `app.data` that are ONLY accessed inside `View.freeze` calls are
automatically detected and removed from the client-side Data type, enabling
dead-code elimination of the render functions and their dependencies.

At build time, an ID is automatically assigned based on the order of `View.freeze`
calls in your view. The elm-review transformation replaces `View.freeze expr` with
`View.Static.adopt "id"`, allowing DCE to eliminate `expr` and its dependencies.

Important: Do not reference `model` inside `View.freeze` - frozen content is
rendered at build time when model doesn't exist. The elm-review rule will
report an error if you try to use model inside freeze.

-}
freeze : Html.Styled.Html Never -> Html.Styled.Html msg
freeze content =
    content
        |> Html.Styled.toUnstyled
        |> View.Static.static
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never
