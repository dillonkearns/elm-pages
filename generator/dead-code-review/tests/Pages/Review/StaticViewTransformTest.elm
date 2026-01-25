module Pages.Review.StaticViewTransformTest exposing (all)

import Pages.Review.StaticViewTransform exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "StaticViewTransform"
        [ describe "View.static transformation"
            [ test "transforms View.static to View.Static.adopt with Html.Styled wrapper" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body = [ View.static (Html.text "hello") ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static (Html.text \"hello\")"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body = [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never) ] }
"""
                            ]
            , test "uses Html.Styled alias when imported as Html.Styled" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled
import View
import View.Static

view =
    { body = [ View.static content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled
import View
import View.Static

view =
    { body = [ (View.Static.adopt "0" |> Html.Styled.fromUnstyled |> Html.Styled.map never) ] }
"""
                            ]
            ]
        , describe "View.staticView transformation"
            [ test "transforms View.staticView to View.Static.adopt" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view app =
    { body = [ View.staticView app.data.content renderFn ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.staticView to View.Static.adopt"
                                , details = [ "Transforms View.staticView to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.staticView app.data.content renderFn"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view app =
    { body = [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never) ] }
"""
                            ]
            ]
        , describe "View.staticBackendTask transformation"
            [ test "transforms View.staticBackendTask to BackendTask.fail" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import View
import View.Static

data =
    View.staticBackendTask (parseMarkdown "content.md")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.staticBackendTask to BackendTask.fail"
                                , details = [ "Transforms View.staticBackendTask to BackendTask.fail for client-side adoption and DCE" ]
                                , under = "View.staticBackendTask (parseMarkdown \"content.md\")"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import View
import View.Static

data =
    BackendTask.fail (FatalError.fromString "static only data")
"""
                            ]
            ]
        , describe "View.Static module calls"
            [ test "transforms View.Static.static to View.Static.adopt (plain Html)" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import View.Static

view =
    View.Static.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.Static.static to View.Static.adopt"
                                , details = [ "Transforms View.Static.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.Static.static (Html.text \"hello\")"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import View.Static

view =
    View.Static.adopt "0"
"""
                            ]
            , test "transforms View.Static.view to View.Static.adopt (plain Html)" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import View.Static

view app =
    View.Static.view app.data.content renderFn
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.Static.view to View.Static.adopt"
                                , details = [ "Transforms View.Static.view to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.Static.view app.data.content renderFn"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import View.Static

view app =
    View.Static.adopt "0"
"""
                            ]
            , test "transforms View.Static.backendTask to BackendTask.fail" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import View.Static

data =
    View.Static.backendTask (parseMarkdown "content.md")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.Static.backendTask to BackendTask.fail"
                                , details = [ "Transforms View.Static.backendTask to BackendTask.fail for client-side adoption and DCE" ]
                                , under = "View.Static.backendTask (parseMarkdown \"content.md\")"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import View.Static

data =
    BackendTask.fail (FatalError.fromString "static only data")
"""
                            ]
            ]
        , describe "View.Static import aliasing"
            [ test "uses View.Static alias when imported with alias" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static as VS

view =
    { body = [ View.static content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static as VS

view =
    { body = [ (VS.adopt "0" |> Html.fromUnstyled |> Html.map never) ] }
"""
                            ]
            ]
        , describe "static index incrementing"
            [ test "increments static index for multiple static calls" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body =
        [ View.static content1
        , View.static content2
        ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static content1"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body =
        [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never)
        , View.static content2
        ]
    }
"""
                            , Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static content2"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body =
        [ View.static content1
        , (View.Static.adopt "1" |> Html.fromUnstyled |> Html.map never)
        ]
    }
"""
                            ]
            ]
        , describe "auto-adding View.Static import"
            [ test "adds View.Static import when not present" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View

view =
    { body = [ View.static content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.static to View.Static.adopt"
                                , details = [ "Transforms View.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.static content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view =
    { body = [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never) ] }
"""
                            ]
            ]
        ]
