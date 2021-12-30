module ServerRequestTest exposing (all)

import Expect exposing (Expectation)
import Json.Decode
import Json.Encode
import OptimizedDecoder
import Server.Request as Request
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Server.Request matching"
        [ test "succeed always matches" <|
            \() ->
                Request.succeed ()
                    |> expectMatch
                        { method = Request.Get
                        , headers = []
                        }
        , test "accept GET" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Get, [] )
                    |> expectMatch
                        { method = Request.Get
                        , headers = []
                        }
        , test "accept GET doesn't match POST" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Post, [] )
                    |> expectNoMatch
                        { method = Request.Get
                        , headers = []
                        }
                        "Expected HTTP method POST but was GET"
        , test "unexpected method for form POST" <|
            \() ->
                Request.expectFormPost
                    (\_ ->
                        Request.succeed ()
                    )
                    |> expectNoMatch
                        { method = Request.Get
                        , headers =
                            [ ( "content-type", "application/x-www-form-urlencoded" )
                            ]
                        }
                        "Expected HTTP method POST but was GET"
        ]


type alias Request =
    { method : Request.Method
    , headers : List ( String, String )
    }


expectMatch : Request -> Request.ServerRequest value -> Expectation
expectMatch request (Request.ServerRequest decoder) =
    case
        request
            |> requestToJson
            |> OptimizedDecoder.decodeValue decoder
    of
        Ok ok ->
            case ok of
                Ok inner ->
                    Expect.pass

                Err innerError ->
                    Expect.fail (Request.errorToString innerError)

        Err error ->
            Expect.fail (Json.Decode.errorToString error)


expectNoMatch : Request -> String -> Request.ServerRequest value -> Expectation
expectNoMatch request expectedErrorString (Request.ServerRequest decoder) =
    case
        request
            |> requestToJson
            |> OptimizedDecoder.decodeValue decoder
    of
        Ok ok ->
            case ok of
                Ok _ ->
                    Expect.fail "Expected this request not to match, but instead it did match."

                Err innerError ->
                    innerError
                        |> Request.errorToString
                        |> Expect.equal
                            expectedErrorString

        Err error ->
            Expect.fail
                ("Expected this request to not match, but instead there was an internal error: "
                    ++ Json.Decode.errorToString error
                )


requestToJson : Request -> Json.Encode.Value
requestToJson request =
    Json.Encode.object
        [ ( "method"
          , request.method
                |> Request.methodToString
                |> Json.Encode.string
          )
        , ( "headers"
          , Json.Encode.object
                (List.map
                    (Tuple.mapSecond
                        Json.Encode.string
                    )
                    request.headers
                )
          )
        ]
