module Document exposing (Document, map, placeholder)

import Html exposing (Html)


type alias View Msg =
    { title : String
    , body : List (Html msg)
    }


map : (msg1 -> msg2) -> View Msg1 -> View Msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.map fn) doc.body
    }


placeholder : String -> View Msg
placeholder moduleName =
    { title = "Placeholder - " ++ moduleName
    , body = [ Html.text moduleName ]
    }
