module Icon exposing (error)

import Html.Styled exposing (Html)
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Utilities as Tw


error : Html msg
error =
    svg
        [ SvgAttr.css
            [ Tw.h_5
            , Tw.w_5
            , Tw.text_red_500
            ]
        , SvgAttr.viewBox "0 0 20 20"
        , SvgAttr.fill "currentColor"
        ]
        [ path
            [ SvgAttr.fillRule "evenodd"
            , SvgAttr.d "M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
            , SvgAttr.clipRule "evenodd"
            ]
            []
        ]
