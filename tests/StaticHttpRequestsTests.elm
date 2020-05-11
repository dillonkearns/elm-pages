module StaticHttpRequestsTests exposing (all)

import Codec
import Dict exposing (Dict)
import Expect
import Html
import Json.Decode as JD
import Json.Decode.Exploration
import Json.Encode as Encode
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.ContentCache as ContentCache
import Pages.Document as Document
import Pages.Http
import Pages.ImagePath as ImagePath
import Pages.Internal.Platform.Cli as Main exposing (..)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttp.Request as Request
import PagesHttp
import ProgramTest exposing (ProgramTest)
import Regex
import Secrets
import SimulatedEffect.Cmd
import SimulatedEffect.Http as Http
import SimulatedEffect.Ports
import Test exposing (Test, describe, only, test)
import Test.Http


all : Test
all =
    describe "Static Http Requests"
        [ test "initial requests are sent out" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "andThen" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.succeed ())
                            |> StaticHttp.andThen
                                (\continueUrl ->
                                    StaticHttp.get (Secrets.succeed "NEXT-REQUEST") (Decode.succeed ())
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """null"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "NEXT-REQUEST"
                        """null"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """null"""
                              )
                            , ( get "NEXT-REQUEST"
                              , """null"""
                              )
                            ]
                          )
                        ]
        , test "andThen chain avoids repeat requests" <|
            \() ->
                let
                    getReq url decoder =
                        StaticHttp.request
                            (Secrets.succeed (get url))
                            decoder

                    pokemonDetailRequest : StaticHttp.Request ()
                    pokemonDetailRequest =
                        getReq
                            "https://pokeapi.co/api/v2/pokemon/"
                            (Decode.list
                                (Decode.field "url" Decode.string
                                    |> Decode.map
                                        (\url ->
                                            getReq url
                                                (Decode.field "image" Decode.string)
                                        )
                                )
                            )
                            |> StaticHttp.resolve
                            |> StaticHttp.map (\_ -> ())
                in
                start
                    [ ( [ "elm-pages" ], pokemonDetailRequest )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://pokeapi.co/api/v2/pokemon/"
                        """[
                            {"url": "url1"},
                            {"url": "url2"},
                            {"url": "url3"},
                            {"url": "url4"},
                            {"url": "url5"},
                            {"url": "url6"},
                            {"url": "url7"},
                            {"url": "url8"},
                            {"url": "url9"},
                            {"url": "url10"}
                            ]"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url1"
                        """{"image": "image1.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url2"
                        """{"image": "image2.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url3"
                        """{"image": "image3.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url4"
                        """{"image": "image4.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url5"
                        """{"image": "image5.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url6"
                        """{"image": "image6.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url7"
                        """{"image": "image7.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url8"
                        """{"image": "image8.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url9"
                        """{"image": "image9.jpg"}"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "url10"
                        """{"image": "image10.jpg"}"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://pokeapi.co/api/v2/pokemon/"
                              , """[{"url":"url1"},{"url":"url2"},{"url":"url3"},{"url":"url4"},{"url":"url5"},{"url":"url6"},{"url":"url7"},{"url":"url8"},{"url":"url9"},{"url":"url10"}]"""
                              )
                            , ( get "url1"
                              , """{"image":"image1.jpg"}"""
                              )
                            , ( get "url2"
                              , """{"image":"image2.jpg"}"""
                              )
                            , ( get "url3"
                              , """{"image":"image3.jpg"}"""
                              )
                            , ( get "url4"
                              , """{"image":"image4.jpg"}"""
                              )
                            , ( get "url5"
                              , """{"image":"image5.jpg"}"""
                              )
                            , ( get "url6"
                              , """{"image":"image6.jpg"}"""
                              )
                            , ( get "url7"
                              , """{"image":"image7.jpg"}"""
                              )
                            , ( get "url8"
                              , """{"image":"image8.jpg"}"""
                              )
                            , ( get "url9"
                              , """{"image":"image9.jpg"}"""
                              )
                            , ( get "url10"
                              , """{"image":"image10.jpg"}"""
                              )
                            ]
                          )
                        ]
        , test "port is sent out once all requests are finished" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                      )
                    , ( [ "elm-pages-starter" ]
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") starDecoder
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 22 }"""
                    |> expectSuccess
                        [ ( "elm-pages"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        , ( "elm-pages-starter"
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":22}"""
                              )
                            ]
                          )
                        ]
        , test "reduced JSON is sent out" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "you can use elm/json decoders with StaticHttp.unoptimizedRequest" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , method = "GET"
                                , headers = []
                                , body = StaticHttp.emptyBody
                                }
                            )
                            (StaticHttp.expectUnoptimizedJson
                                (JD.field "stargazer_count" JD.int)
                            )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{ "stargazer_count": 86, "unused_field": 123 }"""
                              )
                            ]
                          )
                        ]
        , test "plain string" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://example.com/file.txt"
                                , method = "GET"
                                , headers = []
                                , body = StaticHttp.emptyBody
                                }
                            )
                            (StaticHttp.expectString Ok)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://example.com/file.txt"
                        "This is a raw text file."
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://example.com/file.txt"
                              , "This is a raw text file."
                              )
                            ]
                          )
                        ]
        , test "Err in String to Result function turns into decode error" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.unoptimizedRequest
                            (Secrets.succeed
                                { url = "https://example.com/file.txt"
                                , method = "GET"
                                , headers = []
                                , body = StaticHttp.emptyBody
                                }
                            )
                            (StaticHttp.expectString
                                (\string ->
                                    if String.toUpper string == string then
                                        Ok string

                                    else
                                        Err "String was not uppercased"
                                )
                            )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://example.com/file.txt"
                        "This is a raw text file."
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (expectErrorsPort
                            """-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages



