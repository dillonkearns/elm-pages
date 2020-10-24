module Pages.Internal.Platform.Mode exposing (..)

import Json.Decode as Decode


type Mode
    = Prod
    | Dev
    | ElmToHtmlBeta


modeDecoder =
    Decode.string
        |> Decode.andThen
            (\mode ->
                if mode == "prod" then
                    Decode.succeed Prod

                else if mode == "elm-to-html-beta" then
                    Decode.succeed ElmToHtmlBeta

                else
                    Decode.succeed Dev
            )
