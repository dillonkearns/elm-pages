module Greet exposing (Greeting(..), greet, classify, formalGreet)

{-| Module with varied patterns for coverage testing.

Exercises: case branches, if/else, let-bindings, lambdas, multi-line
expressions, and an uncalled function.

-}


type Greeting
    = Hello
    | Goodbye
    | Custom String


greet : Greeting -> String
greet greeting =
    case greeting of
        Hello ->
            "Hello, world!"

        Goodbye ->
            "Goodbye, world!"

        Custom message ->
            message


{-| Classifies a greeting using if/else and let-bindings.
-}
classify : Greeting -> String
classify greeting =
    let
        label =
            greet greeting
    in
    if String.length label > 20 then
        "long"

    else
        "short"


{-| This function is never called by the test script.
-}
formalGreet : String -> String
formalGreet name =
    let
        title =
            "Dear " ++ name
    in
    title ++ ", greetings."
