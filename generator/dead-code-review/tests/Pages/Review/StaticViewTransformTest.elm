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
        , describe "View.freeze transformation"
            [ test "transforms View.freeze with function call argument" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

view app =
    { body = [ View.freeze (renderFn app.staticData) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to View.Static.adopt"
                                , details = [ "Transforms View.freeze to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.freeze (renderFn app.staticData)"
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
    (View.Static.adopt "0" |> Html.map never)
"""
                            ]
            , test "transforms View.Static.static with function call (plain Html)" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import View.Static

view app =
    View.Static.static (renderFn app.staticData)
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.Static.static to View.Static.adopt"
                                , details = [ "Transforms View.Static.static to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.Static.static (renderFn app.staticData)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import View.Static

view app =
    (View.Static.adopt "0" |> Html.map never)
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
        , describe "Data type field tracking"
            [ test "tracks field access inside View.freeze as ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text app.data.body) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to View.Static.adopt"
                                , details = [ "Transforms View.freeze to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "does NOT transform fields used both inside and outside freeze" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text app.data.title) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to View.Static.adopt"
                                , details = [ "Transforms View.freeze to View.Static.adopt for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.title)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ (View.Static.adopt "0" |> Html.fromUnstyled |> Html.map never) ]
    }
"""
                            ]
            , test "field used ONLY in head function should be ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    , description : String
    }

head app =
    [ Html.text app.data.description ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Head function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing head function body with [] because Data fields are being removed."
                                    , "The head function never runs on the client (it's for SEO at build time), so stubbing it out allows DCE."
                                    ]
                                , under = "[ Html.text app.data.description ]"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    , description : String
    }

head app =
    []

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "NESTED field used ONLY in head function should be ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { titles : { title : String }
    , metadata : { description : String }
    }

head app =
    [ Html.text app.data.metadata.description ]

view app =
    { title = app.data.titles.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Head function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing head function body with [] because Data fields are being removed."
                                    , "The head function never runs on the client (it's for SEO at build time), so stubbing it out allows DCE."
                                    ]
                                , under = "[ Html.text app.data.metadata.description ]"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { titles : { title : String }
    , metadata : { description : String }
    }

head app =
    []

view app =
    { title = app.data.titles.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"metadata\"],\"newDataType\":\"{ titles : { title : String } }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "field used in BOTH head and view should NOT be ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static

type alias Data =
    { title : String
    }

head app =
    [ Html.text app.data.title ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "RouteBuilder convention detection"
            [ test "non-conventional head function name bails out (no optimization)" <|
                \() ->
                    -- If RouteBuilder uses { head = seoTags, ... } instead of { head = head, ... }
                    -- we should bail out of optimization to avoid incorrect field tracking
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

seoTags app =
    [ Html.text app.data.description ]

data routeParams =
    BackendTask.succeed { title = "Test", description = "Desc" }

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        -- Should NOT produce Data type transformation errors
                        -- because we bail out when non-conventional naming is detected
                        |> Review.Test.expectNoErrors
            , test "lambda in RouteBuilder head still allows DCE for fields only used in head" <|
                \() ->
                    -- If RouteBuilder uses { head = \app -> [...], ... } instead of { head = head, ... }
                    -- we CAN still track field usage in the view function and remove fields only used in head
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = \\app -> [ Html.text app.data.description ]
        , pages = pages
        , data = data
        }

data routeParams =
    BackendTask.succeed { title = "Test", description = "Desc" }

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        -- Optimization proceeds: title is client-used (in view), description is ephemeral (only in head lambda)
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":9,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            , Review.Test.error
                                { message = "Data function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing data function body because Data fields are being removed."
                                    , "The data function never runs on the client (it's for build-time data fetching), so stubbing it out allows DCE."
                                    ]
                                , under = """BackendTask.succeed { title = "Test", description = "Desc" }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = \\app -> [ Html.text app.data.description ]
        , pages = pages
        , data = data
        }

data routeParams =
    BackendTask.fail (FatalError.fromString "")

view app =
    { title = app.data.title
    , body = []
    }
"""
                            ]
            , test "conventional naming in RouteBuilder allows optimization" <|
                \() ->
                    -- RouteBuilder uses { head = head, data = data } which is conventional
                    -- so optimization should proceed
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }

head app =
    [ Html.text app.data.description ]

data routeParams =
    BackendTask.succeed { title = "Test", description = "Desc" }

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Head function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing head function body with [] because Data fields are being removed."
                                    , "The head function never runs on the client (it's for SEO at build time), so stubbing it out allows DCE."
                                    ]
                                , under = "[ Html.text app.data.description ]"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }

head app =
    []

data routeParams =
    BackendTask.succeed { title = "Test", description = "Desc" }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Data function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing data function body because Data fields are being removed."
                                    , "The data function never runs on the client (it's for build-time data fetching), so stubbing it out allows DCE."
                                    ]
                                , under = "BackendTask.succeed { title = \"Test\", description = \"Desc\" }"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import View.Static
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }

head app =
    [ Html.text app.data.description ]

data routeParams =
    BackendTask.fail (FatalError.fromString "")

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":9,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        ]
