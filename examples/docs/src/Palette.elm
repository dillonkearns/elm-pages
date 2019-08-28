module Palette exposing (color, heading)

import Element exposing (Element)
import Element.Font as Font
import Element.Region


color =
    { primary = Element.rgb255 42 117 255
    , secondary = Element.rgb255 108 123 149
    }


heading : Int -> List (Element msg) -> Element msg
heading level content =
    Element.paragraph
        [ Font.size
            (case level of
                1 ->
                    36

                2 ->
                    24

                _ ->
                    20
            )
        , Font.bold
        , Font.family [ Font.typeface "Raleway" ]
        , Element.Region.heading level
        ]
        content
