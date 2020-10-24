module Dotted exposing (lines)

import Element
import Svg
import Svg.Attributes as Attr



{-
   .css-m2heu9 {
       stroke: #8a4baf;
       stroke-width: 3;
       stroke-linecap: round;
       stroke-dasharray: 0.5 10;
       -webkit-animation: animation-yweh2o 400ms linear infinite;
       animation: animation-yweh2o 400ms linear infinite;
   }
-}
{-
   <svg width="20" height="30" viewBox="0 0 20 30" class="css-p2euw5">
     <path d="M10 40 L10 -10" class="css-m2heu9"></path>
   </svg>
-}


lines =
    Svg.svg
        [ Attr.width "20"
        , Attr.height "30"
        , Attr.viewBox "0 0 20 30"
        ]
        [ Svg.path
            [ Attr.stroke "#2a75ff"
            , Attr.strokeWidth "4"
            , Attr.strokeLinecap "round"
            , Attr.strokeDasharray "0.5 10"
            , Attr.d "M10 40 L10 -10"
            , Attr.class "dotted-line"
            ]
            []
        ]
        |> Element.html
        |> Element.el
            [ Element.centerX
            ]



-- rgb(0, 36, 71)
-- #002447
{-

   .css-m2heu9{stroke:#8a4baf;stroke-width:3;stroke-linecap:round;stroke-dasharray:0.5 10;-webkit-animation:animation-yweh2o 400ms linear infinite;animation:animation-yweh2o 400ms linear infinite;}@-webkit-keyframes animation-yweh2o{to{stroke-dashoffset:10;}}@keyframes animation-yweh2o{to{stroke-dashoffset:10;}}
-}
