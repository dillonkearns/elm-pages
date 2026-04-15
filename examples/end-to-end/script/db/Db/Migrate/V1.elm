module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    { todos = []
    , nextId = 0
    }


migrate : () -> Db.Db
migrate =
    seed
