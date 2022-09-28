module Icon exposing (complete, incomplete)

import Html exposing (..)
import Svg
import Svg.Attributes as SvgAttr


complete : Html msg
complete =
    Svg.svg
        [ SvgAttr.width "40"
        , SvgAttr.height "40"
        , SvgAttr.viewBox "-10 -18 100 135"
        ]
        [ Svg.circle
            [ SvgAttr.cx "50"
            , SvgAttr.cy "50"
            , SvgAttr.r "50"
            , SvgAttr.fill "none"
            , SvgAttr.stroke "#bddad5"
            , SvgAttr.strokeWidth "3"
            ]
            []
        , Svg.path
            [ SvgAttr.fill "#5dc2af"
            , SvgAttr.d "M72 25L42 71 27 56l-4 4 20 20 34-52z"
            ]
            []
        ]


incomplete : Html msg
incomplete =
    Svg.svg
        [ SvgAttr.width "40"
        , SvgAttr.height "40"
        , SvgAttr.viewBox "-10 -18 100 135"
        ]
        [ Svg.circle
            [ SvgAttr.cx "50"
            , SvgAttr.cy "50"
            , SvgAttr.r "50"
            , SvgAttr.fill "none"
            , SvgAttr.stroke "#ededed"
            , SvgAttr.strokeWidth "3"
            ]
            []
        ]
