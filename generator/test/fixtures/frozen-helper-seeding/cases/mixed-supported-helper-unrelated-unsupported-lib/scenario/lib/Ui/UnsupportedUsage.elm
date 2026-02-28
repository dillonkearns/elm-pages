module Ui.UnsupportedUsage exposing (cards)

import Html.Styled exposing (Html)
import Ui.UnsupportedHelper as UnsupportedHelper


cards : List { name : String } -> List (Html msg)
cards users =
    users |> List.map UnsupportedHelper.card
