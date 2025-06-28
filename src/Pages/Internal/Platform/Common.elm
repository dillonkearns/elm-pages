module Pages.Internal.Platform.Common exposing (decodeBuildError)

{-| Contains code common to Cli.elm and GeneratorApplication.elm
-}

import BuildError
import Json.Decode as Decode
import TerminalText as Terminal


decodeBuildError : Decode.Value -> BuildError.BuildError
decodeBuildError jsonValue =
    let
        decoder : Decode.Decoder BuildError.BuildError
        decoder =
            Decode.field "tag" Decode.string
                |> Decode.andThen
                    (\tag ->
                        case tag of
                            "BuildError" ->
                                Decode.field "data"
                                    (Decode.map2
                                        (\message title ->
                                            { title = title
                                            , message = message
                                            , fatal = True
                                            , path = "" -- TODO wire in current path here
                                            }
                                        )
                                        (Decode.field "message" Decode.string |> Decode.map Terminal.fromAnsiString)
                                        (Decode.field "title" Decode.string)
                                    )

                            _ ->
                                Decode.fail "Unhandled msg"
                    )
    in
    Decode.decodeValue decoder jsonValue
        |> Result.mapError
            (\error ->
                ("From location 1: "
                    ++ (error
                            |> Decode.errorToString
                       )
                )
                    |> BuildError.internal
            )
        |> mergeResult


mergeResult : Result a a -> a
mergeResult r =
    case r of
        Ok rr ->
            rr

        Err rr ->
            rr
