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
import Html.Lazy

view =
    { body = [ View.freeze (Html.text "hello") ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text \"hello\")"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

view =
    { body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ] }
"""
                            ]
            , test "uses Html.Styled alias when imported as Html.Styled" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled
import View
import Html.Lazy

view =
    { body = [ View.freeze content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled
import View
import Html.Lazy
import VirtualDom

view =
    { body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.Styled.map never) ] }
"""
                            ]
            ]
        , describe "View.freeze transformation"
            [ test "transforms View.freeze with function call argument" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

view app =
    { body = [ View.freeze (renderFn app.data.content) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (renderFn app.data.content)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

view app =
    { body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ] }
"""
                            ]
            ]
        , describe "Html.Lazy import aliasing"
            [ test "uses Html.Lazy alias when imported with alias" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy as Lazy

view =
    { body = [ View.freeze content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy as Lazy
import VirtualDom

view =
    { body = [ (Lazy.lazy (\\_ -> VirtualDom.text \"\") \"__ELM_PAGES_STATIC__0\" |> View.htmlToFreezable |> Html.map never) ] }
"""
                            ]
            ]
        , describe "static index incrementing"
            [ test "increments static index for multiple static calls" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

view =
    { body =
        [ View.freeze content1
        , View.freeze content2
        ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze content1"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

view =
    { body =
        [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never)
        , View.freeze content2
        ]
    }
"""
                            , Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze content2"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

view =
    { body =
        [ View.freeze content1
        , (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__1" |> View.htmlToFreezable |> Html.map never)
        ]
    }
"""
                            ]
            ]
        , describe "auto-adding Html.Lazy import"
            [ test "adds Html.Lazy import when not present" <|
                \() ->
                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View

view =
    { body = [ View.freeze content ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze content"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Index exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

view =
    { body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ] }
"""
                            ]
            ]
        , describe "Data type field tracking"
            [ test "tracks field access inside View.freeze as ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text app.data.body) ]
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
import Html.Lazy

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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.title)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            ]
            , test "field used ONLY in head function should be ephemeral" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

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
import Html.Lazy

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
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: description"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

head app =
    [ Html.text app.data.description ]

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
import Html.Lazy

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
import Html.Lazy

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
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: metadata"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ titles : { title : String }
    , metadata : { description : String }
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { titles : { title : String } }

head app =
    [ Html.text app.data.metadata.description ]

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
import Html.Lazy

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
            [ test "non-conventional head function name works correctly" <|
                \() ->
                    -- If RouteBuilder uses { head = seoTags, ... } instead of { head = head, ... }
                    -- we correctly track that seoTags is the head function and optimize accordingly
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
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
                        -- Optimization proceeds: description is ephemeral (only used in seoTags which is the head function)
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
import Html.Lazy
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
    []

data routeParams =
    BackendTask.succeed { title = "Test", description = "Desc" }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: description"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String }

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
import Html.Lazy
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
            , test "lambda in RouteBuilder head still allows DCE for fields only used in head" <|
                \() ->
                    -- If RouteBuilder uses { head = \app -> [...], ... } instead of { head = head, ... }
                    -- we CAN still track field usage in the view function and remove fields only used in head
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
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
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: description"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String }

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
                            , Review.Test.error
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
import Html.Lazy
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
import Html.Lazy
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
import Html.Lazy
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
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: description"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String }

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
import Html.Lazy
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
        , describe "Accessor pattern field tracking"
            [ test "accessor pattern app.data |> .field tracks the specific field" <|
                \() ->
                    -- When app.data |> .field is used, we CAN track which field is accessed
                    -- The accessor function explicitly names the field
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data |> .title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        -- Should track title as client-used, body as ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data |> .title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "accessor pattern in freeze context does not cause bail-out" <|
                \() ->
                    -- When app.data |> .field is used INSIDE freeze, we don't care
                    -- because frozen content is ephemeral anyway
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text (app.data |> .body)) ]
    }
"""
                        |> Review.Test.run rule
                        -- Should produce transformation because accessor is only in freeze
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text (app.data |> .body))"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text (app.data |> .body)) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "case expression on app.data causes bail-out in client context" <|
                \() ->
                    -- When case app.data of {...} is used outside freeze/head,
                    -- we can't track which fields are destructured, so bail out entirely
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        data ->
            { title = data.title
            , body = []
            }
"""
                        |> Review.Test.run rule
                        -- Should NOT produce any Data type transformation errors
                        -- because we bail out when case expression on app.data is detected
                        -- But we DO emit a diagnostic explaining why
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)\"}"
                                , details = [ "No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "case expression on app.data in freeze context does not cause bail-out" <|
                \() ->
                    -- When case app.data of {...} is used INSIDE freeze, we don't care
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body =
        [ View.freeze
            (case app.data of
                data ->
                    Html.text data.body
            )
        ]
    }
"""
                        |> Review.Test.run rule
                        -- Should produce transformation because case is only in freeze
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = """View.freeze
            (case app.data of
                data ->
                    Html.text data.body
            )"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body =
        [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never)
        ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body =
        [ View.freeze
            (case app.data of
                data ->
                    Html.text data.body
            )
        ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "case expression with record pattern tracks specific fields" <|
                \() ->
                    -- case app.data of { title } -> ... tracks only title as client-used
                    -- body can still be ephemeral
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                        |> Review.Test.run rule
                        -- title is client-used via record pattern, body is ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
            }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "case expression with record pattern only tracks destructured fields" <|
                \() ->
                    -- case app.data of { title } -> ... only tracks title
                    -- subtitle is not destructured, so it's also ephemeral
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , subtitle : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                        |> Review.Test.run rule
                        -- Only title is client-used via record pattern
                        -- subtitle and body are not accessed, so both are ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , subtitle : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
            }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body, subtitle"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , subtitle : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"subtitle\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "case expression with wildcard pattern uses no fields" <|
                \() ->
                    -- case app.data of _ -> ... uses no fields from the pattern
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        _ ->
            { title = "constant"
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                        |> Review.Test.run rule
                        -- No fields used via pattern, body is only used in freeze
                        -- title is not used at all, so both title and body are ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        _ ->
            { title = "constant"
            , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
            }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body, title"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    {}

view app =
    case app.data of
        _ ->
            { title = "constant"
            , body = [ View.freeze (Html.text app.data.body) ]
            }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"title\"],\"newDataType\":\"{}\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Field binding tracking through let expressions"
            [ test "tracks field through simple let binding in client context" <|
                \() ->
                    -- let title = app.data.title in ... title ...
                    -- Should track that 'title' references app.data.title field
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        title = app.data.title
    in
    { title = title
    , body = [ View.freeze (Html.text app.data.body) ]
    }
"""
                        |> Review.Test.run rule
                        -- 'title' is used in client context via let binding, so it's client-used
                        -- 'body' is only used in freeze, so it's ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        title = app.data.title
    in
    { title = title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    let
        title = app.data.title
    in
    { title = title
    , body = [ View.freeze (Html.text app.data.body) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "tracks field through let binding used only in freeze as ephemeral" <|
                \() ->
                    -- let body = app.data.body in View.freeze (Html.text body)
                    -- 'body' field is only used in freeze via let binding, so it's ephemeral
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        body = app.data.body
    in
    { title = app.data.title
    , body = [ View.freeze (Html.text body) ]
    }
"""
                        |> Review.Test.run rule
                        -- 'body' is only used in freeze context, so it's ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        body = app.data.body
    in
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    let
        body = app.data.body
    in
    { title = app.data.title
    , body = [ View.freeze (Html.text body) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "tracks fields through record destructuring in let" <|
                \() ->
                    -- let { title, body } = app.data in ... title ...
                    -- Should track that 'title' and 'body' reference their respective fields
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        { title, body } = app.data
    in
    { title = title
    , body = [ View.freeze (Html.text body) ]
    }
"""
                        |> Review.Test.run rule
                        -- 'title' is used in client context, so it's client-used
                        -- 'body' is only used in freeze, so it's ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        { title, body } = app.data
    in
    { title = title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    let
        { title, body } = app.data
    in
    { title = title
    , body = [ View.freeze (Html.text body) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Conservative bail-out for app.data passed as whole"
            [ test "record update with app.data bound variable causes bail-out" <|
                \() ->
                    -- When { d | field = value } where d = app.data is used outside freeze,
                    -- we can't safely track which fields are used (all are copied)
                    -- so no EPHEMERAL_FIELDS_JSON is emitted, but View.freeze is still transformed
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        d = app.data
        modifiedData = { d | title = "new" }
    in
    { title = modifiedData.title
    , body = [ View.freeze (Html.text app.data.body) ]
    }
"""
                        |> Review.Test.run rule
                        -- View.freeze transformation still happens
                        -- but NO EPHEMERAL_FIELDS_JSON because we bailed out
                        -- Diagnostic explains why optimization was skipped
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    let
        d = app.data
        modifiedData = { d | title = "new" }
    in
    { title = modifiedData.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)\"}"
                                , details = [ "No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "app.data in list passed to function causes bail-out" <|
                \() ->
                    -- When [ app.data ] is passed to a function outside freeze,
                    -- we can't track which fields are used, so no EPHEMERAL_FIELDS_JSON is emitted
                    -- But View.freeze is still transformed to View.Static.adopt
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper [ app.data ]
    , body = [ View.freeze (Html.text app.data.body) ]
    }

someHelper items = ""
"""
                        |> Review.Test.run rule
                        -- View.freeze transformation still happens
                        -- but NO EPHEMERAL_FIELDS_JSON because we bailed out
                        -- Diagnostic explains why
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper [ app.data ]
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

someHelper items = ""
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)\"}"
                                , details = [ "No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "app.data in tuple passed to function causes bail-out" <|
                \() ->
                    -- When ( app.data, x ) is passed to a function outside freeze,
                    -- we can't track which fields are used, so no EPHEMERAL_FIELDS_JSON is emitted
                    -- But View.freeze is still transformed to View.Static.adopt
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper ( app.data, "extra" )
    , body = [ View.freeze (Html.text app.data.body) ]
    }

someHelper pair = ""
"""
                        |> Review.Test.run rule
                        -- View.freeze transformation still happens
                        -- but NO EPHEMERAL_FIELDS_JSON because we bailed out
                        -- Diagnostic explains why
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper ( app.data, "extra" )
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

someHelper pair = ""
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)\"}"
                                , details = [ "No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "record update in freeze context does not cause bail-out" <|
                \() ->
                    -- When record update is used INSIDE freeze, we don't care
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body =
        [ View.freeze
            (let
                d = app.data
                modifiedData = { d | body = "modified" }
            in
            Html.text modifiedData.body
            )
        ]
    }
"""
                        |> Review.Test.run rule
                        -- Should produce transformation because record update is only in freeze
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = """View.freeze
            (let
                d = app.data
                modifiedData = { d | body = "modified" }
            in
            Html.text modifiedData.body
            )"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body =
        [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never)
        ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body =
        [ View.freeze
            (let
                d = app.data
                modifiedData = { d | body = "modified" }
            in
            Html.text modifiedData.body
            )
        ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "app.data passed to helper function patterns"
            [ test "app.data passed to helper inside freeze should still allow optimization" <|
                \() ->
                    -- When app.data is passed to a helper function inside View.freeze,
                    -- we should STILL optimize because the freeze context is ephemeral
                    -- The body field should be marked as ephemeral (not used outside freeze)
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderContent app.data) ]
    }

renderContent data =
    Html.text data.body
"""
                        |> Review.Test.run rule
                        -- body field should be ephemeral (only used inside freeze via helper)
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (renderContent app.data)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

renderContent data =
    Html.text data.body
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderContent app.data) ]
    }

renderContent data =
    Html.text data.body
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper with Data type annotation gets Ephemeral type generated" <|
                \() ->
                    -- When a freeze-only helper has an explicit Data type annotation,
                    -- we generate an Ephemeral type alias and change the annotation to use it
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderContent app.data) ]
    }

renderContent : Data -> Html.Html msg
renderContent pageData =
    Html.text pageData.body
"""
                        |> Review.Test.run rule
                        -- Should generate Ephemeral type and change helper annotation
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (renderContent app.data)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

renderContent : Data -> Html.Html msg
renderContent pageData =
    Html.text pageData.body
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    , "Generating Ephemeral type alias and updating helper annotations for: renderContent"
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }


type alias Ephemeral =
    { title : String, body : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderContent app.data) ]
    }

renderContent : Ephemeral -> Html.Html msg
renderContent pageData =
    Html.text pageData.body
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "app.data passed to trackable helper in client context allows optimization" <|
                \() ->
                    -- When app.data is passed to a helper function in CLIENT context,
                    -- we analyze the helper to see which fields it actually uses.
                    -- If the helper is trackable (only does field accesses), we only mark
                    -- those fields as client-used, allowing optimization.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

extractTitle data =
    data.title
"""
                        |> Review.Test.run rule
                        -- extractTitle only uses 'title' field, so only 'title' is client-used
                        -- body is only used in freeze, so it's ephemeral and can be removed
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

extractTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

extractTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "mixed: direct field in client + app.data in freeze helper" <|
                \() ->
                    -- title is accessed directly in client context (client-used)
                    -- app.data is passed to helper in freeze context (ignored)
                    -- body is only used in freeze via helper, so it's ephemeral
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    , metadata : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderBody app.data.body app.data.metadata) ]
    }

