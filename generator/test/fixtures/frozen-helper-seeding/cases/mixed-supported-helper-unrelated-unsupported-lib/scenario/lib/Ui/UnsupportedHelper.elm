module Ui.UnsupportedHelper exposing (card)

import Html.Styled as Html exposing (Html)
import View


card : { name : String } -> Html msg
card user =
    View.freeze
        (Html.div []
            [ Html.text ("Unsupported: " ++ user.name)
            ]
        )
