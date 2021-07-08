module Pages.Internal.Platform.Mode exposing (Mode(..), modeDecoder)

import Json.Decode as Decode exposing (Decoder)


type Mode
    = Prod
    | Dev
    | ElmToHtmlBeta


modeDecoder : Decoder Mode
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
