module StaticHttpRequestsTests exposing (all)

import Codec
import Dict exposing (Dict)
import Expect
import Html
import Json.Decode as Decode
import Pages.ContentCache as ContentCache
import Pages.Document as Document
import Pages.ImagePath as ImagePath
import Pages.Internal.Platform.Cli as Main exposing (..)
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import ProgramTest exposing (ProgramTest)
import Secrets exposing (Secrets)
import SimulatedEffect.Cmd
import SimulatedEffect.Http
import SimulatedEffect.Ports
import StaticHttp
import Test exposing (Test, describe, only, test)


all : Test
all =
    describe "Static Http Requests"
        [ test "initial requests are sent out" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
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
                                                [ ( "https://api.github.com/repos/dillonkearns/elm-pages"
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
                      , StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
                            |> StaticHttp.andThen
                                (\continueUrl ->
                                    StaticHttp.jsonRequest "NEXT-REQUEST" (Decode.succeed ())
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
                                                [ ( "https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """null"""
                                                  )
                                                , ( "NEXT-REQUEST"
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
                      , StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.succeed ())
                      )
                    , ( [ "elm-pages-starter" ]
                      , StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages-starter" (Decode.succeed ())
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
                                                [ ( "https://api.github.com/repos/dillonkearns/elm-pages"
                                                  , """{ "stargazer_count": 86 }"""
                                                  )
                                                ]
                                          )
                                        , ( "/elm-pages-starter"
                                          , Dict.fromList
                                                [ ( "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                                                  , """{ "stargazer_count": 22 }"""
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
                            (StaticHttp.jsonRequest "http://example.com" (Decode.succeed ()))
                            (StaticHttp.jsonRequest "http://example.com" (Decode.succeed ()))
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
                                          , Dict.fromList [ ( "http://example.com", "null" ) ]
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
                      , StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.fail "The user should get this message from the CLI.")
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
        , test "uses real secrets to perform request and masked secrets to store and lookup response" <|
            \() ->
                start
                    [ ( []
                      , StaticHttp.jsonRequestWithSecrets
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
                                                [ ( "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=<API_KEY>"
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

        FetchHttp unmaskedUrl maskedUrl ->
            SimulatedEffect.Http.get
                { url = unmaskedUrl
                , expect =
                    SimulatedEffect.Http.expectString
                        (\response ->
                            GotStaticHttpResponse
                                { url = maskedUrl
                                , response = response
                                }
                        )
                }


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
