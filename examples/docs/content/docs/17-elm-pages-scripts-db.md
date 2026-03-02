---
description: Use a local type-safe database in elm-pages scripts with type-safe migrations.
---

# Local Type-Safe DB in `elm-pages` Scripts

`elm-pages` Scripts can read and write to **an Elm type** directly to a local database file using a `BackendTask`.

Think of it like `Sqlite`, but with Elm types and type-safe migrations between versions of that Elm type.

## Lamdera Inspiration

A big thank you to Mario Rogic for Lamdera and Evergreen Migrations. `elm-pages` uses the Lamdera compiler for binary serialization of Elm values, and this local DB uses a pattern inspired by [Lamdera's `Evergreen` migrations](https://dashboard.lamdera.app/docs/evergreen).

## Quick Start

Initialize a `Db.elm` file:

```shell
npx elm-pages db init
```

Example `Db.elm`:

```elm
module Db exposing (Db, Todo, init)


type alias Todo =
    { id : Int
    , title : String
    , done : Bool
    }


type alias Db =
    { todos : List Todo
    , nextId : Int
    }


init : Db
init =
    { todos = []
    , nextId = 1
    }
```

Use `Pages.Db` in a Script:

```elm
module AddTodo exposing (run)

import BackendTask exposing (BackendTask)
import FilePath
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Pages.Db.transaction
            (\db ->
                let
                    todoId =
                        db.nextId

                    updatedDb =
                        { db
                            | todos =
                                db.todos
                                    ++ [ { id = todoId, title = "Ship docs", done = False } ]
                            , nextId = todoId + 1
                        }
                in
                BackendTask.succeed ( updatedDb, () )
            )
            |> BackendTask.allowFatal
        )
        |> Script.withDatabasePath (FilePath.fromString ".elm-pages-data/prefs.db.bin")
```

Run it:

```shell
npx elm-pages run script/src/AddTodo.elm
```

## `Pages.Db` API

`Pages.Db` exposes:

```elm
get : BackendTask FatalError Db.Db
update : (Db.Db -> Db.Db) -> BackendTask FatalError ()
transaction : (Db.Db -> BackendTask FatalError ( Db.Db, a )) -> BackendTask FatalError a
```

Use `Script.withDatabasePath` once at the top level of your script to set where DB data is stored for that run.

## Migration Files

When your schema changes, `elm-pages db migrate` manages migration scaffolding in `.elm-pages-db/`:

- `.elm-pages-db/Db/V1.elm`, `.elm-pages-db/Db/V2.elm`, ... (schema snapshots)
- `.elm-pages-db/Db/Migrate/V2.elm`, `.elm-pages-db/Db/Migrate/V3.elm`, ... (migration modules)
- `.elm-pages-db/schema-version.json` (current schema version)

Typical flow:

1. Edit `Db.elm`.
2. Run `npx elm-pages db migrate` to scaffold snapshot + migration stub.
3. Implement the stub.
4. Run `npx elm-pages db migrate` again to apply it to local `db.bin`.

Example scaffold output:

```text
Created migration V1 -> V2:
  Snapshot: .elm-pages-db/Db/V1.elm
  Stub:     .elm-pages-db/Db/Migrate/V2.elm
  Chain:    .elm-pages-db/MigrateChain.elm
```

## `migrate` and `seed`

Each migration module defines both:

- `migrate : Db.VN.Db -> Db.Db`
- `seed : Db.VN.Db -> Db.Db`

`migrate` is used when upgrading existing stored data.  
`seed` is used for fresh installs that start from `Db.V1.init` and apply each migration's `seed` function in order.

Generated stubs default `seed old = migrate old`, but you can override `seed` to choose a different from-scratch initialization path for new installs.

## Bundled Scripts and End Users

`elm-pages bundle-script` does **not** migrate or mutate the developer's local `db.bin`.

Migrations run when the bundled script executes on the user's machine:

1. Developer bundles and publishes CLI JS.
2. User installs package.
3. User runs command.
4. First DB access initializes or migrates user-local DB automatically (using configured path).

So end users usually do not see migration steps. They just get the latest schema behavior when the command runs.

## Stale Snapshot Safety

If `Db.elm` was edited before the old schema snapshot was captured, `elm-pages db migrate` will stop and explain how to recover safely.

If schema history is available, it can auto-recover the old snapshot source.  
There is also an escape hatch:

```shell
npx elm-pages db migrate --force-stale-snapshot
```

Use that only if you understand the risk: it may snapshot the wrong schema as the old version.

## Helpful Commands

```shell
# Show schema/db compatibility and migration status
npx elm-pages db status

# Reset local db.bin and db.lock
npx elm-pages db reset
```
