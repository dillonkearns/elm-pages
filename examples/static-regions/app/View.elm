module View exposing (View, map, Static, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt)

{-|

@docs View, map, Static, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt

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
embedStatic static =
    Html.Styled.map never static


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
renderStatic id static =
    static
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
