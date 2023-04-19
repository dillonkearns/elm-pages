module ServerRequestTest exposing (all)

import Dict exposing (Dict)
import Expect exposing (Expectation)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import FormData
import Internal.Request exposing (Parser(..))
import Json.Decode as Decode
import Json.Encode
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
                        , urlQueryString = Nothing
                        }
        , test "accept GET" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Get, [] )
                    |> expectMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        , urlQueryString = Nothing
                        }
        , test "accept GET doesn't match POST" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Post, [] )
                    |> expectNoMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        , urlQueryString = Nothing
                        }
                        "Expected HTTP method POST but was GET"
        , test "formData extracts fields from query params for GET" <|
            \() ->
                Request.rawFormData
                    |> Request.map
                        (\formData ->
                            formData
                        )
                    |> expectMatchWith
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        , urlQueryString = Just "q=hello"
                        }
                        [ ( "q", "hello" ) ]
        , test "tries multiple form post formats" <|
            \() ->
                Request.formData
                    (Form.form
                        (\bar ->
                            { combine =
                                Validation.succeed identity
                                    |> Validation.andMap bar
                            , view =
                                \_ -> ()
                            }
                        )
                        |> Form.field "bar" Field.text
                        |> Form.Handler.init identity
                        |> Form.Handler.with identity
                            (Form.form
                                (\bar ->
                                    { combine =
                                        Validation.succeed identity
                                            |> Validation.andMap bar
                                    , view =
                                        \_ -> ()
                                    }
                                )
                                |> Form.field "foo" Field.text
                            )
                    )
                    |> expectMatch
                        { method = Request.Post
                        , headers =
                            [ ( "content-type", "application/x-www-form-urlencoded" )
                            ]
                        , body =
                            Just
                                (FormData
                                    (Dict.fromList [ ( "foo", ( "bar", [] ) ) ])
                                )
                        , urlQueryString = Nothing
                        }
        , test "expectFormPost with missing content-type" <|
            \() ->
                Request.formData
                    (Form.form
                        (\bar ->
                            { combine =
                                Validation.succeed identity
                                    |> Validation.andMap bar
                            , view =
                                \_ -> ()
                            }
                        )
                        |> Form.field "bar" Field.text
                        |> Form.Handler.init identity
                    )
                    |> expectNoMatch
                        { method = Request.Post
                        , headers =
                            [ ( "content_type", "application/x-www-form-urlencoded" )
                            ]
                        , body =
                            Just
                                (FormData
                                    (Dict.fromList [ ( "foo", ( "bar", [] ) ) ])
                                )
                        , urlQueryString = Nothing
                        }
                        """expectFormPost did not match - Was form POST but expected content-type `application/x-www-form-urlencoded` but the request didn't have a content-type header"""

        --        , test "one of no match" <|
        --            \() ->
        --                Request.oneOf
        --                    [ --Request.formParserResultNew
        --                      --   [ Form.init
        --                      --       (\bar ->
        --                      --           Validation.succeed identity
        --                      --               |> Validation.andMap bar
        --                      --       )
        --                      --       (\_ _ -> ())
        --                      --       |> Form.field "first" Field.text
        --                      --   ],
        --                      Request.expectJsonBody (Decode.field "first" Decode.string)
        --                    , Request.expectQueryParam "first"
        --                    , Request.expectMultiPartFormPost
        --                        (\{ field } ->
        --                            field "first"
        --                        )
        --                    ]
        --                    |> expectNoMatch
        --                        { method = Request.Get
        --                        , headers =
        --                            [ ( "content-type", "application/x-www-form-urlencoded" )
        --                            ]
        --                        , body = Nothing
        --                        }
        --                        """Server.Request.oneOf failed in the following 4 ways:
        --
        --(1) expectFormPost did not match - expected method POST, but the method was GET
        --
        --(2) Expected content-type to be application/json but it was application/x-www-form-urlencoded
        --
        --(3) Internal error - expected rawUrl field but the adapter script didn't provide one.
        --
        --(4) Expected content-type to be multipart/form-data but it was application/x-www-form-urlencoded
        --Expected HTTP method POST but was GET"""
        ]


type alias Request =
    { method : Request.Method
    , headers : List ( String, String )
    , body : Maybe Body
    , urlQueryString : Maybe String
    }


type Body
    = FormData (Dict String ( String, List String ))
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


expectMatchWith : Request -> value -> Request.Parser value -> Expectation
expectMatchWith request expected (Parser decoder) =
    case
        request
            |> requestToJson
            |> Decode.decodeValue decoder
    of
        Ok ok ->
            case ok of
                ( Ok actual, [] ) ->
                    actual
                        |> Expect.equal expected

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
        , ( "query"
          , Json.Encode.object
                [ ( "q", Json.Encode.string "hello" )
                ]
          )
        , ( "rawUrl"
          , Json.Encode.string
                ("http://localhost:1234/"
                    ++ (request.urlQueryString |> Maybe.map (\q -> "?" ++ q) |> Maybe.withDefault "")
                )
          )
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
