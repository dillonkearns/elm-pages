module ApiHandlerTests exposing (..)

import Expect
import Regex
import Test exposing (describe, test)


all =
    describe "api routes"
        [ test "match top-level file" <|
            \() ->
                exampleHandler
                    |> tryMatch "123"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "match top-level file 2" <|
            \() ->
                exampleHandler
                    |> tryMatch "124"
                    |> Expect.equal (Just { body = "Data for user 124" })
        ]


tryMatch : String -> Handler Response -> Maybe Response
tryMatch path (Handler pattern handler) =
    let
        matches =
            Regex.find
                (Regex.fromString pattern
                    |> Maybe.withDefault Regex.never
                )
                path
                |> List.concatMap .submatches
                |> List.filterMap identity
    in
    handler matches
        |> Just


exampleHandler : Handler Response
exampleHandler =
    succeed
        (\userId ->
            { body = "Data for user " ++ userId }
        )
        |> literalSegment "rss.xml"
        |> slash
        --|> literalSegment ""
        |> captureSegment ""


type Handler a
    = Handler String (List String -> a)


type alias Response =
    { body : String }


succeed : a -> Handler a
succeed a =
    Handler "(.*)" (\args -> a)


handle : (a -> Response) -> Handler a -> Handler response
handle function handler =
    Debug.todo ""


literalSegment : String -> Handler a -> Handler a
literalSegment segment handler =
    handler


slash : Handler a -> Handler a
slash handler =
    handler


captureSegment : String -> Handler (String -> a) -> Handler a
captureSegment string (Handler pattern previousHandler) =
    (\matches ->
        case matches of
            first :: rest ->
                previousHandler rest first

            _ ->
                Debug.todo "Expected non-empty list"
    )
        |> Handler pattern


captureRest : Handler (List String -> a) -> Handler a
captureRest previousHandler =
    Debug.todo ""
