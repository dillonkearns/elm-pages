module Document exposing (Document, map)

import Html.Styled


type alias Document msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


map : (msg1 -> msg2) -> Document msg1 -> Document msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }
