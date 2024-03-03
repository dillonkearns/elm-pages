module View exposing (View, map)

{-|
@docs map, View
 -}


import Html.Styled as Html exposing (Html)

{-| -}
type alias View msg =
    { title : String
    , body : List (Html msg)
    }


{-| -}
map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn view =
    { title = view.title
    , body = List.map (Html.map fn) view.body
    }


