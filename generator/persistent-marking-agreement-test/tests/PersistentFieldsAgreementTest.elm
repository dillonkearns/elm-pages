module PersistentFieldsAgreementTest exposing (all)

{-| Tests that verify the Server transform (ServerDataTransform) and
Client transform (StaticViewTransform) agree on which fields are ephemeral.

These tests verify AGREEMENT by testing both transforms on identical code
and checking that:
1. When server marks field X as ephemeral, client also marks X as ephemeral
2. When server keeps all fields persistent (no transform), client also keeps all persistent

The individual transform test suites verify fix correctness. These tests
focus on the KEY AGREEMENT property that prevents runtime decode errors.
-}

import Pages.Review.ServerDataTransform as ServerDataTransform
import Pages.Review.StaticViewTransform as StaticViewTransform
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Persistent/Ephemeral Field Agreement"
        [ describe "Basic scenarios - server and client agree"
            [ test "AGREEMENT: field only in freeze - both mark body as ephemeral" <|
                \() ->
                    -- This scenario: body is only accessed inside View.freeze
                    -- Expected: Both transforms mark body as ephemeral
                    -- Verified by: server produces "Ephemeral fields: body"
                    --              client produces EPHEMERAL_FIELDS_JSON with body
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral (produces split Data error)
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            ]
            , test "AGREEMENT: field only in freeze - client also marks body as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Client marks body as ephemeral (produces EPHEMERAL_FIELDS_JSON)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: field used in both contexts - server keeps persistent" <|
                \() ->
                    -- title is used both inside freeze AND in view title (client context)
                    -- Expected: Both transforms keep title as persistent (no split)
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.title ]) ]
    }
"""
                    in
                    -- Server: no ephemeral fields, no transformation
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectNoErrors
            , test "AGREEMENT: field used in both contexts - client keeps persistent" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.title ]) ]
    }
"""
                    in
                    -- Client: only View.freeze transform, no Data type narrowing
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.title ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
            ]
        , describe "Safe fallback scenarios - both bail out consistently"
            [ test "AGREEMENT: app.data in list - server bails out (all persistent)" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper [ app.data ]
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

someHelper items = ""
"""
                    in
                    -- Server bails out: can't track fields through [ app.data ]
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectNoErrors
            , test "AGREEMENT: app.data in list - client bails out (all persistent)" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper [ app.data ]
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

someHelper items = ""
"""
                    in
                    -- Client bails out: can't track fields through [ app.data ]
                    -- No EPHEMERAL_FIELDS_JSON emitted (diagnostic instead)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
            , test "AGREEMENT: accessor pattern - server tracks specific field" <|
                \() ->
                    -- Both transforms CAN track accessor patterns like app.data |> .field
                    -- The accessor function explicitly names the field, so we track it precisely
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data |> .title
    , body = []
    }
"""
                    in
                    -- Server tracks title as persistent, body as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = app.data |> .title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data |> .title
    , body = []
    }
"""
                            ]
            , test "AGREEMENT: accessor pattern - client also tracks specific field" <|
                \() ->
                    -- Both transforms CAN track accessor patterns like app.data |> .field
                    -- The accessor function explicitly names the field, so we track it precisely
                    let
                        testModule =
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
                    in
                    -- Client tracks title as client-used, body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
            ]
        , describe "Helper inside freeze - both still optimize"
            [ test "AGREEMENT: helper inside freeze - server still marks body as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ renderContent app.data ]) ]
    }

renderContent data =
    Html.text data.body
"""
                    in
                    -- Server: app.data inside freeze is fine, body is ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ renderContent app.data ]) ]
    }

renderContent data =
    Html.text data.body
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ renderContent app.data ]) ]
    }

renderContent data =
    Html.text data.body
"""
                            ]
            , test "AGREEMENT: helper inside freeze - client still marks body as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ renderContent app.data ]) ]
    }

renderContent data =
    Html.text data.body
