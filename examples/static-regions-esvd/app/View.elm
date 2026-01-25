module View exposing (View, map, Static, static, staticView)

{-| View module for elm-pages.

@docs View, map, Static, static, staticView

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


{-| Static content type - cannot produce messages (Html Never).
Used for content that is pre-rendered at build time and adopted by virtual-dom.
-}
type alias Static =
    Html.Styled.Html Never


{-| Mark content as static for build-time rendering and client-side adoption.

Static content is:

  - Rendered at build time and included in the HTML
  - Adopted by the client without re-rendering
  - Eligible for dead-code elimination (the rendering code is removed from the client bundle)

Usage:

    view app shared model =
        { title = "My Page"
        , body =
            [ View.static
                (div [] [ text ("Hello " ++ app.data.name) ])
            , -- Dynamic content that can use model
              button [ onClick Increment ] [ text (String.fromInt model.counter) ]
            ]
        }

The content passed to `View.static` must be `Html Never` (no event handlers).
This ensures the static content cannot produce messages and is purely presentational.

At build time, an ID is automatically assigned based on the order of `View.static`
calls in your view. The elm-review transformation replaces `View.static expr` with
`View.Static.adopt "id"`, allowing DCE to eliminate `expr` and its dependencies.

-}
static : Static -> Html.Styled.Html msg
static content =
    content
        |> Html.Styled.toUnstyled
        |> View.Static.static
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Render static content using static-only data from `app.staticData`.

This is the only way to access data wrapped in `StaticOnlyData`. The data is
unwrapped and passed to your render function, then the result is marked as
a static region.

    view app shared model =
        { body =
            [ View.staticView app.staticData
                (\content -> Markdown.toHtml content)
            ]
        }

At build time, this renders the content with the data. The elm-review codemod
transforms this to `View.Static.adopt "id"`, eliminating both the data and render
function from the client bundle.

-}
staticView : View.Static.StaticOnlyData a -> (a -> Static) -> Html.Styled.Html msg
staticView staticOnlyData renderFn =
    View.Static.view staticOnlyData (\data -> Html.Styled.toUnstyled (renderFn data))
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never
