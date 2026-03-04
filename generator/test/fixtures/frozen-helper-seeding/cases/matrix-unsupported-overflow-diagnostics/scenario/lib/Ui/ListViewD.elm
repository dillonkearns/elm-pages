module Ui.ListViewD exposing (summaryCardsD)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper


summaryCardsD : List { name : String } -> List (Html msg)
summaryCardsD users =
    users |> List.map FrozenHelper.summaryCard