renderBody body meta =
    Html.text (body ++ meta)
"""
                        |> Review.Test.run rule
                        -- title is client-used (direct access)
                        -- body and metadata are ephemeral (only in freeze)
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (renderBody app.data.body app.data.metadata)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    , metadata : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

renderBody body meta =
    Html.text (body ++ meta)
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body, metadata"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    , metadata : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (renderBody app.data.body app.data.metadata) ]
    }

renderBody body meta =
    Html.text (body ++ meta)
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"metadata\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper with record destructuring pattern in client context allows optimization" <|
                \() ->
                    -- When a helper function has a record destructuring pattern like { title, body },
                    -- and app.data is passed to it in CLIENT context, we know EXACTLY which fields
                    -- are used (the ones in the pattern). This allows optimization even without
                    -- analyzing the function body.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    , unused : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- This helper uses record destructuring - we know it only needs 'title'
extractTitle { title } =
    title
"""
                        |> Review.Test.run rule
                        -- extractTitle only destructures 'title', so only 'title' is client-used
                        -- 'body' is only used in freeze, so it's ephemeral
                        -- 'unused' is never used, so it's also ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    , unused : String
    }

view app =
    { title = extractTitle app.data
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

-- This helper uses record destructuring - we know it only needs 'title'
extractTitle { title } =
    title
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body, unused"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    , unused : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- This helper uses record destructuring - we know it only needs 'title'
extractTitle { title } =
    title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"unused\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper with record destructuring that accesses multiple fields" <|
                \() ->
                    -- Record pattern with multiple fields should track all of them
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , author : String
    , body : String
    }

