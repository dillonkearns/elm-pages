module Widget exposing (init, update, view)

import Html.Styled as Html exposing (Html)
import View


init : { label : String } -> Html msg
init config =
    View.freeze
        (Html.div []
            [ Html.text ("Init: " ++ config.label)
            ]
        )


update : { label : String } -> Html msg
update config =
    View.freeze
        (Html.div []
            [ Html.text ("Update: " ++ config.label)
            ]
        )


view : { label : String } -> Html msg
view config =
    View.freeze
        (Html.div []
            [ Html.text ("View: " ++ config.label)
            ]
        )
