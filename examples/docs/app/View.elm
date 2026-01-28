module View exposing (View, freeze, map)

import Html exposing (Html)
import View.Static


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.map fn) doc.body
    }


{-| Freeze a view so its content is rendered at build time and not hydrated on the client.
Use this for static content that doesn't need interactivity.

At build time, this wraps the content with a `data-static` attribute.
The elm-review codemod then transforms this to `View.Static.adopt` on the client,
which adopts the pre-rendered DOM without re-rendering.
-}
freeze : Html Never -> Html msg
freeze content =
    View.Static.static content
        |> Html.map never
