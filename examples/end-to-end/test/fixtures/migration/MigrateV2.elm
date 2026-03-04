module Db.Migrate.V2 exposing (migrate, seed)

import Db
import Db.V1


migrate : Db.V1.Db -> Db.Db
migrate old =
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


seed : Db.V1.Db -> Db.Db
seed old =
    migrate old
