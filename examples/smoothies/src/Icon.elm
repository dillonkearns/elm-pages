module Icon exposing (cart, refresh)

import Html exposing (Html)
import Html.Attributes as Attr
import Svg exposing (path, svg)
import Svg.Attributes as SvgAttr


refresh =
    svg
        [ SvgAttr.class "h-6 w-6"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.strokeWidth "2"
        ]
        [ path
            [ SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            , SvgAttr.d "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            ]
            []
        ]


cart =
    svg
        [ Attr.attribute "classname" "h-6 w-6"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.stroke "currentColor"
        , Attr.attribute "strokewidth" "{2}"
        ]
        [ path
            [ Attr.attribute "strokelinecap" "round"
            , Attr.attribute "strokelinejoin" "round"
            , SvgAttr.d "M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z"
            ]
            []
        ]
