module Tests exposing (suite)

import Base64
import Browser
import Bytes.Encode
import Json.Encode as Encode
import Main
import Pages.Flags exposing (Flags(..))
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Path
import ProgramTest
import Route
import Route.Index
import Test exposing (Test, test)
import Test.Html.Selector exposing (text)


suite : Test
suite =
    test "wire up hello" <|
        \() ->
            start2
                |> ProgramTest.clickButton "Open Menu"
                |> ProgramTest.expectViewHas
                    [ text "elm-pages is up and running!"
                    , text "Close Menu"
                    , text "The message is: HELLO 123!@#"
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


start2 =
    ProgramTest.createApplication
        { onUrlRequest = Platform.LinkClicked
        , onUrlChange = Platform.UrlChanged
        , init =
            \flags url () ->
                Platform.init Main.config
                    flags
                    url
                    Nothing
        , update =
            \msg model ->
                Platform.update Main.config
                    msg
                    model
        , view =
            \model ->
                Platform.view Main.config model
        }
        |> ProgramTest.withBaseUrl "https://my-app.com/"
        |> ProgramTest.start flagsWithData


path =
    Path.join []


sharedData =
    ()


pageData =
    Main.DataIndex { message = "Hi!" }


route =
    Just Route.Index


sharedModel =
    Just { showMenu = False }


flagsWithData =
    Encode.object
        [ ( "pageDataBase64"
          , ResponseSketch.HotUpdate
                (Main.DataIndex { message = "HELLO 123!@#" })
                ()
                |> Main.encodeResponse
                |> Bytes.Encode.encode
                |> Base64.fromBytes
                |> expectOrError
                |> Encode.string
          )
        ]


expectOrError thing =
    case thing of
        Just justThing ->
            justThing

        Nothing ->
            Debug.todo "Expected Just but got Nothing"
