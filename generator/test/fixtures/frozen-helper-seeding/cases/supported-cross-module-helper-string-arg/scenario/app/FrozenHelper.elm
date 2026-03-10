module FrozenHelper exposing (badge)

import Html.Styled as Html exposing (Html)
import View


badge : String -> Html msg
badge label =
    View.freeze (Html.span [] [ Html.text ("Badge: " ++ label) ])
