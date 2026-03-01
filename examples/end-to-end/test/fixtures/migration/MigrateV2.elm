module Db.Migrate.V2 exposing (db)

import Db
import Db.V1


db : Db.V1.Db -> Db.Db
db old =
    { todos =
        List.map
            (\t ->
                { id = t.id
                , title = t.title
                , completed = t.completed
                , description = ""
                }
            )
            old.todos
    , nextId = old.nextId
    }
