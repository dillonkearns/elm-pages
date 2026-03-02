---
description: Use a local type-safe database in elm-pages scripts with type-safe migrations.
---

# Local Type-Safe DB in `elm-pages` Scripts

`elm-pages` Scripts can read and write to **an Elm type** directly to a local database file using a `BackendTask`.

Think of it like `SQLite`, but with Elm types and type-safe migrations between versions of that Elm type.

This database API is **script-only**. Use it from `elm-pages run`, or CLIs that you bundle with `elm-pages bundle-script` (not from Route module, i.e. `preRender` or `serverRender`).

## Lamdera Inspiration

A big thank you to Mario Rogic for Lamdera and Evergreen Migrations. `elm-pages` uses the Lamdera compiler for binary serialization of Elm values, and this local DB uses a pattern inspired by [Lamdera's `Evergreen` migrations](https://dashboard.lamdera.app/docs/evergreen).

## Quick Start

Initialize the `Db.elm` file to create the scaffolding where you define the Elm type that you will be persisting in your database:

```shell
npx elm-pages db init
```

Modifying our `Db.elm` module with a simple counter app type:

```elm
module Db exposing (Db, init)


type alias Db =
    { count : Int }


init : Db
init =
    { count = 0 }
```

Use `Pages.Db` in a Script:

```elm
module Counter exposing (run)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import FilePath
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions loop


connection : Pages.Db.Connection
connection =
    FilePath.fromString ".elm-pages-data/counter.db.bin"
        |> Pages.Db.open


prompt : String
prompt =
    [ "[+] increment", "[-] decrement", "[q] quit" ]
        |> String.join ", "


loop : BackendTask FatalError ()
loop =
    -- Read your Db type from disk
    -- You get typed data without writing any Decoders!
    Pages.Db.get connection
        |> BackendTask.andThen
            (\db ->
                Script.log
                    ("\nCount: " ++ String.fromInt db.count)
                    |> BackendTask.and (Script.log ("Press " ++ prompt ++ ": "))
                    |> BackendTask.and Script.readKey
                    |> BackendTask.andThen handleKey
            )


handleKey : String -> BackendTask FatalError ()
handleKey key =
    case key of
        "+" ->
            -- Write your Db type to disk
            -- Notice that we don't write any Encoders, either!
            Pages.Db.update connection (\db -> { db | count = db.count + 1 })
                |> BackendTask.and loop

        "-" ->
            Pages.Db.update connection (\db -> { db | count = db.count - 1 })
                |> BackendTask.and loop

        "q" ->
            Script.log "Goodbye!"

        _ ->
            Script.log ("Unknown key: " ++ key)
                |> BackendTask.and loop
```

Run it:

```shell
npx elm-pages run script/src/Counter.elm

Count: 0
Press [+] increment, [-] decrement, [q] quit: +

Count: 1
Press [+] increment, [-] decrement, [q] quit: +

Count: 2
Press [+] increment, [-] decrement, [q] quit: -

Count: 1
Press [+] increment, [-] decrement, [q] quit: q
Goodbye!
```

## `Pages.Db` API

`Pages.Db` exposes:

```elm
-- The DB file this script will read/write from/to
type Connection

-- The default path, ./db.bin, relative to the current working directory
default : Connection

-- Choose a custom path for the DB file, like `FilePath.relative [ "config.bin" ]
open : FilePath -> Connection

-- Read the current DB value (initializes from seed if the file doesn't exist yet)
get : Connection -> BackendTask FatalError Db.Db

-- Transform and persist the DB value
update : Connection -> (Db.Db -> Db.Db) -> BackendTask FatalError ()

-- Run a read/modify/write step under a lock. You can pass a value back to the continuation via the tuple.
transaction :
    Connection
    -> (Db.Db -> BackendTask FatalError ( Db.Db, a ))
    -> BackendTask FatalError a
```

## Directory Structure

```text
.
├── script/
│   └── src/
│       ├── Db.elm          # current schema + V1 seed (`init`)
│       └── Counter.elm     # script that reads/writes DB
├── .elm-pages-db/
│   ├── schema-version.json # current schema version
│   └── Db/
│       └── Migrate/
│           ├── V2.elm      # migration: V1 -> V2
│           └── V3.elm      # migration: V2 -> V3
├── db.bin                  # default DB file (`Pages.Db.default`)
└── .elm-pages-data/
    └── counter.db.bin      # custom DB file (`Pages.Db.open`)
```

Internal/transient files omitted (for example `.elm-pages-db/MigrateChain.elm`, `.elm-pages-db/Db/V*.elm`, `db.lock`, `.elm-pages-db/schema-history/`).

## Git and `.gitignore`

Recommended:

- Commit `script/src/Db.elm` (or your `Db.elm` location).
- Commit `.elm-pages-db/Db/V*.elm` (generated snapshots; usually not edited directly).
- Commit `.elm-pages-db/Db/Migrate/V*.elm`.
- Commit `.elm-pages-db/MigrateChain.elm`.
- Commit `.elm-pages-db/schema-version.json`.

Usually ignore:

- `db.bin`
- `db.lock`
- `.elm-pages-db/schema-history/` (optional: commit this if you want stale-snapshot recovery shared across machines)

`elm-pages db init` creates `Db.elm` and also adds `db.bin` / `db.lock` ignore entries to `.gitignore`.

## Example: Run a Migration (V1 -> V2)

Start from the V1 schema shown above (`{ count : Int }`), and run your script once so `db.bin` exists:

```shell
npx elm-pages run script/src/Counter.elm
```

Now change `Db.elm` to V2:

```elm
module Db exposing (Db, init)


type alias Db =
    { count : Int
    , step : Int
    }


init : Db
init =
    { count = 0
    , step = 1
    }
```

Generate migration files:

```shell
npx elm-pages db migrate
```

```text
Created migration V1 -> V2:
  Snapshot: .elm-pages-db/Db/V1.elm
  Stub:     .elm-pages-db/Db/Migrate/V2.elm
  Chain:    .elm-pages-db/MigrateChain.elm
```

Implement `.elm-pages-db/Db/Migrate/V2.elm`:

```elm
module Db.Migrate.V2 exposing (migrate, seed)

import Db
import Db.V1


migrate : Db.V1.Db -> Db.Db
migrate old =
    { count = old.count
    , step = 1
    }


seed : Db.V1.Db -> Db.Db
seed old =
    migrate old
```

Apply the migration:

```shell
npx elm-pages db migrate
```

```text
Migration applied: V1 -> V2
```

## `migrate` and `seed`

Each migration module defines both:

```elm
-- used when upgrading existing stored data.  
migrate : Db.VN.Db -> Db.Db

-- used for fresh installs that start from `Db.V1.init`
-- and apply each migration's `seed` function in order.
seed : Db.VN.Db -> Db.Db
```

Generated stubs default `seed old = migrate old`, but you can override `seed` to choose a different from-scratch initialization path for new installs.

## Bundled Scripts and End Users

You can also use the Local DB functionality from `elm-pages bundle-script`! Migrations run when the bundled script executes on the end user's machine:

1. Developer bundles and publishes CLI JS
2. User installs package
3. User runs the CLI
4. First DB access initializes or migrates user-local DB automatically (using the path defined by the `Connection`)

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
