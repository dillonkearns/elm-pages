module ApiHandlerTests exposing (..)

import Expect
import Regex
import Test exposing (describe, only, test)


all =
    describe "api routes"
        [ test "match top-level file with no extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> captureSegment
                    |> tryMatch "123"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "file with extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> captureSegment
                    |> literalSegment ".json"
                    |> tryMatch "124.json"
                    |> Expect.equal (Just { body = "Data for user 124" })
        ]


tryMatch : String -> Handler Response -> Maybe Response
tryMatch path (Handler pattern handler) =
    let
        matches =
            Regex.find
                (Regex.fromString (pattern |> Debug.log "pattern")
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
        |> captureSegment


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
literalSegment segment (Handler pattern handler) =
    Handler (pattern ++ segment) handler


slash : Handler a -> Handler a
slash handler =
    handler


captureSegment : Handler (String -> a) -> Handler a
captureSegment (Handler pattern previousHandler) =
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
