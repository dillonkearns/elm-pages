module Link exposing (link)

import Html.Styled exposing (Attribute, Html, a)
import Html.Styled.Attributes as Attr
import Route exposing (Route)


link : Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route attrs children =
    Route.toLink
        (\anchorAttrs ->
            a
                (List.map Attr.fromUnstyled anchorAttrs ++ attrs)
                children
        )
        route