view app =
    { title = renderHeader app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- This helper destructures both title and author
renderHeader { title, author } =
    title ++ " by " ++ author
"""
                        |> Review.Test.run rule
                        -- title and author are used in client context (via renderHeader)
                        -- body is only used in freeze, so it's ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , author : String
    , body : String
    }

view app =
    { title = renderHeader app.data
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

-- This helper destructures both title and author
renderHeader { title, author } =
    title ++ " by " ++ author
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , author : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String, author : String }

view app =
    { title = renderHeader app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- This helper destructures both title and author
renderHeader { title, author } =
    title ++ " by " ++ author
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String, author : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Accessor function application pattern"
            [ test "accessor function applied to app.data tracks specific field" <|
                \() ->
                    -- .title app.data is equivalent to app.data |> .title
                    -- Should track title as client-used, body as ephemeral
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title app.data
    , body = []
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = .title app.data
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "accessor function applied to app.data in freeze context does not cause bail-out" <|
                \() ->
                    -- .body app.data inside freeze should not prevent optimization
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text (.body app.data)) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text (.body app.data))"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text (.body app.data)) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Helper function with pipe accessor pattern"
            [ test "helper using data |> .field is trackable and allows optimization" <|
                \() ->
                    -- When a helper function uses data |> .field to access a field,
                    -- we should be able to track which field is accessed.
                    -- Previously this would mark the helper as untrackable because
                    -- 'data' appears as a bare variable on the left side of the pipe.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses pipe with accessor to get title field
extractTitle data =
    data |> .title
"""
                        |> Review.Test.run rule
                        -- extractTitle only accesses 'title' via pipe+accessor
                        -- So title is client-used, body is ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses pipe with accessor to get title field
extractTitle data =
    data |> .title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper using .field <| data (backward pipe) is trackable" <|
                \() ->
                    -- Same test but with backward pipe syntax
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses backward pipe with accessor
extractTitle data =
    .title <| data
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses backward pipe with accessor
extractTitle data =
    .title <| data
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper using .field data (accessor application) is trackable" <|
                \() ->
                    -- Same test but with accessor function application syntax
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses accessor function application
extractTitle data =
    .title data
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses accessor function application
extractTitle data =
    .title data
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Function alias tracking"
            [ test "aliased helper function is trackable through simple alias" <|
                \() ->
                    -- When a helper function is aliased (myRender = renderContent),
                    -- and the aliased name is used in client context,
                    -- we should follow the alias chain to get the original helper's field analysis.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myExtract app.data
    , body = []
    }

-- Original helper function
extractTitle data =
    data.title

-- Alias to the helper
myExtract =
    extractTitle
"""
                        |> Review.Test.run rule
                        -- myExtract is an alias to extractTitle which only uses 'title'
                        -- so only 'title' is client-used, 'body' is ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = myExtract app.data
    , body = []
    }

-- Original helper function
extractTitle data =
    data.title

-- Alias to the helper
myExtract =
    extractTitle
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "chained function aliases are trackable" <|
                \() ->
                    -- When aliases are chained (a = b, b = c, c = actualHelper),
                    -- we should follow the entire chain.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = aliasC app.data
    , body = []
    }

-- Original helper function
extractTitle data =
    data.title

-- Chain of aliases: aliasC -> aliasB -> extractTitle
aliasB =
    extractTitle

aliasC =
    aliasB
"""
                        |> Review.Test.run rule
                        -- aliasC -> aliasB -> extractTitle which only uses 'title'
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = aliasC app.data
    , body = []
    }

