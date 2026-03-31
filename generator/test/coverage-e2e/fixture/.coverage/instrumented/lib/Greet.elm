module Greet exposing (Greeting(..), formalGreet, greet)

{-| A simple module with branches for coverage testing.
-}

import Coverage


type Greeting
    = Hello
    | Goodbye
    | Custom String


greet : Greeting -> String
greet greeting =
    let
        _ =
            Coverage.track "Greet" 3
    in
    case greeting of
        Hello ->
            let
                _ =
                    Coverage.track "Greet" 0
            in
            "Hello, world!"

        Goodbye ->
            let
                _ =
                    Coverage.track "Greet" 1
            in
            "Goodbye, world!"

        Custom message ->
            let
                _ =
                    Coverage.track "Greet" 2
            in
            message


{-| This function is never called by the test script.
-}
formalGreet : String -> String
formalGreet name =
    let
        _ =
            Coverage.track "Greet" 4
    in
    "Dear " ++ name ++ ", greetings."
