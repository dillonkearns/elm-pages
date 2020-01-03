module StaticHttpUnitTests exposing (all)

import Dict exposing (Dict)
import Expect
import Json.Decode.Exploration as Decode
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import Test exposing (Test, describe, only, test)


getWithoutSecrets url =
    StaticHttp.get (Secrets.succeed url)


requestsDict requestMap =
    requestMap
        |> List.map
            (\( request, response ) ->
                ( request |> Request.hash
                , response
                )
            )
        |> Dict.fromList


get : String -> Request.Request
get url =
    { method = "GET"
    , url = url
    , headers = []
    , body = Nothing
    }


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
                                (requestsDict
                                    [ ( get "first", "null" )
                                    , ( get "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ getReq "first", getReq "NEXT" ] )
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
                                (requestsDict
                                    [ ( get "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ getReq "NEXT" ] )
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
                                (requestsDict
                                    [ ( get "first", "null" )
                                    , ( get "NEXT", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( True, [ getReq "first", getReq "NEXT" ] )
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
                                (requestsDict
                                    [ ( get "first", "null" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( False, [ getReq "first", getReq "NEXT" ] )
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
                                (requestsDict
                                    [ ( get "first", "1" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( False, [ getReq "first", getReq "NEXT" ] )
                       )
        ]


getReq url =
    { url = url
    , method = "GET"
    , headers = []
    , body = Nothing
    }
