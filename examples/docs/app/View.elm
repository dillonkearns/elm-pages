module View exposing (View, map, Static, static, staticView, embedStatic)

{-| The core View type for this application.

@docs View, map, Static, staticView, embedStatic

For static-only data and build-time helpers, import `View.Static` directly.

-}

import Html
import Html.Styled
import View.Static


{-| The View type that all pages must return.
-}
type alias View msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


{-| Transform the messages in a View.
-}
map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


{-| Static content type - Html.Styled that cannot produce messages.
Used for content that is pre-rendered at build time and adopted by virtual-dom.
-}
type alias Static =
    Html.Styled.Html Never


{-| Embed static content into a View body.

Takes plain Html Never (e.g. from View.Static.adopt) and converts it to
Html.Styled.Html msg for use in the view body.

-}
embedStatic : Html.Html Never -> Html.Styled.Html msg
embedStatic content =
    content
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Mark content as static for build-time rendering and client-side adoption.

Static content is:

  - Rendered at build time and included in the HTML
  - Adopted by the client without re-rendering
  - Eligible for dead-code elimination (the rendering code is removed from the client bundle)

Usage:

    view app shared model =
        { title = "My Page"
        , body =
            [ View.static landingView
            , dynamicContent model
            ]
        }

The content passed to `View.static` must be `Html.Styled.Html Never` (no event handlers).
This ensures the static content cannot produce messages and is purely presentational.

At build time, an ID is automatically assigned based on the order of `View.static`
calls in your view. The elm-review transformation replaces `View.static expr` with
`View.embedStatic (View.adopt "id")`, allowing DCE to eliminate `expr` and its dependencies.

-}
static : Static -> Html.Styled.Html msg
static content =
    content
        |> Html.Styled.toUnstyled
        |> View.Static.static
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Render static content using static-only data.

This bridges View.Static.view (which uses plain Html) with Html.Styled.

    view app =
        { body =
            [ View.staticView app.data.staticContent renderPage
            ]
        }

-}
staticView : View.Static.StaticOnlyData a -> (a -> Static) -> Html.Styled.Html msg
staticView staticOnlyData renderFn =
    View.Static.view staticOnlyData (\data -> Html.Styled.toUnstyled (renderFn data))
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never
