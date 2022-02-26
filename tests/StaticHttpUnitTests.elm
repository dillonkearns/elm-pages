module StaticHttpUnitTests exposing (all)

import DataSource
import DataSource.Http
import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest as StaticHttpRequest
import RequestsAndPending
import Test exposing (Test, describe, test)


getWithoutSecrets : String -> Decode.Decoder a -> DataSource.DataSource a
getWithoutSecrets url =
    DataSource.Http.get url


requestsDict : List ( Request.Request, b ) -> Dict.Dict String (Maybe b)
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

    -- TODO try to abstract away hardcoding of elm-pages-internal in test code
    , headers = [ ( "elm-pages-internal", "ExpectJson" ) ]
    , body = DataSource.Http.emptyBody
    }


all : Test
all =
    describe "Static Http Requests unit tests"
        [ test "andThen" <|
            \() ->
                DataSource.Http.get "first" (Decode.succeed "NEXT")
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls
                                request
                                (requestsDict
                                    [ ( get "first", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    , ( get "NEXT", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    ]
                                )
                                |> Expect.equal [ getReq "first", getReq "NEXT" ]
                       )
        , test "andThen staring with done" <|
            \() ->
                DataSource.succeed ()
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls
                                request
                                (requestsDict
                                    [ ( get "NEXT", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    ]
                                )
                                |> Expect.equal [ getReq "NEXT" ]
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
                            StaticHttpRequest.resolveUrls
                                request
                                (requestsDict
                                    [ ( get "first", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    , ( get "NEXT", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    ]
                                )
                                |> Expect.equal [ getReq "first", getReq "NEXT" ]
                       )
        , test "andThen chain with 1 response available and 1 pending" <|
            \() ->
                getWithoutSecrets "first" (Decode.succeed "NEXT")
                    |> DataSource.andThen
                        (\_ ->
                            getWithoutSecrets "NEXT" (Decode.succeed ())
                        )
                    |> (\request ->
                            StaticHttpRequest.resolveUrls
                                request
                                (requestsDict
                                    [ ( get "first", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody Encode.null) )
                                    ]
                                )
                                |> Expect.equal [ getReq "first", getReq "NEXT" ]
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
                            StaticHttpRequest.resolveUrls
                                request
                                (requestsDict
                                    [ ( get "first", RequestsAndPending.Response Nothing (RequestsAndPending.JsonBody (Encode.int 1)) )
                                    ]
                                )
                                |> Expect.equal [ getReq "first", getReq "NEXT" ]
                       )
        ]


getReq : String -> DataSource.Http.RequestDetails
getReq url =
    { url = url
    , method = "GET"

    -- TODO try to abstract away hardcoding of elm-pages-internal in test code
    , headers = [ ( "elm-pages-internal", "ExpectJson" ) ]
    , body = DataSource.Http.emptyBody
    }
