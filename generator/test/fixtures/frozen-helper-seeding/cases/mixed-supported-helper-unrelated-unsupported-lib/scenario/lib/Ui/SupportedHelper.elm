module Ui.SupportedHelper exposing (summaryCard)

import Html.Styled as Html exposing (Html)
import View


summaryCard : { name : String } -> Html msg
summaryCard user =
    View.freeze
        (Html.div []
            [ Html.text ("Supported: " ++ user.name)
            ]
        )
