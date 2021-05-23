module View exposing (View, map, placeholder)

import Html.Styled exposing (text)


type alias View msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


placeholder : String -> View msg
placeholder moduleName =
    { title = "Placeholder - " ++ moduleName
    , body = [ text moduleName ]
    }
