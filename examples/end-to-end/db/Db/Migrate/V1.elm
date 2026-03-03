module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    { todos = []
    , nextId = 1
    }


migrate : () -> Db.Db
migrate =
    seed
