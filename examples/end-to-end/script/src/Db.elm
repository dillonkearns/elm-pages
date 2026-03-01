module Db exposing (Db, init)


type alias Db =
    { counter : Int
    , name : String
    }


init : Db
init =
    { counter = 0
    , name = ""
    }