String was not uppercased"""
                        )
        , test "POST method works" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.request
                            (Secrets.succeed
                                { method = "POST"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , headers = []
                                , body = StaticHttp.emptyBody
                                }
                            )
                            (Decode.field "stargazer_count" Decode.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "POST"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( { method = "POST"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages"
                                , headers = []
                                , body = StaticHttp.emptyBody
                                }
                              , """{"stargazer_count":86}"""
                              )
                            ]
                          )
                        ]
        , test "json is reduced from andThen chains" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int)
                            |> StaticHttp.andThen
                                (\continueUrl ->
                                    StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") (Decode.field "stargazer_count" Decode.int)
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 100, "unused_field": 123 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 50, "unused_field": 456 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":100}"""
                              )
                            , ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":50}"""
                              )
                            ]
                          )
                        ]
        , test "reduced json is preserved by StaticHttp.map2" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.map2 (\_ _ -> ())
                            (StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.field "stargazer_count" Decode.int))
                            (StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") (Decode.field "stargazer_count" Decode.int))
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 100, "unused_field": 123 }"""
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                        """{ "stargazer_count": 50, "unused_field": 456 }"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                              , """{"stargazer_count":100}"""
                              )
                            , ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                              , """{"stargazer_count":50}"""
                              )
                            ]
                          )
                        ]
        , test "the port sends out even if there are no http requests" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.succeed ()
                      )
                    ]
                    |> expectSuccess [ ( "", [] ) ]
        , test "the port sends out when there are duplicate http requests for the same page" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.map2 (\_ _ -> ())
                            (StaticHttp.get (Secrets.succeed "http://example.com") (Decode.succeed ()))
                            (StaticHttp.get (Secrets.succeed "http://example.com") (Decode.succeed ()))
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "http://example.com"
                        """null"""
                    |> expectSuccess
                        [ ( ""
                          , [ ( get "http://example.com"
                              , """null"""
                              )
                            ]
                          )
                        ]
        , test "an error is sent out for decoder failures" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.fail "The user should get this message from the CLI.")
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (expectErrorsPort
                            """-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages

