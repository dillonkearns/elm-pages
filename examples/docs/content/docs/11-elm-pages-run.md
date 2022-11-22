# The `elm-pages run` CLI command

`elm-pages` provides this command to help you scaffold new code. The starter template includes a codegen module for scaffolding new Route Modules. However, you can use it to build your own custom generators to scaffold any kind of Elm code you can think of! Indeed, you're not even limited to generating Elm code (or generating code at all). The `elm-pages run` command really just takes an Elm module [Elm `worker` application](https://package.elm-lang.org/packages/elm/core/latest/Platform#worker) and runs it.

## Executing an `elm-pages` Script

If you have a file called `codegen/Hello.elm`

```elm
module Hello exposing (main)


main : Program () () msg
main =
    Platform.worker
        { subscriptions = \_ -> Sub.none
        , update = \_ _ -> ( (), Cmd.none )
        , init =
            \_ ->
                let
                    _ =
                        Debug.log "Greeting" "Hello from Elm!
                in
                ( (), Cmd.none )
        }
```

`elm-pages` will compile and run this Elm `worker` app when we execute this from the command line:

```
npx elm-pages codegen Hello
Greeting: "Hello from Elm!"
```

The command uses [`elm-codegen`](https://github.com/mdgriffith/elm-codegen), which is both a command line tool and an Elm package to help you generate Elm code.

##
