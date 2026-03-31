module Greet exposing (Greeting(..), greet, formalGreet)

{-| A simple module with branches for coverage testing.
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


{-| This function is never called by the test script.
-}
formalGreet : String -> String
formalGreet name =
    "Dear " ++ name ++ ", greetings."
