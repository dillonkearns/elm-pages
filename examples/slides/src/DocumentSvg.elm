module DocumentSvg exposing (view)

import Color
import Element exposing (Element)
import Svg exposing (..)
import Svg.Attributes exposing (..)


strokeColor =
    -- "url(#grad1)"
    "black"


pageTextColor =
    "black"


fillColor =
    "url(#grad1)"



-- "none"


fillGradient =
    gradient
        (Color.rgb255 5 117 230)
        (Color.rgb255 0 242 96)



-- (Color.rgb255 252 0 255)
-- (Color.rgb255 0 219 222)
-- (Color.rgb255 255 93 194)
-- (Color.rgb255 255 150 250)


gradient color1 color2 =
    linearGradient [ id "grad1", x1 "0%", y1 "0%", x2 "100%", y2 "0%" ]
        [ stop
            [ offset "10%"
            , Svg.Attributes.style ("stop-color:" ++ Color.toCssString color1 ++ ";stop-opacity:1")
            ]
            []
        , stop [ offset "100%", Svg.Attributes.style ("stop-color:" ++ Color.toCssString color2 ++ ";stop-opacity:1") ] []
        ]


view : Element msg
view =
    svg
        [ version "1.1"
        , viewBox "251.0485 144.52063 56.114286 74.5"
        , width "56.114286"
        , height "74.5"
        , Svg.Attributes.width "30px"
        ]
        [ defs []
            [ fillGradient ]
        , metadata [] []
        , g
            [ id "Canvas_11"
            , stroke "none"
            , fill fillColor
            , strokeOpacity "1"
            , fillOpacity "1"
            , strokeDasharray "none"
            ]
            [ g [ id "Canvas_11: Layer 1" ]
                [ g [ id "Group_38" ]
                    [ g [ id "Graphic_32" ]
                        [ Svg.path
                            [ d "M 252.5485 146.02063 L 252.5485 217.52063 L 305.66277 217.52063 L 305.66277 161.68254 L 290.00087 146.02063 Z"
                            , stroke strokeColor
                            , strokeLinecap "round"
                            , strokeLinejoin "round"
                            , strokeWidth "3"
                            ]
                            []
                        ]
                    , g [ id "Line_34" ] [ line [ x1 "266.07286", y1 "182.8279", x2 "290.75465", y2 "183.00997", stroke pageTextColor, strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_35" ] [ line [ x1 "266.07286", y1 "191.84156", x2 "290.75465", y2 "192.02363", stroke pageTextColor, strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_36" ] [ line [ x1 "266.07286", y1 "200.85522", x2 "290.75465", y2 "201.0373", stroke pageTextColor, strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_37" ] [ line [ x1 "266.07286", y1 "164.80058", x2 "278.3874", y2 "164.94049", stroke pageTextColor, strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    ]
                ]
            ]
        ]
        |> Element.html
        |> Element.el []
