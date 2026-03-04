module FrozenHelper exposing (routeBanner, sharedBanner)

import Html.Styled as Html exposing (Html)
import View


routeBanner : Html msg
routeBanner =
    View.freeze
        (Html.div []
            [ Html.text "Route zero-arg banner"
            ]
        )


sharedBanner : Html msg
sharedBanner =
    View.freeze
        (Html.div []
            [ Html.text "Shared zero-arg banner"
            ]
        )
