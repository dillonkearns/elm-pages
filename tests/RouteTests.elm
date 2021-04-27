module RouteTests exposing (..)

import Expect
import Regex
import Test exposing (Test, describe, test)


all : Test
all =
    describe "routes"
        [ test "test 1" <|
            \() ->
                "/cats/larry"
                    |> tryMatch
                        { pattern = "^cats(?:\\/([^/]+))?$"
                        , toRoute =
                            \matches ->
                                case matches of
                                    [ name ] ->
                                        Cats__Name__ { name = name } |> Just

                                    _ ->
                                        Nothing
                        }
                    |> Expect.equal (Cats__Name__ { name = Just "larry" } |> Just)
        , test "test 2" <|
            \() ->
                "/cats"
                    |> tryMatch
                        { pattern = "^cats(?:\\/([^/]+))?$"
                        , toRoute =
                            \matches ->
                                case matches of
                                    [ name ] ->
                                        Cats__Name__ { name = name } |> Just

                                    _ ->
                                        Nothing
                        }
                    |> Expect.equal (Cats__Name__ { name = Nothing } |> Just)
        ]


tryMatch : { pattern : String, toRoute : List (Maybe String) -> Maybe Route } -> String -> Maybe Route
tryMatch { pattern, toRoute } path =
    path
        |> normalizePath
        |> submatches "^cats(?:\\/([^/]+))?$"
        |> toRoute


submatches : String -> String -> List (Maybe String)
submatches pattern path =
    Regex.find
        (Regex.fromString
            "^cats(?:\\/([^/]+))?$"
            |> Maybe.withDefault Regex.never
        )
        path
        |> List.concatMap .submatches


normalizePath : String -> String
normalizePath path =
    path
        |> stripLeadingSlash
        |> stripTrailingSlash


stripLeadingSlash : String -> String
stripLeadingSlash path =
    if path |> String.startsWith "/" then
        String.dropLeft 1 path

    else
        path


stripTrailingSlash : String -> String
stripTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path


type Route
    = Slide {}
    | Cats__Name__ { name : Maybe String }
    | Slide__Number_ { number : String }
