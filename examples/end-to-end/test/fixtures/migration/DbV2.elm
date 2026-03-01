module Db exposing (Db, Todo, init)


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


init : Db
init =
    { todos = []
    , nextId = 1
    }
