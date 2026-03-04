module Ui.FrozenHelper exposing (summaryCardWithPrefix)

import Html.Styled as Html exposing (Html)
import View


summaryCardWithPrefix : String -> { name : String } -> Html msg
summaryCardWithPrefix prefix user =
    View.freeze
        (Html.div []
            [ Html.text (prefix ++ user.name)
            ]
        )
