module SequenceHttpLog exposing (run)

import DataSource
import DataSource.Http
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "-> 1"
            |> DataSource.andThen
                (\_ ->
                    Script.log "-> 2"
                        |> DataSource.andThen
                            (\_ ->
                                Script.log "-> 3"
                                    |> DataSource.andThen
                                        (\_ ->
                                            DataSource.Http.get
                                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                                (Decode.field "stargazers_count" Decode.int)
                                                |> DataSource.andThen
                                                    (\stars ->
                                                        Script.log (String.fromInt stars)
                                                    )
                                        )
                            )
                )
        )
