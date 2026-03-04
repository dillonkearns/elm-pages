module Ui.ListViewB exposing (summaryCardsB)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper


summaryCardsB : List { name : String } -> List (Html msg)
summaryCardsB users =
    users |> List.map FrozenHelper.summaryCard
