module ContentPage exposing (data)

import Html.Styled as Html exposing (Html)
import View


data : { title : String } -> Html msg
data info =
    View.freeze
        (Html.div []
            [ Html.text ("Data: " ++ info.title)
            ]
        )
