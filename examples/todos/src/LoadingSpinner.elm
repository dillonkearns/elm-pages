module LoadingSpinner exposing (view)

{-| -}

import Html exposing (Html)
import Html.Attributes as Attr


{-| Source; <https: //projects.lukehaas.me/css-loaders/>
-}
view : Html msg
view =
    Html.div
        [ Attr.class "loader"
        , Attr.style "font-size" "4px"
        ]
        []
