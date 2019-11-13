module StaticHttpUnitTests exposing (all)

import Dict exposing (Dict)
import Expect
import Json.Decode.Exploration as Decode
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import StaticHttp
import Test exposing (Test, describe, only, test)


getWithoutSecrets url =
    StaticHttp.get (Secrets.succeed url)


all : Test
all =
    describe "Static Http Requests"
        [ test "andThen" <|
            \() ->
                StaticHttp.get (Secrets.succeed "first") (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.get continueUrl (Decode.succeed ())
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    , ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ get "first", get "NEXT" ] )
                       )
        , test "andThen staring with done" <|
            \() ->
                StaticHttp.succeed ()
                    |> StaticHttp.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ get "NEXT" ] )
                       )
        , test "map" <|
            \() ->
                getWithoutSecrets "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            --                                        StaticHttp.get continueUrl (Decode.succeed ())
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> StaticHttp.map (\_ -> ())
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    , ( "[GET]NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ get "first", get "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 1 pending" <|
            \() ->
                getWithoutSecrets "first" (Decode.succeed "NEXT")
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList
                                    [ ( "[GET]first", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( False, [ get "first", get "NEXT" ] )
                       )
        , test "andThen chain with 1 response available and 2 pending" <|
            \() ->
                getWithoutSecrets "first" Decode.int
                    |> StaticHttp.andThen
                        (\continueUrl ->
                            getWithoutSecrets "NEXT" Decode.string
                                |> StaticHttp.andThen
                                    (\_ ->
                                        getWithoutSecrets "LAST"
                                            Decode.string
                                    )
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls request
                                (Dict.fromList [ ( "[GET]first", "1" ) ])
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( False, [ get "first", get "NEXT" ] )
                       )
        ]


get url =
    { url = url, method = "GET", headers = [] }
