module Ellie exposing (outputTab, outputTabElmCss)

import Element exposing (Element)
import Html
import Html.Attributes as Attr
import Html.Styled exposing (Html)
import Html.Styled.Attributes as StyledAttr


outputTab : String -> Element msg
outputTab ellieId =
    Html.iframe
        [ Attr.src <| "https://ellie-app.com/embed/" ++ ellieId ++ "?panel=output"
        , Attr.style "width" "100%"
        , Attr.style "height" "400px"
        , Attr.style "border" "0"
        , Attr.style "overflow" "hidden"
        , Attr.attribute "sandbox" "allow-modals allow-forms allow-popups allow-scripts allow-same-origin"
        ]
        []
        |> Element.html
        |> Element.el [ Element.width Element.fill ]


outputTabElmCss : String -> Html msg
outputTabElmCss ellieId =
    Html.Styled.iframe
        [ StyledAttr.src <| "https://ellie-app.com/embed/" ++ ellieId ++ "?panel=output"
        , StyledAttr.style "width" "100%"
        , StyledAttr.style "height" "400px"
        , StyledAttr.style "border" "0"
        , StyledAttr.style "overflow" "hidden"
        , StyledAttr.attribute "sandbox" "allow-modals allow-forms allow-popups allow-scripts allow-same-origin"
        ]
        []
