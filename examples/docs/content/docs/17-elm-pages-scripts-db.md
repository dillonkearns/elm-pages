---
description: Use a local type-safe database in elm-pages scripts with type-safe migrations.
---

# Local Type-Safe DB in `elm-pages` Scripts

`elm-pages` Scripts can read and write to **an Elm type** directly to a local database file using a `BackendTask`.

Think of it like `SQLite`, but with Elm types and type-safe migrations between versions of that Elm type.

```elm
module Db exposing (Db)

type alias Db =
    { todos : List { title : String, done : Bool }
    }
```

This database API is **script-only**. Use it from `elm-pages run`, or CLIs that you bundle with `elm-pages bundle-script` (not from Route module, i.e. `preRender` or `serverRender`).

## Prerequisites

This feature requires the [Lamdera compiler](https://dashboard.lamdera.app/docs/download) (`lamdera` must be on your `PATH`). `elm-pages` uses Lamdera's binary serialization to read and write your Elm types without any hand-written encoders or decoders. You can add Lamdera to your package.json by running `npm install --save-dev lamdera@latest`.

## Lamdera Inspiration

A big thank you to Mario Rogic for Lamdera and Evergreen Migrations. `elm-pages` uses the Lamdera compiler for binary serialization of Elm values, and this local DB uses a pattern inspired by [Lamdera's `Evergreen` migrations](https://dashboard.lamdera.app/docs/evergreen).

## Key Concepts

- **`Db.elm`** -- You define your database schema as a plain Elm type alias. When you want to change the schema, you change this file. The V1 seed (initial value for fresh installs) lives in `db/Db/Migrate/V1.elm`.
- **`Connection`** -- An opaque type that points to a database file on disk. Create one with `Pages.Db.default` (uses `./db.bin`) or `Pages.Db.open` (custom path).
- **Migrations** -- When you change `Db.elm`, you also write a type-safe migration function (`Db.V1.Db -> Db.Db`) in `db/Db/Migrate/V*.elm` so existing data is transformed to the new schema. Other generated files in `db/` are scaffolding you generally don't need to think about.

## Quick Start

Initialize the `Db.elm` file to create the scaffolding where you define the Elm type that you will be persisting in your database:

```shell
npx elm-pages db init
```

Modifying our `Db.elm` module with a simple counter app type:

```elm
module Db exposing (Db)


type alias Db =
    { count : Int }
```

The `db init` command also creates `db/Db/Migrate/V1.elm` with a `seed` function that provides the initial value for fresh installs.

## `Pages.Db` API

`Pages.Db` exposes:

```elm
-- The DB file this script will read/write from/to
type Connection

-- Uses ./db.bin in the current working directory (typically your project root)
default : Connection

-- Choose a custom path for the DB file (relative to your project root)
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

## Directory Structure

```text
.
├── script/
│   └── src/
│       ├── Db.elm          # current schema (type only)
│       └── Counter.elm     # script that reads/writes DB
├── db/
│   └── Db/
│       └── Migrate/
│           ├── V1.elm      # seed: () -> Db.Db
│           ├── V2.elm      # migration: V1 -> V2
│           └── V3.elm      # migration: V2 -> V3
├── db.bin                  # default DB file (`Pages.Db.default`)
└── .elm-pages-data/
    └── counter.db.bin      # custom DB file (`Pages.Db.open`)
```

Internal/transient files omitted (for example `db/Db/V*.elm` snapshots, `db.bin.lock`, `db/schema-history/`).

## Git and `.gitignore`

Recommended:

- Commit `script/src/Db.elm` (or your `Db.elm` location).
- Commit `db/Db/V*.elm` (generated snapshots; usually not edited directly).
- Commit `db/Db/Migrate/V*.elm`.

Usually ignore (added to `.gitignore` automatically by `elm-pages db init`):

- `db.bin`
- `db.bin.lock`
- `db.bin.backup`
- `db/schema-history/` (remove this line from `.gitignore` if you want stale-snapshot recovery shared across machines)

## Example: Run a Migration (V1 -> V2)

Start from the V1 schema shown above (`{ count : Int }`), and run your script once so `db.bin` exists:

```shell
npx elm-pages run script/src/Counter.elm
```

Now change `Db.elm` to V2:

```elm
module Db exposing (Db)


type alias Db =
    { count : Int
    , step : Int
    }
```

Generate migration files:

```shell
npx elm-pages db migrate
```

```text
Created migration V1 -> V2:
  Snapshot: db/Db/V1.elm
  Stub:     db/Db/Migrate/V2.elm
```

Implement `db/Db/Migrate/V2.elm`:

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

-- used for fresh installs that start from `() |> V1.seed |> V2.seed |> ...`
seed : Db.VN.Db -> Db.Db
```

V1 is special: `seed : () -> Db.Db` takes unit since there is no previous version. V2+ take the previous version's `Db` type.

Generated stubs default `seed old = migrate old`, which is the right choice most of the time. You only need a different `seed` when fresh installs should start with different data than what existing users get after migration.

For example, suppose V1 had no `theme` field and V2 adds one. Existing users migrating from V1 should keep the old default (`"classic"`), but new users starting fresh should get the newer default (`"modern"`):

```elm
migrate : Db.V1.Db -> Db.Db
migrate old =
    { count = old.count
    , theme = "classic"  -- safe default for existing data
    }

seed : Db.V1.Db -> Db.Db
seed old =
    { count = old.count
    , theme = "modern"  -- better default for fresh installs
    }
```

If you don't need this distinction, just leave `seed old = migrate old`.

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

# Start fresh (delete the default local DB)
rm -f db.bin db.bin.lock db.bin.backup
```

## Troubleshooting

### "db.bin schema mismatch"

Your `Db.elm` type has changed since `db.bin` was last written. You need a migration:

1. Run `npx elm-pages db migrate` to scaffold migration files.
2. Implement the migration in `db/Db/Migrate/V*.elm`.
3. Run `npx elm-pages db migrate` again to apply it.

### "Detected stale Db.elm state" during `db migrate`

This happens when `Db.elm` was edited before the old schema was captured as a snapshot. If `db/schema-history/` has the old source, `elm-pages` will auto-recover automatically. Otherwise:

- **Preferred:** Restore `Db.elm` to the old schema (e.g. via `git stash` or `git checkout`), run `elm-pages db migrate` to create the snapshot, then re-apply your changes.
- **Escape hatch:** `npx elm-pages db migrate --force-stale-snapshot` -- only use this if you're sure the current `Db.elm` before your changes is the correct old schema.

### Lock file is stuck / "database is locked"

Lock files (`db.bin.lock`) automatically expire after 5 minutes if the process that created them is no longer running. If you're sure no other script is using the database, you can safely delete the lock file:

```shell
rm -f db.bin.lock
```

### `db.bin` seems corrupt or can't be decoded

Delete `db.bin` and let it be re-created from the seed chain (`() |> V1.seed |> V2.seed |> ...`):

```shell
rm -f db.bin db.bin.lock
```

If you had a backup: `cp db.bin.backup db.bin`

### `lamdera` not found

The local DB feature requires the Lamdera compiler for binary serialization. [Download it here](https://dashboard.lamdera.app/docs/download) and make sure `lamdera` is on your `PATH`.