elm-pages

I encountered some errors while decoding this JSON:

  The user should get this message from the CLI.

    {
      "stargazer_count": 86
    }"""
                        )
        , test "an error is sent for missing secrets from continuation requests" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get
                            (Secrets.succeed
                                (\apiKey ->
                                    "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                )
                                |> Secrets.with "API_KEY"
                            )
                            Decode.string
                            |> StaticHttp.andThen
                                (\url ->
                                    StaticHttp.get
                                        (Secrets.succeed
                                            (\missingSecret ->
                                                url ++ "?apiKey=" ++ missingSecret
                                            )
                                            |> Secrets.with "MISSING"
                                        )
                                        (Decode.succeed ())
                                )
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        """ "continuation-url" """
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (expectErrorsPort
                            """-- MISSING SECRET ----------------------------------------------------- elm-pages

I expected to find this Secret in your environment variables but didn't find a match:

Secrets.get "MISSING"
             ^^^^^^^

So maybe MISSING should be API_KEY"""
                        )
        , test "an error is sent for HTTP errors" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.simulateHttpResponse
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Test.Http.httpResponse
                            { statusCode = 404
                            , headers = []
                            , body = ""
                            }
                        )
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (expectErrorsPort """-- STATIC HTTP ERROR ----------------------------------------------------- elm-pages

I got an error making an HTTP request to this URL: https://api.github.com/repos/dillonkearns/elm-pages

Bad status: 404
Status message: TODO: if you need this, please report to https://github.com/avh4/elm-program-test/issues
Body: """)
        , test "uses real secrets to perform request and masked secrets to store and lookup response" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.request
                            (Secrets.succeed
                                (\apiKey bearer ->
                                    { url = "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                    , method = "GET"
                                    , headers = [ ( "Authorization", "Bearer " ++ bearer ) ]
                                    , body = StaticHttp.emptyBody
                                    }
                                )
                                |> Secrets.with "API_KEY"
                                |> Secrets.with "BEARER"
                            )
                            (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.ensureHttpRequest "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        (\request ->
                            request.headers
                                |> Expect.equal [ ( "Authorization", "Bearer XYZ789" ) ]
                        )
                    |> ProgramTest.simulateHttpResponse
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        (Test.Http.httpResponse
                            { statusCode = 200
                            , headers = []
                            , body = """{ "stargazer_count": 86 }"""
                            }
                        )
                    |> expectSuccess
                        [ ( ""
                          , [ ( { method = "GET"
                                , url = "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=<API_KEY>"
                                , headers =
                                    [ ( "Authorization", "Bearer <BEARER>" )
                                    ]
                                , body = StaticHttp.emptyBody
                                }
                              , """{}"""
                              )
                            ]
                          )
                        ]
        , describe "staticHttpCache"
            [ test "it doesn't perform http requests that are provided in the http cache flag" <|
                \() ->
                    startWithHttpCache
                        [ ( { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":86}"""
                          )
                        ]
                        [ ( []
                          , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                          )
                        ]
                        |> expectSuccess
                            [ ( ""
                              , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                                  , """{"stargazer_count":86}"""
                                  )
                                ]
                              )
                            ]
            , test "it ignores unused cache" <|
                \() ->
                    startWithHttpCache
                        [ ( { url = "https://this-is-never-used.example.com/"
                            , method = "GET"
                            , headers = []
                            , body = StaticHttpBody.EmptyBody
                            }
                          , """{"stargazer_count":86}"""
                          )
                        ]
                        [ ( []
                          , StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
                          )
                        ]
                        |> ProgramTest.simulateHttpOk
                            "GET"
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            """{ "stargazer_count": 86 }"""
                        |> expectSuccess
                            [ ( ""
                              , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                                  , """{"stargazer_count":86}"""
                                  )
                                ]
                              )
                            ]
            ]
        ]