-- Original helper function
extractTitle data =
    data.title

-- Chain of aliases: aliasC -> aliasB -> extractTitle
aliasB =
    extractTitle

aliasC =
    aliasB
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "alias to unknown function bails out safely" <|
                \() ->
                    -- When an alias points to a function we can't analyze (e.g., imported),
                    -- we should bail out safely and keep all fields persistent.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import SomeModule

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myHelper app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- Alias to an imported (unknown) function
myHelper =
    SomeModule.process
"""
                        |> Review.Test.run rule
                        -- Can't analyze SomeModule.process, so bail out
                        -- Only View.freeze transformation, no Data narrowing
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import SomeModule
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myHelper app.data
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

-- Alias to an imported (unknown) function
myHelper =
    SomeModule.process
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)\"}"
                                , details = [ "No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Helper function with case expression on parameter"
            [ test "helper using case data of { title } -> ... is trackable" <|
                \() ->
                    -- When a helper function uses case on its parameter with record patterns,
                    -- we should be able to track which fields are accessed.
                    -- This is a common pattern for functions that pattern match on their input.
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses case expression with record pattern
extractTitle data =
    case data of
        { title } -> title
"""
                        |> Review.Test.run rule
                        -- extractTitle only destructures 'title' via case, so only 'title' is client-used
                        -- body is ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = []
    }

