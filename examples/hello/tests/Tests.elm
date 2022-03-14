module Tests exposing (suite)

import Browser
import Main
import Pages.Flags exposing (Flags(..))
import Path
import ProgramTest
import Route
import Test exposing (Test, test)
import Test.Html.Selector exposing (text)


suite : Test
suite =
    test "wire up hello" <|
        \() ->
            start
                |> ProgramTest.clickButton "Open Menu"
                |> ProgramTest.expectViewHas
                    [ text "elm-pages is up and running!"
                    , text "Close Menu"
                    ]


start =
    ProgramTest.createApplication
        { onUrlRequest =
            \urlRequest ->
                case urlRequest of
                    Browser.Internal url ->
                        Main.OnPageChange
                            { protocol = url.protocol
                            , host = url.host
                            , port_ = url.port_
                            , path = url.path |> Path.fromString
                            , query = url.query
                            , fragment = url.fragment
                            , metadata = route
                            }

                    Browser.External _ ->
                        Debug.todo "Unhandled"
        , onUrlChange =
            \url ->
                Main.OnPageChange
                    { protocol = url.protocol
                    , host = url.host
                    , port_ = url.port_
                    , path = url.path |> Path.fromString
                    , query = url.query
                    , fragment = url.fragment
                    , metadata = route
                    }
        , init =
            \flags initialUrl () ->
                Main.init
                    sharedModel
                    flags
                    sharedData
                    pageData
                    -- navKey
                    Nothing
                    -- Path and stuff
                    (Just
                        { path =
                            { path = Path.join []
                            , query = Nothing
                            , fragment = Nothing
                            }
                        , metadata = route
                        , pageUrl = Nothing -- TODO --Maybe PageUrl
                        }
                    )
        , update =
            \msg model ->
                Main.update
                    sharedData
                    pageData
                    Nothing
                    msg
                    model
        , view =
            \model ->
                model
                    |> (Main.view
                            { path = path
                            , route = route
                            }
                            Nothing
                            sharedData
                            pageData
                            |> .view
                       )
                    |> (\{ title, body } -> { title = title, body = [ body ] })
        }
        |> ProgramTest.withBaseUrl "https://my-app.com/"
        |> ProgramTest.start Pages.Flags.PreRenderFlags


path =
    Path.join []


sharedData =
    ()


pageData =
    Main.DataIndex {}


route =
    Just Route.Index


sharedModel =
    Just { showMenu = False }
