module RouteTest exposing (..)

import Expect
import FatalError
import Fuzz exposing (Fuzzer)
import Route exposing (Route)
import Test exposing (Test, describe, fuzz, test)
import Url


all : Test
all =
    describe "routes"
        [ test "test 1" <|
            \() ->
                { path = "/cats/larry" }
                    |> Route.urlToRoute
                    |> Expect.equal
                        (Route.Cats__Name__
                            { name = Just "larry" }
                            |> Just
                        )
        , test "catch all route" <|
            \() ->
                { path = "/date/1/2/3" }
                    |> Route.urlToRoute
                    |> Expect.equal
                        (Route.Date__SPLAT_
                            { splat = ( "1", [ "2", "3" ] ) }
                            |> Just
                        )
        , fuzz routeFuzzer "reversible" <|
            \route ->
                let
                    asUrl =
                        route
                            |> Route.routeToPath
                            |> (\path ->
                                    { path = path |> String.join "/" }
                               )

                    asRoute =
                        asUrl
                            |> Route.urlToRoute
                in
                { route = asRoute
                , path = asUrl.path
                }
                    |> Expect.equal
                        { route = Just route
                        , path = asUrl.path
                        }
        ]


routeFuzzer : Fuzzer Route
routeFuzzer =
    Fuzz.oneOf
        [ Fuzz.map
            (\string -> Route.Cats__Name__ { name = Just string })
            nonEmptyUrlEscapedString
        , Fuzz.int
            |> Fuzz.map
                (\number ->
                    Route.Slide__Number_ { number = String.fromInt number }
                )
        , Fuzz.int
            |> Fuzz.map
                (\number ->
                    Route.Date__SPLAT_ { splat = ( String.fromInt number, [] ) }
                )
        , Fuzz.map2
            (\first rest ->
                Route.Date__SPLAT_
                    { splat =
                        ( String.fromInt first
                        , List.map String.fromInt rest
                        )
                    }
            )
            Fuzz.int
            (Fuzz.list Fuzz.int)
        ]


nonEmptyUrlEscapedString : Fuzzer String
nonEmptyUrlEscapedString =
    Fuzz.map2
        (\c string ->
            Url.percentEncode
                (String.fromChar
                    c
                    ++ string
                )
        )
        Fuzz.char
        Fuzz.string
