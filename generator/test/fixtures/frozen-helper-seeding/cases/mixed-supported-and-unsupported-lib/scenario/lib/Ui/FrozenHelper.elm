module Ui.FrozenHelper exposing (summaryCard)

import Html.Styled as Html exposing (Html)
import View


summaryCard : { name : String } -> Html msg
summaryCard user =
    View.freeze
        (Html.div []
            [ Html.text ("User: " ++ user.name)
            ]
        )
