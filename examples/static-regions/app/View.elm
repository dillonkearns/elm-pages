module View exposing (View, map, Static, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt, static)

{-|

@docs View, map, Static, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt, static

-}

import Html
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


{-| Convert Static content to plain Html for extraction at build time.
-}
staticToHtml : Static -> Html.Html Never
staticToHtml =
    Html.Styled.toUnstyled


{-| Convert plain Html to Static content for adoption at runtime.
-}
htmlToStatic : Html.Html Never -> Static
htmlToStatic =
    Html.Styled.fromUnstyled


{-| Embed static content into a View body.
Since Static is Html Never, it can safely become Html msg.
-}
embedStatic : Static -> Html.Styled.Html msg
embedStatic staticContent =
    Html.Styled.map never staticContent


{-| Render static content with a data-static attribute for extraction.
This is a temporary helper until build-time transformation is implemented.

Usage:

    view =
        { body =
            [ renderStatic "my-id" (staticContent ())
            ]
        }

After build-time transformation is implemented, this will become:

    view =
        { body =
            [ embedStatic (staticContent ())
            ]
        }

And `staticContent` will be transformed to return `View.Static.adopt "hash"`.

-}
renderStatic : String -> Static -> Html.Styled.Html msg
renderStatic id staticContent =
    staticContent
        |> staticToHtml
        |> View.Static.render id
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Adopt a static region by ID. This is used by the client-side code after
DCE transformation. On initial load, it adopts pre-rendered DOM. On SPA
navigation, it uses HTML from static-regions.json.
-}
adopt : String -> Static
adopt id =
    View.Static.adopt id
        |> Html.Styled.fromUnstyled


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
`View.adopt "id"`, allowing DCE to eliminate `expr` and its dependencies.

-}
static : Static -> Html.Styled.Html msg
static content =
    content
        |> staticToHtml
        |> View.Static.static
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never
