module Cloudinary exposing (..)

import MimeType
import Pages.ImagePath as ImagePath exposing (ImagePath)


url :
    String
    -> Maybe MimeType.MimeImage
    -> Int
    -> ImagePath pathKey
url asset format width =
    let
        base =
            "https://res.cloudinary.com/dillonkearns/image/upload"

        fetch_format =
            case format of
                Just MimeType.Png ->
                    "png"

                Just (MimeType.OtherImage "webp") ->
                    "webp"

                Just _ ->
                    "auto"

                Nothing ->
                    "auto"

        transforms =
            [ "c_pad"
            , "w_" ++ String.fromInt width
            , "h_" ++ String.fromInt width
            , "q_auto"
            , "f_" ++ fetch_format
            ]
                |> String.join ","
    in
    ImagePath.external (base ++ "/" ++ transforms ++ "/" ++ asset)
