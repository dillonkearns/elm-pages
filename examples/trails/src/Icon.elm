module Icon exposing (error, icon2, icon3)

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


icon2 =
    svg
        [ SvgAttr.css
            [ Tw.h_full
            , Tw.w_full
            , Tw.text_gray_300
            ]
        , SvgAttr.fill "currentColor"
        , SvgAttr.viewBox "0 0 24 24"
        ]
        [ path
            [ SvgAttr.d "M24 20.993V24H0v-2.996A14.977 14.977 0 0112.004 15c4.904 0 9.26 2.354 11.996 5.993zM16.002 8.999a4 4 0 11-8 0 4 4 0 018 0z"
            ]
            []
        ]


icon3 =
    svg
        [ SvgAttr.css
            [ Tw.mx_auto
            , Tw.h_12
            , Tw.w_12
            , Tw.text_gray_400
            ]
        , SvgAttr.stroke "currentColor"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 48 48"
        ]
        [ path
            [ SvgAttr.d "M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
            , SvgAttr.strokeWidth "2"
            , SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            ]
            []
        ]