-- Helper uses case expression with record pattern
extractTitle data =
    case data of
        { title } -> title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper using case with multiple record patterns tracks all fields from all branches" <|
                \() ->
                    -- When case has multiple branches, we should track fields from ALL branches
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , subtitle : String
    , body : String
    }

view app =
    { title = extractHeading app.data
    , body = []
    }

-- Helper uses multiple fields across case branches
extractHeading data =
    case data of
        { title, subtitle } -> title ++ subtitle
"""
                        |> Review.Test.run rule
                        -- title and subtitle are used in case pattern, body is ephemeral
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , subtitle : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String, subtitle : String }

view app =
    { title = extractHeading app.data
    , body = []
    }

-- Helper uses multiple fields across case branches
extractHeading data =
    case data of
        { title, subtitle } -> title ++ subtitle
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String, subtitle : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":11,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "helper using case with variable pattern still bails out" <|
                \() ->
                    -- When case has a variable pattern (d -> d.title), we can't track, so bail out
                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.text app.data.body) ]
    }

-- Helper uses case with variable pattern - can't track
extractTitle data =
    case data of
        d -> d.title
"""
                        |> Review.Test.run rule
                        -- Can't analyze case with variable pattern, so bail out
                        -- Only View.freeze transformation, no Data narrowing
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text app.data.body)"
                                }
                                |> Review.Test.whenFixed
                                    """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import VirtualDom

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = [ (Html.Lazy.lazy (\\_ -> VirtualDom.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

-- Helper uses case with variable pattern - can't track
extractTitle data =
    case data of
        d -> d.title
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)\"}"
                                , details = [ "No fields could be removed from Data type. app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        ]
