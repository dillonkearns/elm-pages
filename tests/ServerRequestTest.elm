module ServerRequestTest exposing (all)

import Dict exposing (Dict)
import Expect exposing (Expectation)
import FormData
import Internal.Request exposing (Parser(..))
import Json.Decode as Decode
import Json.Encode
import List.NonEmpty as NonEmpty exposing (NonEmpty)
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
                        , body = Nothing
                        }
        , test "accept GET" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Get, [] )
                    |> expectMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        }
        , test "accept GET doesn't match POST" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Post, [] )
                    |> expectNoMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
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
                        , body = Nothing
                        }
                        """Expected a form POST but this HTTP request has no body."""
        , test "tries multiple form post formats" <|
            \() ->
                Request.oneOf
                    [ Request.oneOf
                        [ Request.expectFormPost
                            (\{ field } ->
                                field "bar"
                            )
                        , Request.expectFormPost
                            (\{ field } ->
                                field "foo"
                            )
                        ]
                    ]
                    |> expectMatch
                        { method = Request.Post
                        , headers =
                            [ ( "content-type", "application/x-www-form-urlencoded" )
                            ]
                        , body =
                            Just
                                (FormData
                                    (Dict.fromList [ ( "foo", NonEmpty.singleton "bar" ) ])
                                )
                        }
        , test "one of no match" <|
            \() ->
                Request.oneOf
                    [ Request.expectFormPost
                        (\{ field } ->
                            field "first"
                        )
                    , Request.expectJsonBody (Decode.field "first" Decode.string)
                    , Request.expectQueryParam "first"
                    , Request.expectMultiPartFormPost
                        (\{ field } ->
                            field "first"
                        )
                    ]
                    |> expectNoMatch
                        { method = Request.Get
                        , headers =
                            [ ( "content-type", "application/x-www-form-urlencoded" )
                            ]
                        , body = Nothing
                        }
                        """Server.Request.oneOf failed in the following 4 ways:

(1) Expected a form POST but this HTTP request has no body.

(2) Expected content-type to be application/json but it was application/x-www-form-urlencoded

(3) Internal error - expected rawUrl field but the adapter script didn't provide one.

(4) Expected content-type to be multipart/form-data but it was application/x-www-form-urlencoded
Expected HTTP method POST but was GET"""
        ]


type alias Request =
    { method : Request.Method
    , headers : List ( String, String )
    , body : Maybe Body
    }


type Body
    = FormData (Dict String (NonEmpty String))
    | JsonBody Decode.Value
    | StringBody String


expectMatch : Request -> Request.Parser value -> Expectation
expectMatch request (Parser decoder) =
    case
        request
            |> requestToJson
            |> Decode.decodeValue decoder
    of
        Ok ok ->
            case ok of
                ( Ok _, [] ) ->
                    Expect.pass

                ( Err innerError, otherErrors ) ->
                    (innerError :: otherErrors)
                        |> List.map Request.errorToString
                        |> String.join "\n"
                        |> Expect.fail

                ( Ok _, nonEmptyErrors ) ->
                    nonEmptyErrors
                        |> List.map Request.errorToString
                        |> String.join "\n"
                        |> Expect.fail

        Err error ->
            Expect.fail (Decode.errorToString error)


expectNoMatch : Request -> String -> Request.Parser value -> Expectation
expectNoMatch request expectedErrorString (Parser decoder) =
    case
        request
            |> requestToJson
            |> Decode.decodeValue decoder
    of
        Ok ok ->
            case ok of
                ( Ok _, [] ) ->
                    Expect.fail "Expected this request not to match, but instead it did match."

                ( Err innerError, otherErrors ) ->
                    (innerError :: otherErrors)
                        |> List.map Request.errorToString
                        |> String.join "\n"
                        |> Expect.equal expectedErrorString

                ( Ok _, nonEmptyErrors ) ->
                    nonEmptyErrors
                        |> List.map Request.errorToString
                        |> String.join "\n"
                        |> Expect.equal expectedErrorString

        Err error ->
            Expect.fail
                ("Expected this request to not match, but instead there was an internal error: "
                    ++ Decode.errorToString error
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
        , ( "body"
          , request.body
                |> Maybe.map encodeBody
                |> Maybe.withDefault Json.Encode.null
          )
        , ( "query", Json.Encode.null )
        , ( "multiPartFormData", Json.Encode.null )
        ]


encodeBody : Body -> Decode.Value
encodeBody body =
    case body of
        JsonBody json ->
            json

        FormData formData ->
            formData |> FormData.encode |> Json.Encode.string

        StringBody string ->
            string |> Json.Encode.string
