module Ui.ListView exposing (summaryCards)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper


summaryCards : List { name : String } -> List (Html msg)
summaryCards users =
    users |> List.map FrozenHelper.summaryCard
