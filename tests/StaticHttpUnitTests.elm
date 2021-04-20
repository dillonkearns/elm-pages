module StaticHttpUnitTests exposing (all)

import DataSource
import Dict
import Expect
import OptimizedDecoder as Decode
import Pages.Internal.ApplicationType as ApplicationType
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets
import Test exposing (Test, describe, test)


getWithoutSecrets url =
    DataSource.get (Secrets.succeed url)


requestsDict requestMap =
    requestMap
        |> List.map
            (\( request, response ) ->
                ( request |> Request.hash
                , Just response
                )
            )
        |> Dict.fromList


get : String -> Request.Request
get url =
    { method = "GET"
    , url = url
    , headers = []
    , body = DataSource.emptyBody
    }


all : Test
all =
    describe "Static Http Requests unit tests"
        [ test "andThen" <|
            \() ->
                DataSource.get (Secrets.succeed "first") (Decode.succeed "NEXT")
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls ApplicationType.Cli
                                request
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
                DataSource.succeed ()
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls ApplicationType.Cli
                                request
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
                    |> DataSource.andThen
                        (\_ ->
                            --                                        StaticHttp.get continueUrl (Decode.succeed ())
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> DataSource.map (\_ -> ())
                    |> (\request ->
                            StaticHttpRequest.resolveUrls ApplicationType.Cli
                                request
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
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls ApplicationType.Cli
                                request
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
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" Decode.string
                                |> DataSource.andThen
                                    (\_ ->
                                        getWithoutSecrets "LAST"
                                            Decode.string
                                    )
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls ApplicationType.Cli
                                request
                                (requestsDict
                                    [ ( get "first", "1" )
                                    ]
                                )
                                |> Tuple.mapSecond (List.map Secrets.maskedLookup)
                                |> Expect.equal ( False, [ getReq "first", getReq "NEXT" ] )
                       )
        ]


getReq : String -> DataSource.RequestDetails
getReq url =
    { url = url
    , method = "GET"
    , headers = []
    , body = DataSource.emptyBody
    }
