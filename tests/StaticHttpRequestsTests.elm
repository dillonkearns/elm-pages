module StaticHttpRequestsTests exposing (all)

import Dict
import Html
import Json.Decode as Decode
import Pages.ContentCache as ContentCache
import Pages.Document as Document
import Pages.ImagePath as ImagePath
import Pages.Internal.Platform.Cli as Main
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath
import Pages.StaticHttp as StaticHttp
import ProgramTest exposing (ProgramTest)
import Test exposing (Test, describe, test)


all : Test
all =
    describe "GrammarCheckingExample"
        [ test "checking grammar" <|
            \() ->
                start
                    |> ProgramTest.done

        --                    |> ProgramTest.fillIn "main"
        --                        "Enter text to check"
        --                        "The youngest man the boat."
        --                    |> ProgramTest.clickButton "Check"
        --                    |> ProgramTest.ensureOutgoingPortValues
        --                        "checkGrammar"
        --                        Json.Decode.string
        --                        (Expect.equal [ "The youngest man the boat." ])
        --                    |> ProgramTest.simulateIncomingPort
        --                        "grammarCheckResults"
        --                        (Json.Encode.list Json.Encode.string
        --                            [ "Garden-path sentences can confuse the reader." ]
        --                        )
        --                    |> ProgramTest.expectViewHas
        --                        [ text "Garden-path sentences can confuse the reader." ]
        ]


start : ProgramTest Main.Model Main.Msg Main.Effect
start =
    let
        document =
            Document.fromList []

        content =
            []

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
                    StaticHttp.withData "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        (\staticData ->
                            { view =
                                \model viewForPage ->
                                    { title = "Title"
                                    , body =
                                        "elm-pages ⭐️'s: "
                                            ++ String.fromInt staticData
                                            |> Html.text
                                    }
                            , head = []
                            }
                        )
            }
    in
    ProgramTest.createDocument
        { init = Main.init identity contentCache siteMetadata config identity
        , update = Main.update siteMetadata config
        , view = \_ -> { title = "", body = [ Html.text "" ] }
        }
        --        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start ()


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
    , startUrl = PagePath.build PathKey []
    , shortName = Just "elm-pages"
    , sourceIcon = ImagePath.build PathKey []
    }
