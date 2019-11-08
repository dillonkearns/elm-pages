module StaticHttpRequestsTests exposing (all)

import Codec
import Dict exposing (Dict)
import Expect
import Html
import Json.Decode as Decode
import Json.Decode.Exploration as Reduce
import Pages.ContentCache as ContentCache
import Pages.Document as Document
import Pages.ImagePath as ImagePath
import Pages.Internal.Platform.Cli as Main exposing (..)
import Pages.Internal.Secrets
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import ProgramTest exposing (ProgramTest)
import Regex
import Secrets exposing (Secrets)
import SimulatedEffect.Cmd
import SimulatedEffect.Http as Http
import SimulatedEffect.Ports
import StaticHttp
import TerminalText as Terminal
import Test exposing (Test, describe, only, test)
import Test.Http


all : Test
all =
    describe "Static Http Requests"
        [ test "initial requests are sent out" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{ "stargazer_count": 86 }"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "andThen" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
                            |> StaticHttp.andThen
                                (\continueUrl ->
                                    StaticHttp.get "NEXT-REQUEST" (Decode.succeed ())
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
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/elm-pages"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """null"""
                                                  )
                                                , ( "[GET]NEXT-REQUEST"
                                                  , """null"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "port is sent out once all requests are finished" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
                      )
                    , ( [ "elm-pages-starter" ]
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages-starter" (Decode.succeed ())
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
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/elm-pages"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{ "stargazer_count": 86 }"""
                                                  )
                                                ]
                                          )
                                        , ( "/elm-pages-starter"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages-starter"
                                                  , """{ "stargazer_count": 22 }"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "reduced JSON is sent out" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.reducedGet "https://api.github.com/repos/dillonkearns/elm-pages" (Reduce.field "stargazer_count" Reduce.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{"stargazer_count":86}"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "POST method works" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.reducedPost "https://api.github.com/repos/dillonkearns/elm-pages" (Reduce.field "stargazer_count" Reduce.int)
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "POST"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86, "unused_field": 123 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[POST]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{"stargazer_count":86}"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "json is reduced from andThen chains" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.reducedGet "https://api.github.com/repos/dillonkearns/elm-pages" (Reduce.field "stargazer_count" Reduce.int)
                            |> StaticHttp.andThen
                                (\continueUrl ->
                                    StaticHttp.reducedGet "https://api.github.com/repos/dillonkearns/elm-pages-starter" (Reduce.field "stargazer_count" Reduce.int)
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
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{"stargazer_count":100}"""
                                                  )
                                                , ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages-starter"
                                                  , """{"stargazer_count":50}"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "reduced json is preserved by StaticHttp.map2" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.map2 (\_ _ -> ())
                            (StaticHttp.reducedGet "https://api.github.com/repos/dillonkearns/elm-pages" (Reduce.field "stargazer_count" Reduce.int))
                            (StaticHttp.reducedGet "https://api.github.com/repos/dillonkearns/elm-pages-starter" (Reduce.field "stargazer_count" Reduce.int))
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
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{"stargazer_count":100}"""
                                                  )
                                                , ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages-starter"
                                                  , """{"stargazer_count":50}"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "the port sends out even if there are no http requests" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.succeed ()
                      )
                    ]
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList []
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "the port sends out when there are duplicate http requests for the same page" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.map2 (\_ _ -> ())
                            (StaticHttp.get "http://example.com" (Decode.succeed ()))
                            (StaticHttp.get "http://example.com" (Decode.succeed ()))
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "http://example.com"
                        """null"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList [ ( "[GET]http://example.com", "null" ) ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        , test "an error is sent out for decoder failures" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.fail "The user should get this message from the CLI.")
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Errors
                                """\u{001B}[36m-- FAILED STATIC HTTP ERROR ----------------------------------------------------- elm-pages\u{001B}[0m

/elm-pages

Problem with the given value:

{
        "stargazer_count": 86
    }

The user should get this message from the CLI."""
                            ]
                        )
        , test "an error is sent for missing secrets from continuation requests" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , StaticHttp.getWithSecrets
                            (\secrets ->
                                secrets
                                    |> Secrets.get "API_KEY"
                                    |> Result.map
                                        (\apiKey ->
                                            "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                        )
                            )
                            Decode.string
                            |> StaticHttp.andThen
                                (\url ->
                                    StaticHttp.getWithSecrets
                                        (\secrets ->
                                            secrets
                                                |> Secrets.get "MISSING"
                                                |> Result.map
                                                    (\missingSecret ->
                                                        url ++ "?apiKey=" ++ missingSecret
                                                    )
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
                      , StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
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
                        (Expect.equal
                            [ Errors <|
                                Terminal.toString
                                    [ Terminal.cyan <| Terminal.text "-- FAILED STATIC HTTP ERROR ----------------------------------------------------- elm-pages"
                                    , Terminal.text "\n\nI got an error making an HTTP request to this URL: "
                                    , Terminal.yellow <| Terminal.text "https://api.github.com/repos/dillonkearns/elm-pages"
                                    , Terminal.text "\n\nBad status: 404"
                                    ]
                            ]
                        )
        , test "uses real secrets to perform request and masked secrets to store and lookup response" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.getWithSecrets
                            (\secrets ->
                                secrets
                                    |> Secrets.get "API_KEY"
                                    |> Result.map
                                        (\apiKey ->
                                            "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                                        )
                            )
                            (Decode.succeed ())
                      )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=ABCD1234"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Success
                                { pages =
                                    Dict.fromList
                                        [ ( "/"
                                          , Dict.fromList
                                                [ ( "[GET]https://api.github.com/repos/dillonkearns/elm-pages?apiKey=<API_KEY>"
                                                  , """{ "stargazer_count": 86 }"""
                                                  )
                                                ]
                                          )
                                        ]
                                , manifest = manifest
                                }
                            ]
                        )
        ]


