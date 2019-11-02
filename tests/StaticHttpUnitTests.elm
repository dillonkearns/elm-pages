module StaticHttpUnitTests exposing (all)

import Dict exposing (Dict)
import Expect
import Json.Decode as Decode
import Pages.Internal.Secrets
import Pages.StaticHttpRequest as StaticHttpRequest
import StaticHttp
import Test exposing (Test, describe, only, test)


all : Test
all =
    describe "Static Http Requests"
        [ test "andThen" <|
            \() ->
                StaticHttp.jsonRequest "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.jsonRequest continueUrl (Decode.succeed ())
                            StaticHttp.jsonRequest "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "first", "null" )
                                    , ( "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Pages.Internal.Secrets.useFakeSecrets)
                                |> Expect.equal ( True, [ "first", "NEXT" ] )
                       )
        , test "andThen staring with done" <|
            \() ->
                StaticHttp.succeed ()
                    |> StaticHttp.andThen
                        (\_ ->
                            StaticHttp.jsonRequest "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Pages.Internal.Secrets.useFakeSecrets)
                                |> Expect.equal ( True, [ "NEXT" ] )
                       )
        , test "map" <|
            \() ->
                StaticHttp.jsonRequest "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.jsonRequest continueUrl (Decode.succeed ())
                            StaticHttp.jsonRequest "NEXT" (Decode.succeed ())
                        )
                    |> StaticHttp.map (\_ -> ())
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "first", "null" )
                                    , ( "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Pages.Internal.Secrets.useFakeSecrets)
                                |> Expect.equal ( True, [ "first", "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 1 pending" <|
            \() ->
                StaticHttp.jsonRequest "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            StaticHttp.jsonRequest "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "first", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Pages.Internal.Secrets.useFakeSecrets)
                                |> Expect.equal ( False, [ "first", "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 2 pending" <|
            \() ->
                StaticHttp.jsonRequest "first" Decode.int
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            StaticHttp.jsonRequest "NEXT" Decode.string
                                |> StaticHttp.andThen
                                    (\_ ->
                                        StaticHttp.jsonRequest "LAST"
                                            Decode.string
                                    )
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList [ ( "first", "1" ) ])
                                |> Tuple.mapSecond (List.map Pages.Internal.Secrets.useFakeSecrets)
                                |> Expect.equal ( False, [ "first", "NEXT" ] )
                       )
        ]
