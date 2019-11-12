module StaticHttpUnitTests exposing (all)

import Dict exposing (Dict)
import Expect
import Json.Decode as Decode
import Pages.Internal.Secrets
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets2
import StaticHttp
import Test exposing (Test, describe, only, test)


all : Test
all =
    describe "Static Http Requests"
        [ test "andThen" <|
            \() ->
                StaticHttp.get "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.get continueUrl (Decode.succeed ())
                            StaticHttp.get "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    , ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets2.maskedLookup)
                                |> Expect.equal ( True, [ get "first", get "NEXT" ] )
                       )
        , test "andThen staring with done" <|
            \() ->
                StaticHttp.succeed ()
                    |> StaticHttp.andThen
                        (\_ ->
                            StaticHttp.get "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets2.maskedLookup)
                                |> Expect.equal ( True, [ get "NEXT" ] )
                       )
        , test "map" <|
            \() ->
                StaticHttp.get "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.get continueUrl (Decode.succeed ())
                            StaticHttp.get "NEXT" (Decode.succeed ())
                        )
                    |> StaticHttp.map (\_ -> ())
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    , ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets2.maskedLookup)
                                |> Expect.equal ( True, [ get "first", get "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 1 pending" <|
            \() ->
                StaticHttp.get "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            StaticHttp.get "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets2.maskedLookup)
                                |> Expect.equal ( False, [ get "first", get "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 2 pending" <|
            \() ->
                StaticHttp.get "first" Decode.int
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            StaticHttp.get "NEXT" Decode.string
                                |> StaticHttp.andThen
                                    (\_ ->
                                        StaticHttp.get "LAST"
                                            Decode.string
                                    )
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList [ ( "[GET]first", "1" ) ])
                                |> Tuple.mapSecond (List.map Secrets2.maskedLookup)
                                |> Expect.equal ( False, [ get "first", get "NEXT" ] )
                       )
        ]


get url =
    { url = url, method = "GET", headers = [] }
