module ContentPage exposing (view)

import Html.Styled as Html exposing (Html)
import View


view : { title : String } -> { showMobileMenu : Bool } -> Html msg
view data shared =
    View.freeze
        (Html.div []
            [ Html.text ("Page: " ++ data.title ++ " menu=" ++ boolToString shared.showMobileMenu)
            ]
        )


boolToString : Bool -> String
boolToString b =
    if b then
        "true"

    else
        "false"
