module View exposing (View, map, Static, staticView, embedStatic)

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
