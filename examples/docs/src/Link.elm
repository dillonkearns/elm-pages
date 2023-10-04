module Link exposing (Link, external, internal, link)

import Html.Styled exposing (Attribute, Html, a)
import Html.Styled.Attributes as Attr
import Route exposing (Route)


external : String -> Link
external =
    ExternalLink


internal : Route -> Link
internal =
    RouteLink


type Link
    = RouteLink Route
    | ExternalLink String


link : Link -> List (Attribute msg) -> List (Html msg) -> Html msg
link link_ attrs children =
    case link_ of
        RouteLink route ->
            Route.toLink
                (\anchorAttrs ->
                    a
                        (List.map Attr.fromUnstyled anchorAttrs ++ attrs)
                        children
                )
                route

        ExternalLink string ->
            a
                (Attr.href string :: attrs)
                children
