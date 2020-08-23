module Pages.Internal.Platform.Mode exposing (..)

import Json.Decode as Decode


type Mode
    = Prod
    | Dev


modeDecoder =
    Decode.string
        |> Decode.andThen
            (\mode ->
                if mode == "prod" then
                    Decode.succeed Prod

                else
                    Decode.succeed Dev
            )
