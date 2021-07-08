module RouteTests exposing (all)

import Expect
import List.Extra
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
        , test "multiple matchers" <|
            \() ->
                "/slide/123"
                    |> firstMatch exampleMatchers
                    |> Expect.equal (Slide__Number_ { number = "123" } |> Just)
        , test "hardcoded routes have precedence over dynamic segments" <|
            \() ->
                "/post/create"
                    |> firstMatch postPrecedenceExample
                    |> Expect.equal (Post__Create {} |> Just)
        , test "dynamic segments match when they are not overshadowed by a hardcoded route" <|
            \() ->
                "/post/update"
                    |> firstMatch postPrecedenceExample
                    |> Expect.equal (Post__Slug_ { slug = "update" } |> Just)
        ]


exampleMatchers : List (Matcher Route)
exampleMatchers =
    [ { pattern = "^cats(?:\\/([^/]+))?$"
      , toRoute =
            \matches ->
                case matches of
                    [ name ] ->
                        Cats__Name__ { name = name } |> Just

                    _ ->
                        Nothing
      }
    , { pattern = "^slide\\/(?:([^/]+))$"
      , toRoute =
            \matches ->
                case matches of
                    [ Just number ] ->
                        Slide__Number_ { number = number } |> Just

                    _ ->
                        Nothing
      }
    ]


postPrecedenceExample : List (Matcher Route)
postPrecedenceExample =
    [ { pattern = "^post\\/create$"
      , toRoute =
            \_ ->
                Just (Post__Create {})
      }
    , { pattern = "^post\\/(?:([^/]+))$"
      , toRoute =
            \matches ->
                case matches of
                    [ Just slug ] ->
                        Post__Slug_ { slug = slug } |> Just

                    _ ->
                        Nothing
      }
    ]


firstMatch : List (Matcher Route) -> String -> Maybe Route
firstMatch matchers path =
    List.Extra.findMap
        (\matcher ->
            if Regex.contains (matcher.pattern |> toRegex) (normalizePath path) then
                tryMatch matcher path

            else
                Nothing
        )
        matchers


toRegex : String -> Regex.Regex
toRegex pattern =
    Regex.fromString pattern
        |> Maybe.withDefault Regex.never


type alias Matcher route =
    { pattern : String, toRoute : List (Maybe String) -> Maybe route }


tryMatch : { pattern : String, toRoute : List (Maybe String) -> Maybe Route } -> String -> Maybe Route
tryMatch { pattern, toRoute } path =
    path
        |> normalizePath
        |> submatches pattern
        |> toRoute


submatches : String -> String -> List (Maybe String)
submatches pattern path =
    Regex.find
        (Regex.fromString pattern
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
    | Post__Create {}
    | Post__Slug_ { slug : String }
