module FrozenHelper exposing (routeCard, sharedCard)

import Html.Styled as Html exposing (Html)
import View


routeCard : { name : String } -> Html msg
routeCard user =
    View.freeze
        (Html.div []
            [ Html.text ("Route user: " ++ user.name)
            ]
        )


sharedCard : { name : String } -> Html msg
sharedCard user =
    View.freeze
        (Html.div []
            [ Html.text ("Shared user: " ++ user.name)
            ]
        )