"""
                    in
                    -- Client: app.data inside freeze is fine, body is ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ renderContent app.data ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ renderContent app.data ]) ]
    }

renderContent data =
    Html.text data.body
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Multiple ephemeral fields - both agree on the set"
            [ test "AGREEMENT: multiple fields - server marks body and metadata as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    , metadata : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (app.data.body ++ app.data.metadata) ]) ]
    }
"""
                    in
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body, metadata"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , metadata : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Ephemeral =
    { title : String
    , body : String
    , metadata : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (app.data.body ++ app.data.metadata) ]) ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    , metadata : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (app.data.body ++ app.data.metadata) ]) ]
    }
"""
                            ]
            , test "AGREEMENT: multiple fields - client marks body and metadata as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (app.data.body ++ app.data.metadata) ]) ]
    }
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text (app.data.body ++ app.data.metadata) ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (app.data.body ++ app.data.metadata) ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"metadata\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Case pattern tracking - both agree on record patterns"
            [ test "AGREEMENT: case with record pattern - server tracks specific fields" <|
                \() ->
                    -- case app.data of { title } -> ... tracks title as persistent
                    -- body is ephemeral since it's not accessed
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = []
            }
"""
                    in
                    -- Server marks body as ephemeral (title is tracked via record pattern)
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = []
            }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        { title } ->
            { title = title
            , body = []
            }
