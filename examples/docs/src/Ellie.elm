module Ellie exposing (outputTabElmCss)

import Html.Styled exposing (Html)
import Html.Styled.Attributes as StyledAttr


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
