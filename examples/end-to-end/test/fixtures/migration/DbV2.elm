module Db exposing (Db, Todo)


type alias Db =
    { todos : List Todo
    , nextId : Int
    }


type alias Todo =
    { id : Int
    , title : String
    , completed : Bool
    , description : String
    }
