module SequenceHttpLog exposing (run)

import BackendTask
import BackendTask.Http
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "-> 1"
            |> BackendTask.andThen
                (\_ ->
                    Script.log "-> 2"
                        |> BackendTask.andThen
                            (\_ ->
                                Script.log "-> 3"
                                    |> BackendTask.andThen
                                        (\_ ->
                                            BackendTask.Http.getJson
                                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                                (Decode.field "stargazers_count" Decode.int)
                                                |> BackendTask.allowFatal
                                                |> BackendTask.andThen
                                                    (\stars ->
                                                        Script.log (String.fromInt stars)
                                                    )
                                        )
                            )
                )
        )
