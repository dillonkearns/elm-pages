module Pages.Internal.DbRequest exposing
    ( readMeta, write
    , lockAcquire, lockRelease
    , migrateRead, migrateWrite
    )

{-| Exposed for internal use only (used in generated code).

Backs the elm-pages CLI-generated `Pages.Db` and `MigrateChain` modules.
Each function targets exactly one `elm-pages-internal://db-*` runtime
handler — the endpoint name is hardcoded so callers cannot pivot to
non-DB internal routes.

@docs readMeta, write
@docs lockAcquire, lockRelease
@docs migrateRead, migrateWrite

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body)
import BackendTask.Internal.Request as Internal
import Bytes.Decode
import FatalError exposing (FatalError)
import Json.Decode exposing (Decoder)


{-| Read the on-disk db.bin metadata + payload for a connection. Targets
`elm-pages-internal://db-read-meta`.
-}
readMeta :
    { body : Body
    , decoder : Bytes.Decode.Decoder a
    }
    -> BackendTask FatalError a
readMeta { body, decoder } =
    Internal.requestBytes
        { name = "db-read-meta"
        , body = body
        , expect = decoder
        }


{-| Write a new db.bin payload. Targets `elm-pages-internal://db-write`.
-}
write :
    { headers : List ( String, String )
    , body : Body
    , decoder : Decoder a
    }
    -> BackendTask FatalError a
write { headers, body, decoder } =
    Internal.requestWithHeaders
        { name = "db-write"
        , headers = headers
        , body = body
        , expect = decoder
        }


{-| Acquire the write lock for a connection. Targets
`elm-pages-internal://db-lock-acquire`.
-}
lockAcquire :
    { body : Body
    , decoder : Decoder a
    }
    -> BackendTask FatalError a
lockAcquire { body, decoder } =
    Internal.request
        { name = "db-lock-acquire"
        , body = body
        , expect = decoder
        }


{-| Release a previously-acquired write lock. Targets
`elm-pages-internal://db-lock-release`.
-}
lockRelease :
    { body : Body
    , decoder : Decoder a
    }
    -> BackendTask FatalError a
lockRelease { body, decoder } =
    Internal.request
        { name = "db-lock-release"
        , body = body
        , expect = decoder
        }


{-| Read raw db.bin during a migration script. Targets
`elm-pages-internal://db-migrate-read`.
-}
migrateRead :
    { body : Body
    , decoder : Bytes.Decode.Decoder a
    }
    -> BackendTask FatalError a
migrateRead { body, decoder } =
    Internal.requestBytes
        { name = "db-migrate-read"
        , body = body
        , expect = decoder
        }


{-| Write a migrated db.bin. Targets
`elm-pages-internal://db-migrate-write`. Used both by `Pages.Db` (with
connection headers) and by `MigrateChain` (with no headers).
-}
migrateWrite :
    { headers : List ( String, String )
    , body : Body
    , decoder : Decoder a
    }
    -> BackendTask FatalError a
migrateWrite { headers, body, decoder } =
    Internal.requestWithHeaders
        { name = "db-migrate-write"
        , headers = headers
        , body = body
        , expect = decoder
        }
