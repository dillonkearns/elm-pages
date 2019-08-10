module DocumentSvg exposing (view)

import Html exposing (Html)
import Svg exposing (..)
import Svg.Attributes exposing (..)


view : Html msg
view =
    svg
        [ version "1.1"
        , viewBox "251.0485 144.52063 56.114286 74.5"
        , width "56.114286"
        , height "74.5"
        ]
        [ defs [] []
        , metadata [] [ text " Produced by OmniGraffle 7.11.1 " ]
        , g
            [ id "Canvas_11"
            , stroke "none"
            , fill "none"
            , strokeOpacity "1"
            , fillOpacity "1"
            , strokeDasharray "none"
            ]
            [ g [ id "Canvas_11: Layer 1" ]
                [ g [ id "Group_38" ]
                    [ g [ id "Graphic_32" ]
                        [ Svg.path
                            [ d "M 252.5485 146.02063 L 252.5485 217.52063 L 305.66277 217.52063 L 305.66277 161.68254 L 290.00087 146.02063 Z"
                            , stroke "black"
                            , strokeLinecap "round"
                            , strokeLinejoin "round"
                            , strokeWidth "3"
                            ]
                            []
                        ]
                    , g [ id "Line_34" ] [ line [ x1 "266.07286", y1 "182.8279", x2 "290.75465", y2 "183.00997", stroke "black", strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_35" ] [ line [ x1 "266.07286", y1 "191.84156", x2 "290.75465", y2 "192.02363", stroke "black", strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_36" ] [ line [ x1 "266.07286", y1 "200.85522", x2 "290.75465", y2 "201.0373", stroke "black", strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    , g [ id "Line_37" ] [ line [ x1 "266.07286", y1 "164.80058", x2 "278.3874", y2 "164.94049", stroke "black", strokeLinecap "round", strokeLinejoin "round", strokeWidth "2" ] [] ]
                    ]
                ]
            ]
        ]



-- <?xml version="1.0" encoding="UTF-8" standalone="no"?>
-- <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
-- <svg version="1.1" xmlns:xl="http://www.w3.org/1999/xlink" xmlns="http://www.w3.org/2000/svg" xmlns:dc="http://purl.org/dc/elements/1.1/" viewBox="251.0485 144.52063 56.114286 74.5" width="56.114286" height="74.5">
--   <defs/>
--   <metadata> Produced by OmniGraffle 7.11.1
--     <dc:date>2019-08-10 15:54:02 +0000</dc:date>
--   </metadata>
--   <g id="Canvas_11" stroke="none" fill="none" stroke-opacity="1" fill-opacity="1" stroke-dasharray="none">
--     <title>Canvas 11</title>
--     <g id="Canvas_11: Layer 1">
--       <title>Layer 1</title>
--       <g id="Group_38">
--         <g id="Graphic_32">
--           <path d="M 252.5485 146.02063 L 252.5485 217.52063 L 305.66277 217.52063 L 305.66277 161.68254 L 290.00087 146.02063 Z" stroke="black" stroke-linecap="round" stroke-linejoin="round" stroke-width="3"/>
--         </g>
--         <g id="Line_34">
--           <line x1="266.07286" y1="182.8279" x2="290.75465" y2="183.00997" stroke="black" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"/>
--         </g>
--         <g id="Line_35">
--           <line x1="266.07286" y1="191.84156" x2="290.75465" y2="192.02363" stroke="black" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"/>
--         </g>
--         <g id="Line_36">
--           <line x1="266.07286" y1="200.85522" x2="290.75465" y2="201.0373" stroke="black" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"/>
--         </g>
--         <g id="Line_37">
--           <line x1="266.07286" y1="164.80058" x2="278.3874" y2="164.94049" stroke="black" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"/>
--         </g>
--       </g>
--     </g>
--   </g>
-- </svg>
