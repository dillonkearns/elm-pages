---
description: You can run scripts written in pure Elm with the `elm-pages run` CLI command.
---

# `elm-pages` Scripts

The `elm-pages run` command lets you use [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask)'s to do scripting tasks with Elm. The goal is to make it as simple as possible to write a Script in Elm and run it from the command line. You can use any of the techniques from BackendTask's to read files, make HTTP requests, get environment variables, or async NodeJS functions through [`BackendTask.Custom.run`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Custom#run).

## Quick Start

The [elm-pages starter repo](https://github.com/dillonkearns/elm-pages-starter) comes with a `script/` folder that is setup with an `elm.json` with `elm-pages` as a dependency, but you can also create the `script/` folder from scratch:

```
mkdir script
cd script
elm init
elm install dillonkearns/elm-pages
```

Now we can write our Script Module. Create a file called `script/src/Hello.elm` that exposes a top-level value `run` of type `Script`.

```elm
module Hello exposing (run)

import Pages.Script as Script exposing (Script)

run : Script
run =
    Script.withoutCliOptions
        (Script.log "Hello from elm-pages Scripts!")
```

Now we can run our `Hello.elm` Script Module from the command line:

```shell
npx elm-pages run script/src/Hello.elm
# Hello from elm-pages Scripts!
```

As a shorthand, you can run scripts from the folder `./script/src/` by passing in the Elm module name (without the `.elm` extension) instead of the file path of the module name.

```python
npx elm-pages run Hello
# Hello from elm-pages Scripts!
```

## Script Folder

The `script/` folder is a regular Elm project folder. That means it will need to have an `elm.json` file, and an Elm module in the `src/` folder (or whichever `source-directories` path you define in your `elm.json`). It will also need `elm-pages` installed as a dependency.

If you use [`BackendTask.Custom.run`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Custom#run) from your Script, it will use the `custom-backend-task.ts` (or `.js`) file defined in your `script/` project folder.

The name `script/` is a convention and is not required. You can execute the `elm-pages run` command on any file as long as it is part of an Elm project (in its `source-directories`), and that project has `elm-pages` installed as a dependency.

## Running Scripts from Different Directories

You can pass any absolute or relative path to an `elm-pages` Script module to the `elm-pages run` command. It will find the `elm.json` for the Script module automatically.

```shell
elm-pages run ~/my-projects/elm-pages-scripts/src/Hello.elm
```

## Adding Command Line Options

Scripts can define command line options with a config from [`dillonkearns/elm-cli-options-parser`](https://package.elm-lang.org/packages/dillonkearns/elm-cli-options-parser/latest/).

Here is an example that takes optional keyword arguments `--username` and `--repo`.

```elm
module Stars exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withCliOptions program
        (\{ username, repo } ->
            BackendTask.Http.getJson
                ("https://api.github.com/repos/" ++ username ++ "/" ++ repo)
                (Decode.field "stargazers_count" Decode.int)
                |> BackendTask.andThen
                    (\stars ->
                        Script.log ("🤩" ++ (String.fromInt stars))
                    )
                |> BackendTask.allowFatal
        )


type alias CliOptions =
    { username : String
    , repo : String
    }


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add
            (OptionsParser.build CliOptions
                |> OptionsParser.with
                    (Option.optionalKeywordArg "username"
                        |> Option.withDefault "dillonkearns")
                |> OptionsParser.with
                    (Option.optionalKeywordArg "repo"
                        |> Option.withDefault "elm-pages")
            )
```

Our `Cli.Program.Config` that we defined automatically gives us a `--help` option.

```
npx elm-pages run script/src/Stars.elm --help
# elm-pages run Stars [--username <username>] [--repo <repo>]
```

Now let's run our script with some options.

```shell
npx elm-pages run script/src/Stars.elm --repo elm-graphql
# 🤩 757
```

Now let's try running it with an invalid option.

```shell
run script/src/Stars.elm --user elm --name json

# -- Invalid CLI arguments ---------------
# The `--name` flag was not found. Maybe it was one of these typos?
#
# `--name` <> `--username`
```

## `FatalError`'s

If the `BackendTask` in your script resolves to a [`FatalError`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/FatalError), the script will print the error message and exit with a non-zero exit code. As with any `BackendTask`, if you want to ensure that your script will not encounter a `FatalError`, you can ensure that you have handled every possible error by using a value with the type `BackendTask Never ()`.

## Scaffolding a Route Module

The `elm-pages` package includes some modules that help you generate Elm files.

`elm-pages run` will automatically run `elm-codegen install` for you if you have a `./codegen/` folder next to your `./script/` project.

[`elm-codegen`](https://github.com/mdgriffith/elm-codegen) is a project that helps you write Elm code that generate Elm code. In our case, we are going to generate some scaffolding to help us add new Routes to our `elm-pages` app.

`elm-codegen` helps ensure that you are generating valid code by generating functions that mirror the code they will generate, giving you an extra layer of type safety. `elm-pages` Scripts are general-purpose, so you can do what you want with them, but there are some built-in helpers to make it easy for you to scaffold code for your `elm-pages` app that work well with `elm-codegen`.

Take a look at [the `AddRoute.elm` Script from the `elm-pages` starter repo](https://github.com/dillonkearns/elm-pages-starter/blob/master/script/src/AddRoute.elm). This Script is a great starting point for customizing your own scaffolding Scripts for your project. It is designed to lock in the essential details for defining a Route Module and a Form, while leaving the rest up to you to customize in the script. See [`Scaffold.Route`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Scaffold-Route) and [`Scaffold.Form`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Scaffold-Form) in the docs.

## Compiling Scripts to an Executable JavaScript File

You can compile your script (options parsing and all) to a single minified and optimized JavaScript file that you can run in any NodeJS environment.

```shell
elm-pages bundle-script script/src/Stars.elm
```
