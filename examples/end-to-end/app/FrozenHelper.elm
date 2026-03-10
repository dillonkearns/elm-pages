module FrozenHelper exposing (badge, summaryCard)

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


badge : String -> Html msg
badge label =
    View.freeze
        (Html.span [ Attr.class "inline-flex items-center rounded-full bg-indigo-100 px-2.5 py-0.5 text-xs font-medium text-indigo-800" ]
            [ Html.text label ]
        )
