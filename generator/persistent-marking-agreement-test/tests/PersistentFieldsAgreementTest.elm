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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.title ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
            , test "AGREEMENT: record update on app.data binding - server bails out (all persistent)" <|
                \() ->
                    -- Record update on a variable bound to app.data uses ALL fields from app.data
                    -- (the record is copied with modifications), so we can't track individual fields
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
    let
        d = app.data
    in
    { title = ({ d | title = "modified" }).title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server bails out: can't track fields through record update on app.data
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectNoErrors
            , test "AGREEMENT: record update on app.data binding - client bails out (all persistent)" <|
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
    let
        d = app.data
    in
    { title = ({ d | title = "modified" }).title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Client bails out: can't track fields through record update on app.data
                    -- No EPHEMERAL_FIELDS_JSON emitted (diagnostic instead)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    let
        d = app.data
    in
    { title = ({ d | title = "modified" }).title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "OPTIMIZATION_DIAGNOSTIC_JSON:{\"module\":\"Route.Test\",\"reason\":\"all_fields_client_used\",\"details\":\"No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)\"}"
                                , details = [ "No fields could be removed from Data type. app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)" ]
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ renderContent app.data ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"metadata\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , metadata : String
    }"""
                                }
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text (app.data.body ++ app.data.metadata) ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
            , test "AGREEMENT: case with variable pattern - server tracks field accesses on binding" <|
                \() ->
                    -- case app.data of d -> d.title uses variable pattern
                    -- Server tracks field accesses on `d` (the binding) in the case body
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
                    -- Server tracks d.title access, body is ephemeral
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
        d ->
            { title = d.title
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
        d ->
            { title = d.title
            , body = []
            }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: case with variable pattern - client also tracks field accesses on binding" <|
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
                    -- Client tracks d.title access, body is ephemeral
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
        d ->
            { title = d.title
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
        , describe "Helper function case patterns - both agree"
            [ test "AGREEMENT: helper with case record pattern - server tracks specific fields" <|
                \() ->
                    -- Helper function uses case data of { title } -> title
                    -- Both transforms should track only 'title' as used
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

extractTitle data =
    case data of
        { title } -> title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                    in
                    -- Server should mark body as ephemeral (title is client-used via helper)
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

extractTitle data =
    case data of
        { title } -> title

view app =
    { title = extractTitle app.data
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

extractTitle data =
    case data of
        { title } -> title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: helper with case record pattern - client also tracks specific fields" <|
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

extractTitle data =
    case data of
        { title } -> title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                    in
                    -- Client should also track title as client-used via helper, body is ephemeral
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

extractTitle data =
    case data of
        { title } -> title

view app =
    { title = extractTitle app.data
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
            , test "AGREEMENT: helper with case variable pattern - server tracks field accesses on binding" <|
                \() ->
                    -- Helper function uses case data of d -> d.title
                    -- Server tracks field accesses on `d` in the case body
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

extractTitle data =
    case data of
        d -> d.title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                    in
                    -- Server tracks d.title access in helper, body is ephemeral
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

extractTitle data =
    case data of
        d -> d.title

view app =
    { title = extractTitle app.data
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

extractTitle data =
    case data of
        d -> d.title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: helper with case variable pattern - client also tracks field accesses on binding" <|
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

extractTitle data =
    case data of
        d -> d.title

view app =
    { title = extractTitle app.data
    , body = []
    }
"""
                    in
                    -- Client tracks d.title access in helper, body is ephemeral
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

extractTitle data =
    case data of
        d -> d.title

view app =
    { title = extractTitle app.data
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"unused\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , unused : String
    }"""
                                }
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
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
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
        , describe "Function alias agreement"
            [ test "AGREEMENT: aliased helper function - server optimizes" <|
                \() ->
                    -- When a helper function is aliased (myExtract = extractTitle),
                    -- and used in freeze-only context, server should mark body as ephemeral
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (myExtract app.data) ]) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (myExtract app.data) ]) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (myExtract app.data) ]) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: aliased helper function - client also optimizes" <|
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (myExtract app.data) ]) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text (myExtract app.data) ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (myExtract app.data) ]) ]
    }

extractBody data =
    data.body

myExtract =
    extractBody
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: aliased helper in client context - server optimizes body" <|
                \() ->
                    -- When aliased helper accessing only title is used in CLIENT context,
                    -- title is persistent but body is ephemeral (never used)
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myExtract app.data
    , body = [ View.freeze (Html.text "static") ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
"""
                    in
                    -- Server: title is client-used via aliased helper, body is ephemeral
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
    { title = myExtract app.data
    , body = [ View.freeze (Html.text "static") ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
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
    { title = myExtract app.data
    , body = [ View.freeze (Html.text "static") ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
"""
                            , Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text \"static\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myExtract app.data
    , body = [ View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "static") ])) ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: aliased helper in client context - client also optimizes body" <|
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
    { title = myExtract app.data
    , body = [ View.freeze (Html.text "static") ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
"""
                    in
                    -- Client: title is client-used via aliased helper, body is ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.text \"static\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html.Styled as Html
import View
import Html.Lazy
import Html as ElmPages__Html

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = myExtract app.data
    , body = [ (Html.Lazy.lazy (\\_ -> ElmPages__Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

extractTitle data =
    data.title

myExtract =
    extractTitle
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

import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = myExtract app.data
    , body = [ View.freeze (Html.text "static") ]
    }

extractTitle data =
    data.title

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
            ]
        , describe "Helper function forwarding - both agree"
            [ test "AGREEMENT: helper forwards data to another local helper - both optimize" <|
                \() ->
                    -- When a helper function forwards its parameter to another local helper,
                    -- both transforms should track through the delegation
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
    { title = wrapperHelper app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

wrapperHelper data =
    innerHelper data

innerHelper data =
    data.title
"""
                    in
                    -- Server: wrapperHelper -> innerHelper only accesses title, body only in freeze
                    -- Expected: body is ephemeral
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
    { title = wrapperHelper app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

wrapperHelper data =
    innerHelper data

innerHelper data =
    data.title
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
    { title = wrapperHelper app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

wrapperHelper data =
    innerHelper data

innerHelper data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: helper forwards data to another local helper - client also optimizes" <|
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
    { title = wrapperHelper app.data
    , body = []
    }

wrapperHelper data =
    innerHelper data

innerHelper data =
    data.title
"""
                    in
                    -- Client: wrapperHelper -> innerHelper only accesses title, body is ephemeral
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
    { title = wrapperHelper app.data
    , body = []
    }

wrapperHelper data =
    innerHelper data

innerHelper data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":8,\"column\":5},\"end\":{\"row\":10,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Multi-parameter helper - data in second position"
            [ test "AGREEMENT: helper with data in second position - server optimizes" <|
                \() ->
                    -- Helper function where data is in second parameter position
                    -- formatTitle prefix data = prefix ++ data.title
                    -- Both transforms should track that 'title' is accessed via the second param
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
    { title = formatTitle "Hello: " app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

formatTitle prefix data =
    prefix ++ data.title
"""
                    in
                    -- Server: formatTitle accesses title via second param, body only in freeze
                    -- Expected: body is ephemeral
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
    { title = formatTitle "Hello: " app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

formatTitle prefix data =
    prefix ++ data.title
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
    { title = formatTitle "Hello: " app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

formatTitle prefix data =
    prefix ++ data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: helper with data in second position - client optimizes" <|
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
    { title = formatTitle "Hello: " app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

formatTitle prefix data =
    prefix ++ data.title
"""
                    in
                    -- Client: formatTitle accesses title via second param, body only in freeze
                    -- Expected: body is ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = formatTitle "Hello: " app.data
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

formatTitle prefix data =
    prefix ++ data.title
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
    { title = formatTitle "Hello: " app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__\" ] [ Html.text app.data.body ]) ]
    }

formatTitle prefix data =
    prefix ++ data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Helper via pipe operator - both agree"
            [ test "AGREEMENT: app.data |> helperFn - server tracks helper fields" <|
                \() ->
                    -- Forward pipe to helper function: app.data |> renderTitle
                    -- Both transforms should track the helper function's field accesses
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
    { title = app.data |> renderTitle
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                    in
                    -- Server: renderTitle only accesses title, body only in freeze
                    -- Expected: body is ephemeral
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
    { title = app.data |> renderTitle
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
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
    { title = app.data |> renderTitle
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: app.data |> helperFn - client also tracks helper fields" <|
                \() ->
                    -- Same scenario, client transform
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
    { title = app.data |> renderTitle
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                    in
                    -- Client: same field accesses, body should be ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = app.data |> renderTitle
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

renderTitle data =
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data |> renderTitle
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: helperFn <| app.data - server tracks helper fields" <|
                \() ->
                    -- Backward pipe to helper function: renderTitle <| app.data
                    -- Both transforms should track the helper function's field accesses
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
    { title = renderTitle <| app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                    in
                    -- Server: renderTitle only accesses title, body only in freeze
                    -- Expected: body is ephemeral
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
    { title = renderTitle <| app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
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
    { title = renderTitle <| app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: helperFn <| app.data - client also tracks helper fields" <|
                \() ->
                    -- Same scenario, client transform
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
    { title = renderTitle <| app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                    in
                    -- Client: same field accesses, body should be ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = renderTitle <| app.data
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }

renderTitle data =
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = renderTitle <| app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

renderTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Inline lambda with app.data - both agree"
            [ test "AGREEMENT: inline lambda (\\d -> d.title) app.data tracks title field" <|
                \() ->
                    -- Inline lambda analyzing which fields it accesses
                    -- Expected: Both transforms mark body as ephemeral (only title used in client context)
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
    { title = (\\d -> d.title) app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral
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
import Html.Styled as Html
import View
import Html.Lazy

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
    { title = (\\d -> d.title) app.data
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
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = (\\d -> d.title) app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: inline lambda via pipe app.data |> (\\d -> d.title) tracks title field" <|
                \() ->
                    -- Inline lambda with pipe operator
                    -- Expected: Both transforms mark body as ephemeral (only title used in client context)
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
    { title = app.data |> (\\d -> d.title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral
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
import Html.Styled as Html
import View
import Html.Lazy

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
    { title = app.data |> (\\d -> d.title)
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
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data |> (\\d -> d.title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            ]
        , describe "Let-bound helper functions - both agree"
            [ test "AGREEMENT: let-bound helper with data parameter - server optimizes" <|
                \() ->
                    -- Helper function defined in let expression: let extractTitle data = data.title
                    -- Both transforms should track that the helper uses 'title'
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
    let
        extractTitle data =
            data.title
    in
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral (extractTitle uses only title)
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
    let
        extractTitle data =
            data.title
    in
    { title = extractTitle app.data
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
    let
        extractTitle data =
            data.title
    in
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: let-bound helper with record destructuring - server optimizes" <|
                \() ->
                    -- Helper with record destructuring: let extractTitle { title } = title
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
    let
        extractTitle { title } =
            title
    in
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
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
    let
        extractTitle { title } =
            title
    in
    { title = extractTitle app.data
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
    let
        extractTitle { title } =
            title
    in
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            ]
        , describe "Nested local function application - both agree"
            [ test "AGREEMENT: nested local function extracting field - server optimizes" <|
                \() ->
                    -- When (extractField app.data) is passed to another function,
                    -- both transforms analyze extractField to see which fields it uses.
                    -- Since extractField only accesses title, body is ephemeral.
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
    { title = String.toUpper (extractTitle app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
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
    { title = String.toUpper (extractTitle app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
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
    { title = String.toUpper (extractTitle app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: nested local function extracting field - client also optimizes" <|
                \() ->
                    -- Client should also track through the nested local function call
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
    { title = String.toUpper (extractTitle app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = String.toUpper (extractTitle app.data)
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = String.toUpper (extractTitle app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Function composition patterns"
            [ test "AGREEMENT: function composition with accessor (.title >> transform) - server optimizes" <|
                \() ->
                    -- When app.data |> (.field >> transform) is used,
                    -- both transforms should track the field access through the composition.
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
    { title = app.data |> (.title >> String.toUpper)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
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
    { title = app.data |> (.title >> String.toUpper)
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
    { title = app.data |> (.title >> String.toUpper)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: function composition with accessor (.title >> transform) - client also optimizes" <|
                \() ->
                    -- Client should also track the field through function composition
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
    { title = app.data |> (.title >> String.toUpper)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = app.data |> (.title >> String.toUpper)
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
    { title = app.data |> (.title >> String.toUpper)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: backward composition with accessor (transform << .title) - server optimizes" <|
                \() ->
                    -- When app.data |> (transform << .field) is used,
                    -- both transforms should track the field access through the composition.
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
    { title = app.data |> (String.toUpper << .title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
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
    { title = app.data |> (String.toUpper << .title)
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
    { title = app.data |> (String.toUpper << .title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: backward composition with accessor (transform << .title) - client also optimizes" <|
                \() ->
                    -- Client should also track the field through backward function composition
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
    { title = app.data |> (String.toUpper << .title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

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
    { title = app.data |> (String.toUpper << .title)
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
    { title = app.data |> (String.toUpper << .title)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Non-conventional head function naming - both agree"
            [ test "AGREEMENT: head = seoTags (defined BEFORE RouteBuilder) - server marks description as ephemeral" <|
                \() ->
                    -- When RouteBuilder uses { head = seoTags } instead of { head = head }
                    -- and seoTags is defined BEFORE the RouteBuilder call,
                    -- both transforms should identify seoTags as the head function
                    -- and mark description as ephemeral (only accessed in head context)
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

seoTags app =
    [ Html.text app.data.description ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Server marks description as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: description"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Ephemeral =
    { title : String
    , description : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

seoTags app =
    [ Html.text app.data.description ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

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

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

seoTags app =
    [ Html.text app.data.description ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                            ]
            , test "AGREEMENT: head = seoTags (defined BEFORE RouteBuilder) - client also marks description as ephemeral" <|
                \() ->
                    -- The key agreement check: client's EPHEMERAL_FIELDS_JSON matches server's ["description"]
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    }

seoTags app =
    [ Html.text app.data.description ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Client marks description as ephemeral (same as server)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String }

seoTags app =
    [ Html.text app.data.description ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":11,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: head = seoTags (defined AFTER RouteBuilder) - server marks description as ephemeral" <|
                \() ->
                    -- Same as above but seoTags is defined AFTER the RouteBuilder call
                    -- Both transforms should still correctly identify seoTags as the head function
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Server marks description as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: description"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Ephemeral =
    { title : String
    , description : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

seoTags app =
    [ Html.text app.data.description ]

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

import Html
import Html.Attributes
import View
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                            ]
            , test "AGREEMENT: head = seoTags (defined AFTER RouteBuilder) - client also marks description as ephemeral" <|
                \() ->
                    -- The key agreement check: client's EPHEMERAL_FIELDS_JSON matches server's ["description"]
                    -- When seoTags is defined AFTER RouteBuilder, the client can stub out the head function
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Client marks description as ephemeral (same as server)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Head function codemod: stub out for client bundle"
                                , details =
                                    [ "Replacing head function body with [] because Data fields are being removed."
                                    , "The head function never runs on the client (it's for SEO at build time), so stubbing it out allows DCE."
                                    ]
                                , under = "[ Html.text app.data.description ]"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":11,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: head = seoTags accessing multiple fields - server marks all as ephemeral" <|
                \() ->
                    -- When the non-conventionally named head function accesses multiple fields,
                    -- both transforms should mark ALL of those fields as ephemeral
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    , ogImage : String
    }

seoTags app =
    [ Html.text app.data.description
    , Html.text app.data.ogImage
    ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Server marks description AND ogImage as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: description, ogImage"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , description : String
    , ogImage : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Ephemeral =
    { title : String
    , description : String
    , ogImage : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

seoTags app =
    [ Html.text app.data.description
    , Html.text app.data.ogImage
    ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

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

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    , ogImage : String
    }

seoTags app =
    [ Html.text app.data.description
    , Html.text app.data.ogImage
    ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\",\"ogImage\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , description : String
    , ogImage : String
    }"""
                                }
                            ]
            , test "AGREEMENT: head = seoTags accessing multiple fields - client also marks all as ephemeral" <|
                \() ->
                    -- The key agreement check: client's EPHEMERAL_FIELDS_JSON matches server's ["description", "ogImage"]
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String
    , description : String
    , ogImage : String
    }

seoTags app =
    [ Html.text app.data.description
    , Html.text app.data.ogImage
    ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Client marks description AND ogImage as ephemeral (same as server)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: description, ogImage"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , description : String
    , ogImage : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
import RouteBuilder

type alias Data =
    { title : String }

seoTags app =
    [ Html.text app.data.description
    , Html.text app.data.ogImage
    ]

route =
    RouteBuilder.preRender
        { head = seoTags
        , pages = pages
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\",\"ogImage\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":11,\"column\":5},\"end\":{\"row\":14,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: head = lambda function - server marks description as ephemeral" <|
                \() ->
                    -- When RouteBuilder uses { head = \app -> [...] } with an inline lambda,
                    -- both transforms should handle it correctly
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Server marks description as ephemeral
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: description"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View
import RouteBuilder

type alias Ephemeral =
    { title : String
    , description : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

route =
    RouteBuilder.preRender
        { head = \\app -> [ Html.text app.data.description ]
        , pages = pages
        , data = data
        }

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

import Html
import Html.Attributes
import View
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , description : String
    }"""
                                }
                            ]
            , test "AGREEMENT: head = lambda function - client also marks description as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                    in
                    -- Client marks description as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
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

view app =
    { title = app.data.title
    , body = []
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"description\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":11,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "View module alias import - both agree"
            [ test "AGREEMENT: import View as V with V.freeze - server marks body as ephemeral" <|
                \() ->
                    -- When View is imported with an alias (import View as V),
                    -- both transforms should correctly identify V.freeze as View.freeze
                    -- and mark body as ephemeral (only accessed inside freeze)
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View as V

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ V.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral
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
import View as V

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
    , body = [ V.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
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
import View as V

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ V.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: import View as V with V.freeze - client also marks body as ephemeral" <|
                \() ->
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View as V
import Html.Lazy

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ V.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                    in
                    -- Client marks body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "V.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text app.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View as V
import Html.Lazy
type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = app.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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
import View as V
import Html.Lazy

type alias Data =
    { title : String }

view app =
    { title = app.data.title
    , body = [ V.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Non-conventional parameter names - both agree"
            [ test "AGREEMENT: view function with props parameter - server marks body as ephemeral" <|
                \() ->
                    -- When the view function uses a non-conventional name like 'props'
                    -- instead of 'app' or 'static', both transforms should identify it
                    -- and track field access correctly
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

view props =
    { title = props.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text props.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral
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

view props =
    { title = props.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text props.data.body ]) ]
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

view props =
    { title = props.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text props.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: view function with props parameter - client also marks body as ephemeral" <|
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

view props =
    { title = props.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text props.data.body ]) ]
    }
"""
                    in
                    -- Client marks body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text props.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
type alias Data =
    { title : String
    , body : String
    }

view props =
    { title = props.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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

view props =
    { title = props.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text props.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: view function with context parameter - server marks body as ephemeral" <|
                \() ->
                    -- Similar test with 'context' as parameter name
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

view context =
    { title = context.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text context.data.body ]) ]
    }
"""
                    in
                    -- Server marks body as ephemeral
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

view context =
    { title = context.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text context.data.body ]) ]
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

view context =
    { title = context.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text context.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: view function with context parameter - client also marks body as ephemeral" <|
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

view context =
    { title = context.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text context.data.body ]) ]
    }
"""
                    in
                    -- Client marks body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text context.data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
type alias Data =
    { title : String
    , body : String
    }

view context =
    { title = context.data.title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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

view context =
    { title = context.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text context.data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Record pattern with alias in app parameter - both agree"
            [ test "AGREEMENT: view ({ data } as app) pattern - server marks body as ephemeral" <|
                \() ->
                    -- When the view function uses a record pattern with alias like
                    -- ({ data } as app), both transforms correctly track field access
                    -- through the destructured 'data' binding as app.data access.
                    -- data.title in client context → title is persistent
                    -- data.body in freeze → body is ephemeral
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text data.body ]) ]
    }
"""
                    in
                    -- Server marks only body as ephemeral (title is used in client context)
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text data.body ]) ]
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    }"""
                                }
                            ]
            , test "AGREEMENT: view ({ data } as app) pattern - client also marks body as ephemeral" <|
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text data.body ]) ]
    }
"""
                    in
                    -- Client also marks only body as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text data.body ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
type alias Data =
    { title : String
    , body : String
    }

view ({ data } as app) =
    { title = data.title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text data.body ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            , test "AGREEMENT: view ({ data } as app) with mixed access - server optimizes" <|
                \() ->
                    -- Test using both data.field and app.data.field in same function
                    -- Both should be tracked correctly
                    let
                        testModule =
                            """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    , extra : String
    }

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (data.body ++ app.data.extra) ]) ]
    }
"""
                    in
                    -- Server marks body and extra as ephemeral (title is client-used)
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: body, extra"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , extra : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Ephemeral =
    { title : String
    , body : String
    , extra : String
    }


type alias Data =
    { title : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { title = ephemeral.title
    }

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (data.body ++ app.data.extra) ]) ]
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
    , extra : String
    }

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (data.body ++ app.data.extra) ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"extra\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { title : String
    , body : String
    , extra : String
    }"""
                                }
                            ]
            , test "AGREEMENT: view ({ data } as app) with mixed access - client also optimizes" <|
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
    , extra : String
    }

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (data.body ++ app.data.extra) ]) ]
    }
"""
                    in
                    -- Client marks body and extra as ephemeral (title is client-used)
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Html.div [ Html.Attributes.attribute \"data-static\" \"__STATIC__\" ] [ Html.text (data.body ++ app.data.extra) ])"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import Html.Styled as Html
import View
import Html.Lazy
type alias Data =
    { title : String
    , body : String
    , extra : String
    }

view ({ data } as app) =
    { title = data.title
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.map never) ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: body, extra"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ title : String
    , body : String
    , extra : String
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

view ({ data } as app) =
    { title = data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text (data.body ++ app.data.extra) ]) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\",\"extra\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":10,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Static-regions pattern - elm-css with exposing"
            [ test "AGREEMENT: elm-css with multiple freeze calls and exposed functions" <|
                \() ->
                    -- This matches the static-regions Route/Index.elm pattern:
                    -- - Html.Styled exposing (div, text)
                    -- - Multiple View.freeze calls
                    -- - Fields only used inside freeze should be ephemeral
                    let
                        testModule =
                            """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                    in
                    -- Server should mark greeting and portGreeting as ephemeral
                    -- because they're only used inside View.freeze
                    -- now should be persistent (used outside freeze)
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (div [] [ text <| \"Greeting: \" ++ app.data.greeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (div [] [ text <| "Greeting: " ++ app.data.greeting ]) ]))
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (div [] [ text <| \"Port Greeting: \" ++ app.data.portGreeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ]) ]))
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: split Data into Ephemeral and Data"
                                , details =
                                    [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                                    , "Ephemeral fields: greeting, portGreeting"
                                    , "Generating ephemeralToData conversion function for wire encoding."
                                    ]
                                , under = """type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy

type alias Ephemeral =
    { greeting : String
    , portGreeting : String
    , now : String
    }


type alias Data =
    { now : String
    }


ephemeralToData : Ephemeral -> Data
ephemeralToData ephemeral =
    { now = ephemeral.now
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
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
                                |> Review.Test.atExactly { start = { row = 1, column = 30 }, end = { row = 1, column = 34 } }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, Ephemeral, ephemeralToData, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Index\",\"ephemeralFields\":[\"greeting\",\"portGreeting\"]}"
                                , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
                                , under = """type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }"""
                                }
                            ]
            , test "AGREEMENT: client also marks greeting/portGreeting as ephemeral" <|
                \() ->
                    -- Same module as above - client should ALSO mark greeting/portGreeting as ephemeral
                    let
                        testModule =
                            """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                    in
                    -- Client should also mark greeting and portGreeting as ephemeral
                    testModule
                        |> Review.Test.run StaticViewTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (div [] [ text <| \"Greeting: \" ++ app.data.greeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import Html as ElmPages__Html

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , (Html.Lazy.lazy (\\_ -> ElmPages__Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> Html.Styled.map never)
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (div [] [ text <| \"Port Greeting: \" ++ app.data.portGreeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import Html as ElmPages__Html

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , (Html.Lazy.lazy (\\_ -> ElmPages__Html.text "") "__ELM_PAGES_STATIC__1" |> View.htmlToFreezable |> Html.Styled.map never)
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "Data type codemod: remove non-client-used fields"
                                , details =
                                    [ "Removing fields from Data type: greeting, portGreeting"
                                    , "These fields are not used in client contexts (only in freeze/head), so they can be eliminated from the client bundle."
                                    ]
                                , under = """{ greeting : String
    , portGreeting : String
    , now : String
    }"""
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy

type alias Data =
    { now : String }

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Index\",\"ephemeralFields\":[\"greeting\",\"portGreeting\"],\"newDataType\":\"{ now : String }\",\"range\":{\"start\":{\"row\":9,\"column\":5},\"end\":{\"row\":12,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
            ]
        , describe "Data used as constructor - must skip optimization on BOTH sides"
            [ test "AGREEMENT: when Data is used as constructor (map4 Data), BOTH transforms skip optimization" <|
                \() ->
                    -- When Data is used as a record constructor function (e.g., map4 Data),
                    -- BOTH server and client must skip the ephemeral field optimization.
                    -- Client can't narrow Data type without breaking the constructor call.
                    -- Server must agree to ensure the wire format matches what client expects.
                    let
                        testModule =
                            """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import BackendTask

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

data =
    BackendTask.map3 Data
        (BackendTask.succeed "hello")
        (BackendTask.succeed "world")
        (BackendTask.succeed "now")

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                    in
                    -- SERVER should skip optimization because Data is used as constructor
                    -- This ensures agreement with client which also skips
                    testModule
                        |> Review.Test.run ServerDataTransform.rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (div [] [ text <| \"Greeting: \" ++ app.data.greeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import BackendTask
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

data =
    BackendTask.map3 Data
        (BackendTask.succeed "hello")
        (BackendTask.succeed "world")
        (BackendTask.succeed "now")

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (div [] [ text <| "Greeting: " ++ app.data.greeting ]) ]))
        , View.freeze (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ])
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (div [] [ text <| \"Port Greeting: \" ++ app.data.portGreeting ])"
                                }
                                |> Review.Test.whenFixed """module Route.Index exposing (Data, route)

import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes exposing (href)
import View
import Html.Lazy
import BackendTask
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { greeting : String
    , portGreeting : String
    , now : String
    }

data =
    BackendTask.map3 Data
        (BackendTask.succeed "hello")
        (BackendTask.succeed "world")
        (BackendTask.succeed "now")

view app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , View.freeze (div [] [ text <| "Greeting: " ++ app.data.greeting ])
        , View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (div [] [ text <| "Port Greeting: " ++ app.data.portGreeting ]) ]))
        , div [] [ text <| "Now: " ++ app.data.now ]
        ]
    }
"""
                            -- NO ephemeral field errors should appear because Data is used as constructor!
                            -- Server must skip optimization to agree with client
                            ]
            ]
        ]
