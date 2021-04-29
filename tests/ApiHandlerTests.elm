module ApiHandlerTests exposing (..)

import Expect
import Regex
import Test exposing (describe, only, test)


all =
    describe "api routes"
        [ --test "match top-level file with no extension" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            |> captureSegment
          --            |> tryMatch "123"
          --            |> Expect.equal (Just { body = "Data for user 123" })
          --, test "file with extension" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            |> captureSegment
          --            |> literalSegment ".json"
          --            |> tryMatch "124.json"
          --            |> Expect.equal (Just { body = "Data for user 124" })
          --, test "file path with multiple segments" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            |> literalSegment "users"
          --            |> slash
          --            |> captureSegment
          --            |> literalSegment ".json"
          --            |> tryMatch "users/123.json"
          --            |> Expect.equal (Just { body = "Data for user 123" }),
          test "routes" <|
            \() ->
                routesExample
                    |> withRoutes
                    --[ \c -> c "100"
                    |> Expect.equal
                        [ "users/100.json" ]

        --, "users/101.json"
        ]


routesExample : Handler Response (List (List String))
routesExample =
    succeed
        (\userId ->
            { body = "Data for user " ++ userId }
        )
        (\constructor ->
            [ constructor "100" ]
        )
        |> literalSegment "users"
        |> slash
        |> captureSegment
        |> literalSegment ".json"


withRoutes : Handler Response (List (List String)) -> List String
withRoutes (Handler pattern handler toString dynamicSegments) =
    --[ "users/100.json", "users/101.json" ]
    --values
    --    |> List.map
    --        (\value ->
    --            value
    --                |> dynamicSegments
    --                |> toString
    --        )
    dynamicSegments
        --|> Debug.log "dynamicSegments"
        |> List.map toString



--|> List.map (\value -> toString value)


tryMatch : String -> Handler Response b -> Maybe Response
tryMatch path (Handler pattern handler toString dynamicSegments) =
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



--exampleHandler : Handler Response
--exampleHandler =
--    succeed
--        (\userId ->
--            { body = "Data for user " ++ userId }
--        )
--        |> captureSegment


type Handler a b
    = Handler String (List String -> a) (List String -> String) b


type alias Response =
    { body : String }


succeed : a -> ((b -> List String) -> List (List String)) -> Handler a ((b -> List String) -> List (List String))
succeed a buildTimePaths =
    Handler "" (\args -> a) (\_ -> "") buildTimePaths



--handle : (a -> Response) -> Handler a b -> Handler response b
--handle function handler =
--    Debug.todo ""


literalSegment : String -> Handler a b -> Handler a b
literalSegment segment (Handler pattern handler toString dynamicSegments) =
    Handler (pattern ++ segment) handler (\values -> toString values ++ segment) dynamicSegments


slash : Handler a b -> Handler a b
slash (Handler pattern handler toString dynamicSegments) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/") dynamicSegments


captureSegment : Handler (String -> a) ((String -> List String) -> List (List String)) -> Handler a (List (List String))
captureSegment (Handler pattern previousHandler toString dynamicSegments) =
    Handler (pattern ++ "(.*)")
        (\matches ->
            case matches of
                first :: rest ->
                    previousHandler rest first

                _ ->
                    Debug.todo "Expected non-empty list"
        )
        (\s ->
            case s of
                first :: rest ->
                    toString s ++ first

                _ ->
                    ""
        )
        (dynamicSegments (\string -> [ string ]))


captureRest : Handler (List String -> a) b -> Handler a b
captureRest previousHandler =
    Debug.todo ""