start : List ( List String, StaticHttp.Request a ) -> ProgramTest Main.Model Main.Msg (Main.Effect PathKey)
start pages =
    startWithHttpCache [] pages


startWithHttpCache : List ( Request.Request, String ) -> List ( List String, StaticHttp.Request a ) -> ProgramTest Main.Model Main.Msg (Main.Effect PathKey)
startWithHttpCache staticHttpCache pages =
    let
        document =
            Document.fromList
                [ Document.parser
                    { extension = "md"
                    , metadata = JD.succeed ()
                    , body = \_ -> Ok ()
                    }
                ]

        content =
            pages
                |> List.map
                    (\( path, _ ) ->
                        ( path, { extension = "md", frontMatter = "null", body = Just "" } )
                    )

        contentCache =
            ContentCache.init document content Nothing

        siteMetadata =
            contentCache
                |> Result.map
                    (\cache -> cache |> ContentCache.extractMetadata PathKey)
                |> Result.mapError (List.map Tuple.second)

        config =
            { toJsPort = toJsPort
            , fromJsPort = fromJsPort
            , manifest = manifest
            , generateFiles = \_ -> StaticHttp.succeed []
            , init = \_ -> ( (), Cmd.none )
            , update = \_ _ -> ( (), Cmd.none )
            , view =
                \allFrontmatter page ->
                    let
                        thing =
                            pages
                                |> Dict.fromList
                                |> Dict.get
                                    (page.path
                                        |> PagePath.toString
                                        |> String.split "/"
                                        |> List.filter (\pathPart -> pathPart /= "")
                                    )
                    in
                    case thing of
                        Just request ->
                            request
                                |> StaticHttp.map
                                    (\staticData -> { view = \model viewForPage -> { title = "Title", body = Html.text "" }, head = [] })

                        Nothing ->
                            Debug.todo "Couldn't find page"
            , subscriptions = \_ -> Sub.none
            , document = document
            , content = []
            , canonicalSiteUrl = ""
            , pathKey = PathKey
            , onPageChange = \_ -> ()
            }

        encodedFlags =
            --{"secrets":
            --        {"API_KEY": "ABCD1234","BEARER": "XYZ789"}, "mode": "prod", "staticHttpCache": {}
            --        }
            Encode.object
                [ ( "secrets"
                  , [ ( "API_KEY", "ABCD1234" )
                    , ( "BEARER", "XYZ789" )
                    ]
                        |> Dict.fromList
                        |> Encode.dict identity Encode.string
                  )
                , ( "mode", Encode.string "prod" )
                , ( "staticHttpCache", encodedStaticHttpCache )
                ]

        encodedStaticHttpCache =
            staticHttpCache
                |> List.map
                    (\( request, httpResponseString ) ->
                        ( Request.hash request, Encode.string httpResponseString )
                    )
                |> Encode.object
    in
    {-
       (Model -> model)
       -> ContentCache.ContentCache metadata view
       -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
       -> Config pathKey userMsg userModel metadata view
       -> Decode.Value
       -> ( model, Effect pathKey )
    -}
    ProgramTest.createDocument
        { init = Main.init identity contentCache siteMetadata config
        , update = Main.update siteMetadata config
        , view = \_ -> { title = "", body = [] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start (flags (Encode.encode 0 encodedFlags))


flags : String -> JD.Value
flags jsonString =
    case JD.decodeString JD.value jsonString of
        Ok value ->
            value

        Err _ ->
            Debug.todo "Invalid JSON value."


simulateEffects : Main.Effect PathKey -> ProgramTest.SimulatedEffect Main.Msg
simulateEffects effect =
    case effect of
        NoEffect ->
            SimulatedEffect.Cmd.none

        SendJsData value ->
            SimulatedEffect.Ports.send "toJsPort" (value |> Codec.encoder Main.toJsCodec)

        --            toJsPort value |> Cmd.map never
        Batch list ->
            list
                |> List.map simulateEffects
                |> SimulatedEffect.Cmd.batch

        FetchHttp ({ unmasked, masked } as requests) ->
            Http.request
                { method = unmasked.method
                , url = unmasked.url
                , headers = unmasked.headers |> List.map (\( key, value ) -> Http.header key value)
                , body =
                    case unmasked.body of
                        StaticHttpBody.EmptyBody ->
                            Http.emptyBody

                        StaticHttpBody.StringBody contentType string ->
                            Http.stringBody contentType string

                        StaticHttpBody.JsonBody value ->
                            Http.jsonBody value
                , expect =
                    PagesHttp.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { request = requests
                                , response = response
                                }
                        )
                , timeout = Nothing
                , tracker = Nothing
                }


expectErrorsPort : String -> List (ToJsPayload pathKey) -> Expect.Expectation
expectErrorsPort expectedPlainString actualPorts =
    case actualPorts of
        [ Errors actualRichTerminalString ] ->
            actualRichTerminalString
                |> normalizeErrorExpectEqual expectedPlainString

        _ ->
            Expect.fail <| "Expected single error port. Got\n" ++ String.join "\n\n" (List.map Debug.toString actualPorts)


expectNonfatalErrorsPort : String -> List (ToJsPayload pathKey) -> Expect.Expectation
expectNonfatalErrorsPort expectedPlainString actualPorts =
    case actualPorts of
        [ Success successPayload ] ->
            successPayload.errors
                |> String.join "\n\n"
                |> normalizeErrorExpectEqual expectedPlainString

        _ ->
            Expect.fail <| "Expected single non-fatal error port. Got\n" ++ String.join "\n\n" (List.map Debug.toString actualPorts)


normalizeErrorExpectEqual : String -> String -> Expect.Expectation
normalizeErrorExpectEqual expectedPlainString actualRichTerminalString =
    actualRichTerminalString
        |> Regex.replace
            (Regex.fromString "\u{001B}\\[[0-9;]+m"
                |> Maybe.withDefault Regex.never
            )
            (\_ -> "")
        |> Expect.equal expectedPlainString


toJsPort foo =
    Cmd.none


fromJsPort =
    Sub.none


type PathKey
    = PathKey


manifest : Manifest.Config PathKey
manifest =
    { backgroundColor = Nothing
    , categories = []
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Nothing
    , startUrl = PagePath.external ""
    , shortName = Just "elm-pages"
    , sourceIcon = ImagePath.external ""
    }


starDecoder =
    Decode.field "stargazer_count" Decode.int


thingy =
    [ ( ""
      , [ ( { method = "GET"
            , url = "https://api.github.com/repos/dillonkearns/elm-pages"
            , headers = []
            }
          , """{"stargazer_count":86}"""
          )
        ]
      )
    ]



--type alias Request =
--    { method : String
--    , url : String
--    , headers : List String
--    }


expectSuccess : List ( String, List ( Request.Request, String ) ) -> ProgramTest model msg effect -> Expect.Expectation
expectSuccess expectedRequests previous =
    previous
        |> ProgramTest.expectOutgoingPortValues
            "toJsPort"
            (Codec.decoder Main.toJsCodec)
            (\value ->
                case value of
                    [ Main.Success portPayload ] ->
                        portPayload.pages
                            |> Expect.equal
                                (expectedRequests
                                    |> List.map
                                        (\( url, requests ) ->
                                            ( url
                                            , requests
                                                |> List.map
                                                    (\( request, response ) ->
                                                        ( Request.hash request, response )
                                                    )
                                                |> Dict.fromList
                                            )
                                        )
                                    |> Dict.fromList
                                )

                    [ _ ] ->
                        Expect.fail "Expected success port."

                    _ ->
                        Expect.fail ("Expected ports to be called once, but instead there were " ++ String.fromInt (List.length value) ++ " calls.")
            )


get : String -> Request.Request
get url =
    { method = "GET"
    , url = url
    , headers = []
    , body = StaticHttp.emptyBody
    }
