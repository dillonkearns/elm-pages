module Pages.FrontmatterDecoder exposing (FrontmatterDecoder, decodeList, decoder, resolve)

import Json.Decode as Decode exposing (Decoder)


type FrontmatterDecoder a
    = FrontmatterDecoder (List Decode.Value -> Decoder a)

parse : List String -> FrontmatterDecoder a -> Result String a
parse (FrontmatterDecoder rawDecoder) =
    Decode.decodeString rawDecoder

decoder : Decoder a -> FrontmatterDecoder a
decoder rawDecoder =
    FrontmatterDecoder (\values -> rawDecoder)


resolve : (List a -> Decoder b) -> FrontmatterDecoder a -> FrontmatterDecoder b
resolve resolveFn (FrontmatterDecoder rawDecoder) =
    (\values ->
        let
            listDecoder : Decoder (List a)
            listDecoder =
                decodeList values (rawDecoder values)
        in
        listDecoder
            |> Decode.andThen
                (\list ->
                    resolveFn list
                )
    )
        |> FrontmatterDecoder


decodeList : List Decode.Value -> Decoder a -> Decoder (List a)
decodeList values rawDecoder =
    List.foldl
        (\value soFar ->
            soFar
                |> Decode.andThen
                    (\list ->
                        case Decode.decodeValue rawDecoder value of
                            Ok decoded ->
                                Decode.succeed (decoded :: list)

                            Err error ->
                                Decode.fail "TODO error message"
                    )
        )
        (Decode.succeed [])
        values
