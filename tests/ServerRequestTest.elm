module ServerRequestTest exposing (all)

import Expect exposing (Expectation)
import Json.Decode
import Json.Encode
import OptimizedDecoder
import Server.Request as Request
import Test exposing (Test, describe, only, test)


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
                        , formData = Nothing
                        }
        , test "accept GET" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Get, [] )
                    |> expectMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        , formData = Nothing
                        }
        , test "accept GET doesn't match POST" <|
            \() ->
                Request.succeed ()
                    |> Request.acceptMethod ( Request.Post, [] )
                    |> expectNoMatch
                        { method = Request.Get
                        , headers = []
                        , body = Nothing
                        , formData = Nothing
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
                        , formData = Nothing
                        }
                        """Did not match formPost because
- Form post must have method POST, but the method was GET
- Forms must have Content-Type application/x-www-form-urlencoded, but the Content-Type was TODO"""
        , test "one of no match" <|
            \() ->
                Request.oneOf
                    [ Request.expectFormPost
                        (\{ field, optionalField } ->
                            field "first"
                        )
                    , Request.expectJsonBody (OptimizedDecoder.field "first" OptimizedDecoder.string)
                    , Request.expectQueryParam "first"
                    , Request.expectMultiPartFormPost
                        (\{ field, optionalField } ->
                            field "first"
                        )
                    ]
                    |> expectNoMatch
                        { method = Request.Get
                        , headers =
                            [ ( "content-type", "application/x-www-form-urlencoded" )
                            ]
                        , body = Nothing
                        , formData = Nothing
                        }
                        """Server.Request.oneOf failed in the following 4 ways:

(1) Did not match formPost because
- Form post must have method POST, but the method was GET
- Forms must have Content-Type application/x-www-form-urlencoded, but the Content-Type was TODO

(2) Unable to parse JSON body
Problem with the given value:

null

Expecting an OBJECT with a field named `first`

(3) Missing query param "first"

(4) Missing form field first
Expected content-type to be multipart/form-data but it was application/x-www-form-urlencoded
Expected HTTP method POST but was GET"""
        ]


type alias Request =
    { method : Request.Method
    , headers : List ( String, String )
    , body : Maybe String
    , formData : Maybe (List ( String, String ))
    }


expectMatch : Request -> Request.Request value -> Expectation
expectMatch request (Request.Request decoder) =
    case
        request
            |> requestToJson
            |> OptimizedDecoder.decodeValue decoder
    of
        Ok ok ->
            case ok of
                ( Ok inner, [] ) ->
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
            Expect.fail (Json.Decode.errorToString error)


expectNoMatch : Request -> String -> Request.Request value -> Expectation
expectNoMatch request expectedErrorString (Request.Request decoder) =
    case
        request
            |> requestToJson
            |> OptimizedDecoder.decodeValue decoder
    of
        Ok ok ->
            case ok of
                ( Ok inner, [] ) ->
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
        , ( "formData"
          , request.formData
                |> Maybe.map
                    (\fields ->
                        fields
                            |> List.map (Tuple.mapSecond Json.Encode.string)
                            |> Json.Encode.object
                    )
                |> Maybe.withDefault Json.Encode.null
          )
        , ( "jsonBody", Json.Encode.null )
        , ( "query", Json.Encode.null )
        , ( "multiPartFormData", Json.Encode.null )
        ]
