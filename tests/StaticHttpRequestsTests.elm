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
                      , { url = "https://api.github.com/repos/dillonkearns/elm-pages", decoder = Decode.succeed () }
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
        , test "port is sent out once all requests are finished" <|
            \() ->
                start
                    [ ( [ "elm-pages" ]
                      , { url = "https://api.github.com/repos/dillonkearns/elm-pages", decoder = Decode.succeed () }
                      )
                    , ( [ "elm-pages-starter" ]
                      , { url = "https://api.github.com/repos/dillonkearns/elm-pages-starter", decoder = Decode.succeed () }
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
        , test "an error is sent out for decoder failures" <|
            \() ->
                start
                    [ ( [ "elm-pages" ], { url = "https://api.github.com/repos/dillonkearns/elm-pages", decoder = Decode.fail "The user should get this message from the CLI." } )
                    ]
                    |> ProgramTest.simulateHttpOk
                        "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        """{ "stargazer_count": 86 }"""
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder Main.toJsCodec)
                        (Expect.equal
                            [ Main.Errors Dict.empty
                            ]
                        )
        ]


start : List ( List String, { url : String, decoder : Decode.Decoder () } ) -> ProgramTest Main.Model Main.Msg (Main.Effect PathKey)
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
                |> Result.mapError
                    (\error ->
                        error
                            |> Dict.toList
                            |> List.map (\( path, errorString ) -> errorString)
                    )

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
                        Just { url, decoder } ->
                            StaticHttp.jsonRequest url
                                decoder
                                |> StaticHttp.map
                                    (\staticData -> { view = \model viewForPage -> { title = "Title", body = Html.text "" }, head = [] })

                        Nothing ->
                            Debug.todo "Couldn't find page"
            }
    in
    ProgramTest.createDocument
        { init = Main.init identity contentCache siteMetadata config identity
        , update = Main.update siteMetadata config
        , view = \_ -> { title = "", body = [ Html.text "" ] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start ()


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

        FetchHttp url ->
            SimulatedEffect.Http.get
                { url = url
                , expect =
                    SimulatedEffect.Http.expectString
                        (\response ->
                            Main.GotStaticHttpResponse
                                { url = url
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
