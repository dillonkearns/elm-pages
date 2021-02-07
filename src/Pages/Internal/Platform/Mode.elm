module Pages.Internal.Platform.Mode exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode
import TsJson.Decode as TsDecode


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


tsModeDecoder : TsDecode.Decoder Mode
tsModeDecoder =
    TsDecode.oneOf
        [ TsDecode.literal Prod (Encode.string "prod")
        , TsDecode.literal ElmToHtmlBeta (Encode.string "elm-to-html-beta")
        , TsDecode.literal Dev (Encode.string "dev")
        ]
