module View exposing (View, map, freeze, freezableToHtml, htmlToFreezable)

{-| View module for elm-pages with frozen view support.

@docs View, map, freeze, Freezable, freezableToHtml, htmlToFreezable

-}

import Html
import Html.Styled


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


{-| The type of content that can be frozen. Must produce no messages (Never).
Users can customize this type alias for their view library (elm-css, elm-ui, etc.).
-}
type alias Freezable =
    Html.Styled.Html Never


{-| Convert Freezable content to plain Html for server-side rendering.
-}
freezableToHtml : Freezable -> Html.Html Never
freezableToHtml =
    Html.Styled.toUnstyled


{-| Convert plain Html back to Freezable for client-side adoption.
-}
htmlToFreezable : Html.Html Never -> Freezable
htmlToFreezable =
    Html.Styled.fromUnstyled


{-| Mark content as frozen for build-time rendering and client-side adoption.

Frozen content is:

  - Rendered at build time and included in the HTML
  - Adopted by the client without re-rendering
  - Eligible for dead-code elimination (the rendering code is removed from the client bundle)

Usage:

    view app shared model =
        { title = "My Page"
        , body =
            [ View.freeze
                (div [] [ text ("Hello " ++ app.data.name) ])
            , -- Dynamic content that can use model
              button [ onClick Increment ] [ text (String.fromInt model.counter) ]
            ]
        }

The content passed to `View.freeze` must be `Html Never` (no event handlers).
This ensures the frozen content cannot produce messages and is purely presentational.

The elm-pages build system handles wrapping with `data-static` attributes on the server
and transforms `freeze` calls to lazy thunks on the client for DOM adoption.

-}
freeze : Freezable -> Html.Styled.Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.Styled.map never
