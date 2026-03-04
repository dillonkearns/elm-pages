module Ui.ListViewA exposing (summaryCardsA)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper


summaryCardsA : List { name : String } -> List (Html msg)
summaryCardsA users =
    users |> List.map FrozenHelper.summaryCard
