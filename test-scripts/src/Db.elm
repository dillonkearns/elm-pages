module Db exposing (Db, init)


type alias Db =
    { counter : Int
    }


init : Db
init =
    { counter = 0
    }
