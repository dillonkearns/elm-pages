module View exposing (View, map, freeze, freezableToHtml, htmlToFreezable)

{-| View module for elm-pages with frozen view support.

@docs View, map, freeze, Freezable, freezableToHtml, htmlToFreezable

-}

import Html exposing (Html)


{-| -}
type alias View msg =
    { title : String
    , body : List (Html msg)
    }


{-| -}
map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.map fn) doc.body
    }


{-| The type of content that can be frozen. Must produce no messages (Never).
For plain Html, this is just Html Never.
-}
type alias Freezable =
    Html Never


{-| Convert Freezable content to plain Html for server-side rendering.
For plain Html, this is identity.
-}
freezableToHtml : Freezable -> Html Never
freezableToHtml =
    identity


{-| Convert plain Html back to Freezable for client-side adoption.
For plain Html, this is identity.
-}
htmlToFreezable : Html Never -> Freezable
htmlToFreezable =
    identity


{-| Freeze a view so its content is rendered at build time and adopted on the client.
Use this for static content that doesn't need interactivity.

Frozen content is:

  - Rendered at build time and included in the HTML
  - Adopted by the client without re-rendering
  - Eligible for dead-code elimination (rendering code removed from client bundle)

At build time, the server codemod wraps the content with a `data-static` attribute for extraction.
The elm-review codemod then transforms `freeze` calls to lazy thunks on the client,
which adopt the pre-rendered DOM without re-rendering.

-}
freeze : Freezable -> Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.map never
