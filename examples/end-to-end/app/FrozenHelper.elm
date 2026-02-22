module FrozenHelper exposing (summaryCard)

import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import View


type alias SummaryCardData =
    { title : String
    , details : String
    }


summaryCard : SummaryCardData -> Html msg
summaryCard cardData =
    View.freeze
        (Html.div [ Attr.class "border border-blue-200 rounded-md px-4 py-3 bg-blue-50 mb-3" ]
            [ Html.p [ Attr.class "text-sm font-semibold text-blue-800 mb-1" ] [ Html.text cardData.title ]
            , Html.p [ Attr.class "text-sm text-blue-700" ] [ Html.text cardData.details ]
            ]
        )
