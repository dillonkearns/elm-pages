---
description: Use a local type-safe database in elm-pages scripts with type-safe migrations.
---

# Local Type-Safe DB in `elm-pages` Scripts

`elm-pages` Scripts can read and write to **an Elm type** directly to a local database file using a `BackendTask`.

Think of it like `SQLite`, but with Elm types and type-safe migrations between versions of that Elm type.

This database API is currently **Script-only**.
Use it from `elm-pages run ...` or bundled scripts, not from Route modules (`preRender` or `serverRender`).

## Lamdera Inspiration

A big thank you to Mario Rogic for Lamdera and Evergreen Migrations. `elm-pages` uses the Lamdera compiler for binary serialization of Elm values, and this local DB uses a pattern inspired by [Lamdera's `Evergreen` migrations](https://dashboard.lamdera.app/docs/evergreen).

## Quick Start

Initialize a `Db.elm` file:

```shell
npx elm-pages db init
```

Example `Db.elm`:

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
```

## `Pages.Db` API

`Pages.Db` exposes:

```elm
type Connection

default : Connection
open : FilePath -> Connection

get : Connection -> BackendTask FatalError Db.Db
update : Connection -> (Db.Db -> Db.Db) -> BackendTask FatalError ()
transaction :
    Connection
    -> (Db.Db -> BackendTask FatalError ( Db.Db, a ))
    -> BackendTask FatalError a
```

Use `Pages.Db.open` when your path comes from CLI options or environment values.
Use `Pages.Db.default` for the default `db.bin` path at the current working directory (where the script is executed).
Migration metadata and generated migration files live in `.elm-pages-db/`.

## Git and `.gitignore`

Recommended:

- Commit `script/src/Db.elm` (or your `Db.elm` location).
- Commit `.elm-pages-db/Db/V*.elm`.
- Commit `.elm-pages-db/Db/Migrate/V*.elm`.
- Commit `.elm-pages-db/MigrateChain.elm`.
- Commit `.elm-pages-db/schema-version.json`.

Usually ignore:

- `db.bin`
- `db.lock`
- `.elm-pages-db/schema-history/` (optional: commit this if you want stale-snapshot recovery shared across machines)

`elm-pages db init` currently creates `Db.elm` only. It does **not** update `.gitignore` for you.

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
