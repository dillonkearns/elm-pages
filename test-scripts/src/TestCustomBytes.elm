module TestCustomBytes exposing (run)

{-| End-to-end smoke test for `BackendTask.Custom.runBytes`.

Encodes a known UTF-8 string to `Bytes`, round-trips it through the JS
`echoBytes` port, decodes back to a String, and asserts equality. Then
does the same with `reverseBytes` and checks the reversal.

Run via:

    (cd test-scripts && npx elm-pages run src/TestCustomBytes.elm)

-}

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import FatalError
import Pages.Script as Script exposing (Script)


run : Script
run =
    (check "echoBytes round-trip" expectedForward echoed
        |> BackendTask.andThen (\_ -> check "reverseBytes" expectedReversed reversed)
        |> BackendTask.andThen (\_ -> Script.log "TestCustomBytes: all round-trips passed ✓")
    )
        |> Script.withoutCliOptions


payload : String
payload =
    "Hello from Elm over Bytes!"


expectedForward : String
expectedForward =
    payload


expectedReversed : String
expectedReversed =
    String.reverse payload


echoed : BackendTask FatalError.FatalError String
echoed =
    BackendTask.Custom.runBytes "echoBytes"
        (encodeString payload)
        (decodeString (utf8ByteLen payload))


reversed : BackendTask FatalError.FatalError String
reversed =
    BackendTask.Custom.runBytes "reverseBytes"
        (encodeString payload)
        (decodeString (utf8ByteLen payload))


encodeString : String -> Bytes
encodeString s =
    Bytes.Encode.encode (Bytes.Encode.string s)


decodeString : Int -> Bytes.Decode.Decoder String
decodeString width =
    Bytes.Decode.string width


utf8ByteLen : String -> Int
utf8ByteLen s =
    -- payload is ASCII so byte length = string length. For non-ASCII payloads,
    -- encode first and use Bytes.width.
    Bytes.Encode.encode (Bytes.Encode.string s) |> Bytes.width


check : String -> String -> BackendTask FatalError.FatalError String -> BackendTask FatalError.FatalError ()
check label expected actual =
    actual
        |> BackendTask.andThen
            (\got ->
                if got == expected then
                    Script.log ("  ✓ " ++ label ++ ": " ++ quoted got)

                else
                    BackendTask.fail
                        (FatalError.fromString
                            ("TestCustomBytes failed: " ++ label ++ "\n  expected: " ++ quoted expected ++ "\n  got     : " ++ quoted got)
                        )
            )


quoted : String -> String
quoted s =
    "\"" ++ s ++ "\""
