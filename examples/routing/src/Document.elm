module Document exposing (Document, map, placeholder)

import Html.Styled exposing (text)


type alias Document msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


map : (msg1 -> msg2) -> Document msg1 -> Document msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


placeholder : String -> Document msg
placeholder moduleName =
    { title = "Placeholder - " ++ moduleName
    , body = [ text moduleName ]
    }
