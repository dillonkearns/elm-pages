module StaticResponsesTests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BuildError exposing (BuildError)
import Exception exposing (Throwable)
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (NextStep(..))
import Pages.Internal.StaticHttpBody exposing (Body(..))
import Pages.Script as Script
import Pages.StaticHttp.Request as Request exposing (Request)
import RequestsAndPending exposing (ResponseBody)
import Test exposing (Test, describe, test)


all : Test
all =
    describe "StaticResponses"
        [ test "simple get" <|
            \() ->
                BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Decode.field "stargazers_count" Decode.int)
                    |> BackendTask.throw
                    |> expectRequestChain 123
                        [ [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                            , Encode.object
                                [ ( "stargazers_count", Encode.int 123 )
                                ]
                            )
                          ]
                        ]
        , test "andThen" <|
            \() ->
                BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Decode.field "stargazers_count" Decode.int)
                    |> BackendTask.andThen
                        (\elmPagesStars ->
                            BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-graphql"
                                (Decode.field "stargazers_count" Decode.int)
                                |> BackendTask.map (\graphqlStars -> elmPagesStars + graphqlStars)
                        )
                    |> BackendTask.throw
                    |> expectRequestChain 579
                        [ [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                            , Encode.object
                                [ ( "stargazers_count", Encode.int 123 )
                                ]
                            )
                          ]
                        , [ ( get "https://api.github.com/repos/dillonkearns/elm-graphql"
                            , Encode.object
                                [ ( "stargazers_count", Encode.int 456 )
                                ]
                            )
                          ]
                        ]
        , test "log" <|
            \() ->
                Script.log "Hello!"
                    |> expectRequestChain ()
                        [ [ ( log "Hello!"
                            , Encode.object []
                            )
                          ]
                        ]
        , test "andThen log" <|
            \() ->
                BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Decode.field "stargazers_count" Decode.int)
                    |> BackendTask.throw
                    |> BackendTask.andThen
                        (\stars ->
                            Script.log ("Stars: " ++ String.fromInt stars)
                        )
                    |> expectRequestChain ()
                        [ [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                            , Encode.object
                                [ ( "stargazers_count", Encode.int 123 )
                                ]
                            )
                          ]
                        , [ ( log "Stars: 123"
                            , Encode.object []
                            )
                          ]
                        ]
        ]


log : String -> Request
log message =
    portRequest "log"
        (Encode.object
            [ ( "message", Encode.string message )
            ]
        )


portRequest : String -> Encode.Value -> Request
portRequest portName body =
    { url = "elm-pages-internal://" ++ portName
    , method = "GET"
    , headers = []
    , body = JsonBody body
    , cacheOptions = Nothing
    }


get : String -> Request
get url =
    { url = url
    , method = "GET"
    , headers = []
    , body = EmptyBody
    , cacheOptions = Nothing
    }


expectRequestChain :
    a
    -> List (List ( Request, Encode.Value ))
    -> BackendTask Throwable a
    -> Expect.Expectation
expectRequestChain expectedValue expectedChain request =
    expectRequestChainHelp expectedValue
        (expectedChain |> List.map (List.map Tuple.first))
        (expectedChain
            |> List.map
                (List.map
                    (Tuple.mapFirst
                        (withInternalHeader
                            (RequestsAndPending.JsonBody Encode.null)
                        )
                    )
                )
        )
        []
        request
        (Encode.object [])
        { errors = []
        }


expectRequestChainHelp :
    a
    -> List (List Request)
    -> List (List ( Request, Encode.Value ))
    -> List (List Request)
    -> BackendTask Throwable a
    -> Encode.Value
    ->
        { errors : List BuildError
        }
    -> Expect.Expectation
expectRequestChainHelp expectedValue fullExpectedChain expectedChain chainSoFar backendTask responses values =
    case
        StaticResponses.nextStep responses backendTask values
    of
        Finish actualFinalValue ->
            Expect.all
                [ \() ->
                    chainSoFar
                        |> List.reverse
                        |> List.map (List.map .url)
                        |> Expect.equal (fullExpectedChain |> List.map (List.map .url))
                , \() ->
                    actualFinalValue
                        |> Expect.equal expectedValue
                ]
                ()

        FinishedWithErrors errors ->
            ("Expected no errors, got FinishedWithErrors: \n"
                ++ BuildError.errorsToString errors
            )
                |> Expect.fail

        Continue requests rawRequest ->
            let
                latestActualChainReversed : List (List Request)
                latestActualChainReversed =
                    requests :: chainSoFar
            in
            case expectedChain of
                first :: rest ->
                    let
                        thing : Encode.Value
                        thing =
                            first
                                |> List.map
                                    (\( request, response ) ->
                                        ( Request.hash request
                                        , Encode.object
                                            [ ( "response"
                                              , Encode.object
                                                    [ ( "body", response )
                                                    , ( "bodyKind", Encode.string "json" )
                                                    ]
                                              )
                                            ]
                                        )
                                    )
                                |> Encode.object
                    in
                    expectRequestChainHelp expectedValue
                        fullExpectedChain
                        rest
                        (requests :: chainSoFar)
                        rawRequest
                        thing
                        { errors = [] }

                _ ->
                    -- TODO give error because it's not complete but should be?
                    latestActualChainReversed
                        |> List.reverse
                        |> List.map (List.map .url)
                        |> Expect.equal (fullExpectedChain |> List.map (List.map .url))


withInternalHeader : ResponseBody -> { a | headers : List ( String, String ) } -> { a | headers : List ( String, String ) }
withInternalHeader res req =
    { req
        | headers =
            ( "elm-pages-internal"
            , case res of
                RequestsAndPending.JsonBody _ ->
                    "ExpectJson"

                RequestsAndPending.BytesBody _ ->
                    "ExpectBytes"

                RequestsAndPending.StringBody _ ->
                    "ExpectString"

                RequestsAndPending.WhateverBody ->
                    "ExpectWhatever"
            )
                :: req.headers
    }
