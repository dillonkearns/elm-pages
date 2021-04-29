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
        , test "file path with multiple segments" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literalSegment "users"
                    |> slash
                    |> captureSegment
                    |> literalSegment ".json"
                    |> tryMatch "users/123.json"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "routes" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literalSegment "users"
                    |> slash
                    |> captureSegment
                    |> literalSegment ".json"
                    |> withRoutes
                        --[ \c -> c "100"
                        [ \c -> "100"
                        ]
                    |> Expect.equal
                        [ "users/100.json"

                        --, "users/101.json"
                        ]
        ]



--withRoutes : a -> b -> List String


withRoutes : List ((b -> String) -> String) -> Handler a b -> List String
withRoutes values (Handler pattern handler toString) =
    --[ "users/100.json", "users/101.json" ]
    values
        |> List.map (\value -> value toString)



--|> List.map (\value -> toString value)


tryMatch : String -> Handler Response b -> Maybe Response
tryMatch path (Handler pattern handler toString) =
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
    = Handler String (List String -> a) (b -> String)


type alias Response =
    { body : String }


succeed : a -> Handler a b
succeed a =
    Handler "" (\args -> a) (\_ -> "")



--handle : (a -> Response) -> Handler a b -> Handler response b
--handle function handler =
--    Debug.todo ""


literalSegment : String -> Handler a b -> Handler a b
literalSegment segment (Handler pattern handler toString) =
    Handler (pattern ++ segment) handler (\arg -> toString arg ++ segment)


slash : Handler a b -> Handler a b
slash (Handler pattern handler toString) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/")


captureSegment : Handler (String -> a) (String -> b) -> Handler a (String -> b)
captureSegment (Handler pattern previousHandler toString) =
    Handler (pattern ++ "(.*)")
        (\matches ->
            case matches of
                first :: rest ->
                    previousHandler rest first

                _ ->
                    Debug.todo "Expected non-empty list"
        )
        --(\string -> \arg -> toString arg)
        (\s -> toString s)


captureRest : Handler (List String -> a) b -> Handler a b
captureRest previousHandler =
    Debug.todo ""