start : List ( List String, StaticHttp.Request a ) -> ProgramTest Main.Model Main.Msg (Main.Effect PathKey)
start pages =
    let
        document =
            Document.fromList
                [ Document.parser
                    { extension = "md"
                    , metadata = Decode.succeed ()
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
            ContentCache.init document content

        siteMetadata =
            contentCache
                |> Result.map
                    (\cache -> cache |> ContentCache.extractMetadata PathKey)
                |> Result.mapError (List.map Tuple.second)

        config =
            { toJsPort = toJsPort
            , manifest = manifest
            , view =
                \allFrontmatter page ->
                    let
                        thing =
                            pages
                                |> Dict.fromList
                                |> Dict.get
                                    (page.path
                                        |> PagePath.toString
                                        |> String.dropLeft 1
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
            }
    in
    ProgramTest.createDocument
        { init = Main.init identity contentCache siteMetadata config identity
        , update = Main.update siteMetadata config
        , view = \_ -> { title = "", body = [] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start (flags """{"secrets":
        {"API_KEY": "ABCD1234"}
        }""")


flags : String -> Decode.Value
flags jsonString =
    case Decode.decodeString Decode.value jsonString of
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

        FetchHttp secureUrl ->
            let
                { masked, unmasked } =
                    Pages.Internal.Secrets.unwrap secureUrl
            in
            Http.request
                { method = unmasked.method
                , url = unmasked.url
                , headers = []
                , body = Http.emptyBody
                , expect =
                    Http.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { request = { url = masked, method = unmasked.method }
                                , response = response
                                }
                        )
                , timeout = Nothing
                , tracker = Nothing
                }


expectErrorsPort expectedPlainString actualPorts =
    case actualPorts of
        [ Errors actualRichTerminalString ] ->
            let
                actualPlainString =
                    actualRichTerminalString
                        |> Regex.replace
                            (Regex.fromString "\u{001B}\\[[0-9;]+m"
                                |> Maybe.withDefault Regex.never
                            )
                            (\_ -> "")
            in
            actualPlainString |> Expect.equal expectedPlainString

        _ ->
            Expect.fail "Expected single error port"


toJsPort foo =
    Cmd.none


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
