module Ui.ListViewC exposing (summaryCardsC)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper


summaryCardsC : List { name : String } -> List (Html msg)
summaryCardsC users =
    users |> List.map FrozenHelper.summaryCard
