module FrozenHelper exposing (summaryCard)

import Html exposing (Html, div, p, text)
import Html.Attributes as Attr
import View


type alias CardData =
    { title : String
    , details : String
    }


summaryCard : CardData -> Html msg
summaryCard cardData =
    View.freeze
        (div [ Attr.class "border border-blue-200 rounded-md px-4 py-3 bg-blue-50" ]
            [ p [ Attr.class "text-sm font-semibold text-blue-800 mb-1" ] [ text cardData.title ]
            , p [ Attr.class "text-sm text-blue-700" ] [ text cardData.details ]
            ]
        )
