module FontAwesome exposing (icon, styledIcon)

import Element exposing (Element)
import Html
import Html.Attributes


styledIcon : String -> List (Element.Attribute msg) -> Element msg
styledIcon classString styles =
    Html.i [ Html.Attributes.class classString ] []
        |> Element.html
        |> Element.el styles


icon : String -> Element msg
icon classString =
    Html.i [ Html.Attributes.class classString ] []
        |> Element.html
