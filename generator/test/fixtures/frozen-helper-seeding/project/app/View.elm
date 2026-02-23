module View exposing (View, map, freeze, freezableToHtml, htmlToFreezable)

import Html
import Html.Styled


type alias View msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


type alias Freezable =
    Html.Styled.Html Never


freezableToHtml : Freezable -> Html.Html Never
freezableToHtml =
    Html.Styled.toUnstyled


htmlToFreezable : Html.Html Never -> Freezable
htmlToFreezable =
    Html.Styled.fromUnstyled


freeze : Freezable -> Html.Styled.Html msg
freeze content =
    content
        |> freezableToHtml
        |> htmlToFreezable
        |> Html.Styled.map never
