module Internal.Request exposing (Parser(..))

import Json.Decode


type Parser decodesTo validationError
    = Parser (Json.Decode.Decoder ( Result validationError decodesTo, List validationError ))