"""
                            ]
            , test "AGREEMENT: case with record pattern - client also tracks specific fields" <|
                \() ->
                    let
                        testModule =
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
            , body = []
            }
"""
                    in
                    -- Client also marks body as ephemeral (title tracked via record pattern)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    case app.data of
        { title } ->
            { title = title
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
            , test "AGREEMENT: case with variable pattern - server bails out" <|
                \() ->
                    -- case app.data of d -> d.title uses variable pattern, must bail out
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    case app.data of
        d ->
            { title = d.title
            , body = []
            }
"""
                    in
                    -- Server bails out: variable pattern is not trackable
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectNoErrors
            , test "AGREEMENT: case with variable pattern - client also bails out" <|
                \() ->
                    let
                        testModule =
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
        d ->
            { title = d.title
            , body = []
            }
"""
                    in
                    -- Client bails out: variable pattern is not trackable
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)\"}"
                                , details = [ "No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)" ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Uncalled helper functions - both agree"
            [ test "AGREEMENT: uncalled helper with app.data - server marks body as ephemeral" <|
                \() ->
                    -- Helper function that's defined but never called from view
                    -- Its field accesses don't count as client-used
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

unusedHelper app =
    [ app.data.body ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Server: body is accessed in unusedHelper, but unusedHelper is never called
                    -- from view, so body is never needed in client context → ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

unusedHelper app =
    [ app.data.body ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

unusedHelper app =
    [ app.data.body ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                            ]
            , test "AGREEMENT: uncalled helper with app.data - client also marks body as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

unusedHelper app =
    [ app.data.body ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Client: body is accessed in unusedHelper, but unusedHelper is never called
                    -- from view, so body is never needed in client context → ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

unusedHelper app =
    [ app.data.body ]

view app =
    { title = app.data.title
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
            ]
        , describe "Helper with record destructuring - both agree"
            [ test "AGREEMENT: helper with record pattern in client context - server optimizes" <|
                \() ->
                    -- Helper with record destructuring pattern like { title }
                    -- Both transforms should know EXACTLY which fields are used
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    , unused : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle { title } =
    title
"""
                    in
                    -- Server: extractTitle only needs 'title', body only in freeze, unused never
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body, unused"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , unused : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Ephemeral =
    { title : String
    , body : String
    , unused : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle { title } =
    title
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    , unused : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle { title } =
    title
"""
                            ]
            , test "AGREEMENT: helper with record pattern in client context - client optimizes" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle { title } =
    title
"""
                    in
                    -- Client: extractTitle only needs 'title', body only in freeze, unused never
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle { title } =
    title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"unused\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Accessor function application - both agree"
            [ test "AGREEMENT: accessor function .field app.data - server tracks specific field" <|
                \() ->
                    -- .title app.data should track title as persistent, body as ephemeral
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title app.data
    , body = []
    }
"""
                    in
                    -- Server tracks title as persistent, body as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = .title app.data
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title app.data
    , body = []
    }
"""
                            ]
            , test "AGREEMENT: accessor function .field app.data - client also tracks specific field" <|
                \() ->
                    let
                        testModule =
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
                    in
                    -- Client tracks title as client-used, body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
            ]
        , describe "Backward pipe operator with accessor - both agree"
            [ test "AGREEMENT: backward pipe .field <| app.data - server tracks specific field" <|
                \() ->
                    -- .title <| app.data should track title as persistent, body as ephemeral
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title <| app.data
    , body = []
    }
"""
                    in
                    -- Server tracks title as persistent, body as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = .title <| app.data
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title <| app.data
    , body = []
    }
"""
                            ]
            , test "AGREEMENT: backward pipe .field <| app.data - client also tracks specific field" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = .title <| app.data
    , body = []
    }
"""
                    in
                    -- Client tracks title as client-used, body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
    { title = .title <| app.data
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
            ]
        , describe "Helper function with accessor patterns - both agree"
            [ test "AGREEMENT: helper using data |> .field - server optimizes" <|
                \() ->
                    -- Helper function uses pipe with accessor: data |> .title
                    -- Both transforms should track the specific field and allow optimization
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    data |> .title
"""
                    in
                    -- Server: extractTitle only accesses title, body is ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    data |> .title
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    data |> .title
"""
                            ]
            , test "AGREEMENT: helper using data |> .field - client also optimizes" <|
                \() ->
                    let
                        testModule =
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

extractTitle data =
    data |> .title
"""
                    in
                    -- Client: extractTitle only accesses title, body is ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
            , test "AGREEMENT: helper using .field data - server optimizes" <|
                \() ->
                    -- Helper function uses accessor application: .title data
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    .title data
"""
                    in
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    .title data
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    .title data
"""
                            ]
            , test "AGREEMENT: helper using .field data - client also optimizes" <|
                \() ->
                    let
                        testModule =
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

extractTitle data =
    .title data
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
        , describe "Let alias in helper functions - both agree"
            [ test "AGREEMENT: helper using let alias of parameter - server optimizes" <|
                \() ->
                    -- Helper function that aliases parameter: let d = data in d.title
                    -- Should track title as the only accessed field
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d.title
"""
                    in
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d.title
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d.title
"""
                            ]
            , test "AGREEMENT: helper using let alias of parameter - client also optimizes" <|
                \() ->
                    let
                        testModule =
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

extractTitle data =
    let
        d = data
    in
    d.title
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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

extractTitle data =
    let
        d = data
    in
    d.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: helper using chained let aliases - server optimizes" <|
                \() ->
                    -- let d = data in let e = d in e.title should track title
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    let
        e = d
    in
    e.title
"""
                    in
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    let
        e = d
    in
    e.title
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    let
        e = d
    in
    e.title
"""
                            ]
            , test "AGREEMENT: helper using chained let aliases - client also optimizes" <|
                \() ->
                    let
                        testModule =
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

extractTitle data =
    let
        d = data
    in
    let
        e = d
    in
    e.title
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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

extractTitle data =
    let
        d = data
    in
    let
        e = d
    in
    e.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: helper using let alias with pipe accessor - server optimizes" <|
                \() ->
                    -- let d = data in d |> .title should track title
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d |> .title
"""
                    in
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View

type alias Ephemeral =
    { title : String
    , body : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d |> .title
"""
                            , Review.Test.error
                                { message = "Server codemod: export Ephemeral type"
                                , details =
                                    [ "Adding Ephemeral to module exports."
                                    , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                    ]
                                , under = "Data"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 29 }, end = { row = 1, column = 33 } }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = []
    }

extractTitle data =
    let
        d = data
    in
    d |> .title
"""
                            ]
            , test "AGREEMENT: helper using let alias with pipe accessor - client also optimizes" <|
                \() ->
                    let
                        testModule =
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

extractTitle data =
    let
        d = data
    in
    d |> .title
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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

extractTitle data =
    let
        d = data
    in
    d |> .title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        ]
