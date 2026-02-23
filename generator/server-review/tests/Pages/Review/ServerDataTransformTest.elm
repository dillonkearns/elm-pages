module Pages.Review.ServerDataTransformTest exposing (all)

{-| Tests for ServerDataTransform - focuses on the safe fallback behavior.

The key behavior we want to verify is that app.data passed as a whole
in client context marks all fields as persistent (safe fallback),
preventing incorrect ephemeral field detection.

-}

import Pages.Review.ServerDataTransform exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "ServerDataTransform"
        [ describe "No transformation cases - safe fallback behavior"
            [ test "field used in both freeze and outside is persistent - no transformation" <|
                \() ->
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
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
                        |> Review.Test.run rule
                        -- title is accessed both inside freeze and outside, so it's persistent
                        -- No ephemeral fields, so no transformation
                        |> Review.Test.expectNoErrors
            , test "app.data passed to trackable helper allows optimization" <|
                \() ->
                    -- When app.data is passed to a TRACKABLE helper function in CLIENT context,
                    -- we analyze the helper to determine which fields it uses.
                    -- extractTitle only accesses 'title', so 'body' can be ephemeral.
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = extractTitle app.data
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

extractTitle data =
    data.title
"""
                        |> Review.Test.run rule
                        -- extractTitle only uses 'title' field, so 'body' can be ephemeral
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
    { title = extractTitle app.data
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
    { title = extractTitle app.data
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
            , test "app.data in list passed to function marks all fields persistent" <|
                \() ->
                    -- When [ app.data ] is passed to a function outside freeze,
                    -- we can't track which fields are used, so all are persistent
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
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
                        |> Review.Test.run rule
                        -- All fields marked as persistent (safe fallback)
                        |> Review.Test.expectNoErrors
            , test "app.data in tuple passed to function marks all fields persistent" <|
                \() ->
                    -- When ( app.data, x ) is passed to a function outside freeze,
                    -- we can't track which fields are used, so all are persistent
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = someHelper ( app.data, "extra" )
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

someHelper pair = ""
"""
                        |> Review.Test.run rule
                        -- All fields marked as persistent (safe fallback)
                        |> Review.Test.expectNoErrors
            , test "app.data in nested function call marks all fields persistent" <|
                \() ->
                    -- When helper (fn app.data) is called outside freeze,
                    -- we can't track which fields are used
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = helper (transform app.data)
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }

helper x = x
transform d = d
"""
                        |> Review.Test.run rule
                        -- All fields marked as persistent (safe fallback)
                        |> Review.Test.expectNoErrors
            , test "nested local function extracting specific field is trackable" <|
                \() ->
                    -- When (extractField app.data) is passed to another function,
                    -- we can analyze extractField to see which fields it uses.
                    -- If extractField only uses specific fields, the outer function
                    -- only receives those field values (not app.data), so we can optimize.
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
                        |> Review.Test.run rule
                        -- extractTitle only accesses title, so body is ephemeral
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
            , test "skips transformation if Ephemeral type already exists" <|
                \() ->
                    -- If Ephemeral type already exists, transformation was already applied
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
                    """module Route.Test exposing (Data, Ephemeral, route)

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
ephemeralToData e = { title = e.title }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text app.data.body ]) ]
    }
"""
                        |> Review.Test.run rule
                        -- Should not produce any errors because Ephemeral already exists
                        |> Review.Test.expectNoErrors
            ]
        , describe "Non-standard app parameter names"
            [ test "works with 'static' as parameter name instead of 'app'" <|
                \() ->
                    -- Some routes use 'static' instead of 'app' as the parameter name
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view static =
    { title = static.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text static.data.body ]) ]
    }
"""
                        |> Review.Test.run rule
                        -- body should be ephemeral (only in freeze)
                        -- title should be persistent (in client context)
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

view static =
    { title = static.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text static.data.body ]) ]
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

view static =
    { title = static.data.title
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text static.data.body ]) ]
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
        , describe "View.freeze wrapping with data-static"
            [ test "wraps View.freeze argument with data-static div" <|
                \() ->
                    -- The server codemod should wrap View.freeze arguments with
                    -- Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ ... ]
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text "hello") ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text \"hello\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                            ]
            , test "does not wrap already wrapped freeze argument (base case)" <|
                \() ->
                    -- If the freeze argument is already wrapped with data-static,
                    -- we should not wrap it again (prevents infinite loops)
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "wraps multiple View.freeze calls with sequential indices" <|
                \() ->
                    -- Multiple freeze calls should get unique __STATIC__ markers
                    -- (the placeholder is the same, but extract-frozen-views.js assigns indices)
                    """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body =
        [ View.freeze (Html.text "first")
        , View.freeze (Html.text "second")
        ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text \"first\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body =
        [ View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "first") ]))
        , View.freeze (Html.text "second")
        ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text \"second\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body =
        [ View.freeze (Html.text "first")
        , View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "second") ]))
        ]
    }
"""
                            ]
            , test "uses Html alias if imported with alias" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html as H
import Html.Attributes as Attr
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (H.text "hello") ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (H.text \"hello\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html as H
import Html.Attributes as Attr
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (H.div [ Attr.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (H.text "hello") ])) ]
    }
"""
                            ]
            , test "adds Html import when not imported" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze content ]
    }

content = Html.Attributes.attribute "foo" "bar"
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze content"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html.Attributes
import View
import Html as ElmPages__Html

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (content) ])) ]
    }

content = Html.Attributes.attribute "foo" "bar"
"""
                            ]
            , test "adds Html.Attributes import when not imported" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text "hello") ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text \"hello\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View
import Html.Attributes

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                            ]
            , test "adds both Html and Html.Attributes imports when neither imported" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze content ]
    }

content = someHelper "test"
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze content"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import View
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (content) ])) ]
    }

content = someHelper "test"
"""
                            ]
            , test "adds Html import when Html.Styled imported without alias" <|
                \() ->
                    -- Html.Styled is imported but not as "Html", so we need elm/html's Html
                    """module Route.Test exposing (Data, route)

import Html.Styled
import Html.Styled.Attributes
import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.Styled.text "hello") ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.Styled.text \"hello\")"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html.Styled
import Html.Styled.Attributes
import View
import Html as ElmPages__Html
import Html.Attributes

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (View.htmlToFreezable (ElmPages__Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.Styled.text "hello") ])) ]
    }
"""
                            ]
            ]
        , describe "app.data passed inside freeze still allows optimization"
            [ test "app.data passed to helper inside freeze produces transformation" <|
                \() ->
                    -- When app.data is passed to a helper function inside View.freeze,
                    -- we should STILL optimize because the freeze context is ephemeral
                    -- The body field should be ephemeral (not used outside freeze)
                    -- Note: freeze argument is pre-wrapped with data-static to focus on Data/Ephemeral transform
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
                        |> Review.Test.run rule
                        -- body field should be ephemeral (only used inside freeze via helper)
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
            ]
        , describe "Non-conventional head function naming"
            [ test "head = seoTags correctly identifies seoTags as head function" <|
                \() ->
                    -- When RouteBuilder uses { head = seoTags }, the server should correctly
                    -- identify seoTags as the head function and treat fields accessed there as ephemeral.
                    -- This tests that we use routeBuilderHeadFn from shared state, not hardcoded "head".
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
    RouteBuilder.single
        { head = seoTags
        , data = data
        }

seoTags app =
    [ Html.text app.data.description ]

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        -- description is only accessed in seoTags (head function), so it's ephemeral
                        -- title is accessed in view, so it's persistent
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
    RouteBuilder.single
        { head = seoTags
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
    RouteBuilder.single
        { head = seoTags
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
            , test "head = seoTags with seoTags defined BEFORE RouteBuilder" <|
                \() ->
                    -- Same scenario but seoTags is defined BEFORE the RouteBuilder call.
                    -- This verifies the correction mechanism works when we haven't seen RouteBuilder yet.
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
    RouteBuilder.single
        { head = seoTags
        , data = data
        }

view app =
    { title = app.data.title
    , body = []
    }
"""
                        |> Review.Test.run rule
                        -- Same result: description is ephemeral, title is persistent
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
    RouteBuilder.single
        { head = seoTags
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
    RouteBuilder.single
        { head = seoTags
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
            ]
        , describe "Pipeline forms"
            [ test "wraps right-pipe View.freeze argument" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View

view app =
    { title = "title"
    , body = [ Html.text "hello" |> View.freeze ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "Html.text \"hello\" |> View.freeze"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View
import Html.Attributes

view app =
    { title = "title"
    , body = [ (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) |> View.freeze ]
    }
"""
                            ]
            , test "wraps left-pipe View.freeze argument" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View

view app =
    { title = "title"
    , body = [ View.freeze <| Html.text "hello" ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze <| Html.text \"hello\""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View
import Html.Attributes

view app =
    { title = "title"
    , body = [ View.freeze <| (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                            ]
            , test "wraps right-pipe View.freeze argument with parenthesized callee" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View

view app =
    { title = "title"
    , body = [ Html.text "hello" |> (View.freeze) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "Html.text \"hello\" |> (View.freeze)"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View
import Html.Attributes

view app =
    { title = "title"
    , body = [ (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) |> (View.freeze) ]
    }
"""
                            ]
            , test "wraps left-pipe View.freeze argument with parenthesized callee" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View

view app =
    { title = "title"
    , body = [ (View.freeze) <| Html.text "hello" ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "(View.freeze) <| Html.text \"hello\""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View
import Html.Attributes

view app =
    { title = "title"
    , body = [ (View.freeze) <| (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                            ]
            , test "wraps right-pipe unqualified freeze via exposing import" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View exposing (freeze)

view app =
    { title = "title"
    , body = [ Html.text "hello" |> freeze ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "Html.text \"hello\" |> freeze"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View exposing (freeze)
import Html.Attributes

view app =
    { title = "title"
    , body = [ (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) |> freeze ]
    }
"""
                            ]
            , test "wraps left-pipe unqualified freeze via exposing import" <|
                \() ->
                    """module Route.Test exposing (Data, route)

import Html
import View exposing (freeze)

view app =
    { title = "title"
    , body = [ freeze <| Html.text "hello" ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "freeze <| Html.text \"hello\""
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Html
import View exposing (freeze)
import Html.Attributes

view app =
    { title = "title"
    , body = [ freeze <| (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Html.text "hello") ])) ]
    }
"""
                            ]
            ]
        , describe "Non-Route modules should be skipped"
            [ test "Site module with Data type should not be transformed" <|
                \() ->
                    -- Site.elm is not a Route module, so it should be skipped
                    -- even if it has a Data type with unused fields.
                    -- This prevents server/client ephemeral field disagreements.
                    """module Site exposing (config)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)

type alias Data =
    { siteName : String
    }

data : BackendTask FatalError Data
data =
    BackendTask.succeed { siteName = "test" }

config =
    { canonicalUrl = "https://example.com"
    , head = BackendTask.succeed []
    }
"""
                        |> Review.Test.run rule
                        -- Site.elm is not a Route module, so no transformation should occur
                        -- even though siteName is never used in client context
                        |> Review.Test.expectNoErrors
            , test "Shared module Data type should not be transformed (but View.freeze still works)" <|
                \() ->
                    -- Shared.elm is NOT transformed for ephemeral data tracking
                    -- because Shared.Data fields are accessed from Route modules via app.sharedData
                    -- and we can't track cross-module field usage.
                    -- View.freeze in Shared.elm still works for HTML transformation, but
                    -- data fields are not eliminated.
                                    """module Shared exposing (Data, template)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html
import View

type alias Data =
    { userName : String
    , heavyFooterContent : String
    }

data : BackendTask FatalError Data
data =
    BackendTask.succeed { userName = "guest", heavyFooterContent = "markdown" }

view sharedData page model toMsg pageView =
    { title = pageView.title
    , body =
        [ Html.text sharedData.userName
        , View.freeze (Html.text sharedData.heavyFooterContent)
        ]
    }

template =
    {}
"""
                        |> Review.Test.run rule
                        -- View.freeze transformation still happens (wrapping with data-static)
                        -- but NO data type splitting should occur
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                    ]
                                , under = "View.freeze (Html.text sharedData.heavyFooterContent)"
                                }
                                |> Review.Test.whenFixed """module Shared exposing (Data, template)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html
import View
import Html.Attributes

type alias Data =
    { userName : String
    , heavyFooterContent : String
    }

data : BackendTask FatalError Data
data =
    BackendTask.succeed { userName = "guest", heavyFooterContent = "markdown" }

view sharedData page model toMsg pageView =
    { title = pageView.title
    , body =
        [ Html.text sharedData.userName
        , View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" "shared:__STATIC__" ] [ View.freezableToHtml (Html.text sharedData.heavyFooterContent) ]))
        ]
    }

template =
    {}
"""
                            ]
            ]
        , describe "Helper module frozen view IDs"
            [ test "uses deterministic helper FID parameter name based on module and function" <|
                \() ->
                    [ """module UserCard exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "UserCard"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module UserCard exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_usercard_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_usercard_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            ]
            , test "adds helper ID parameter and rewrites two route call sites" <|
                \() ->
                    [ """module UserCard exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module Route.Index exposing (view)

import Html
import UserCard

view app =
    { body =
        [ UserCard.view app.data.alice
        , UserCard.view app.data.bob
        ]
    }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "UserCard"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module UserCard exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_usercard_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_usercard_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "UserCard.view app.data.alice"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Route.Index exposing (view)

import Html
import UserCard

view app =
    { body =
        [ UserCard.view "0" app.data.alice
        , UserCard.view app.data.bob
        ]
    }
"""
                                , Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "UserCard.view app.data.bob"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Route.Index exposing (view)

import Html
import UserCard

view app =
    { body =
        [ UserCard.view app.data.alice
        , UserCard.view "1" app.data.bob
        ]
    }
"""
                                ]
                              )
                            ]
            , test "propagates helper IDs through transitive helper call chains" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module CardWrapper exposing (view)

import Card

view user =
    Card.view user
"""
                    , """module Route.Index exposing (view)

import CardWrapper

view app =
    { body = [ CardWrapper.view app.data.user ] }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Card"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "CardWrapper"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "Card.view user"
                                    }
                                    |> Review.Test.whenFixed
                                        """module CardWrapper exposing (view)

import Card

view elmPagesFid_cardwrapper_view user =
    Card.view (elmPagesFid_cardwrapper_view ++ ":0") user
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "CardWrapper.view app.data.user"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Route.Index exposing (view)

import CardWrapper

view app =
    { body = [ CardWrapper.view "0" app.data.user ] }
"""
                                ]
                              )
                            ]
            , test "reports unsupported repeated helper call context in list.map lambda" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module CardWrapper exposing (view)

import Card

view user =
    Card.view user
"""
                    , """module Route.Index exposing (view)

import CardWrapper

view app =
    { body =
        app.data.users
            |> List.map
                (\\user -> CardWrapper.view user)
    }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Card"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "CardWrapper"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "Card.view user"
                                    }
                                    |> Review.Test.whenFixed
                                        """module CardWrapper exposing (view)

import Card

view elmPagesFid_cardwrapper_view user =
    Card.view (elmPagesFid_cardwrapper_view ++ ":0") user
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: unsupported helper ID seeding in repeated context"
                                    , details =
                                        [ "Cannot auto-seed frozen helper IDs inside lambdas or higher-order iterations (for example List.map)."
                                        , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
                                        ]
                                    , under = "CardWrapper.view user"
                                    }
                                ]
                              )
                            ]
            , test "reports unsupported helper function value usage in list.map" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module CardWrapper exposing (view)

import Card

view user =
    Card.view user
"""
                    , """module Route.Index exposing (view)

import CardWrapper

view app =
    { body =
        app.data.users
            |> List.map CardWrapper.view
    }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Card"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "CardWrapper"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "Card.view user"
                                    }
                                    |> Review.Test.whenFixed
                                        """module CardWrapper exposing (view)

import Card

view elmPagesFid_cardwrapper_view user =
    Card.view (elmPagesFid_cardwrapper_view ++ ":0") user
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: unsupported helper function value or partial application"
                                    , details =
                                        [ "Cannot pass a helper containing View.freeze as a function value or partial application (for example List.map Helper.view)."
                                        , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
                                        ]
                                    , under = "CardWrapper.view"
                                    }
                                ]
                              )
                            ]
            , test "reports unsupported local helper function value usage in list.map" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module Route.Index exposing (view)

import Card

view app =
    let
        renderUser user =
            Card.view user
    in
    { body =
        app.data.users
            |> List.map renderUser
    }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Card"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "Card.view user"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Route.Index exposing (view)

import Card

view app =
    let
        renderUser user =
            Card.view "0" user
    in
    { body =
        app.data.users
            |> List.map renderUser
    }
"""
                                , Review.Test.error
                                    { message = "Server codemod: unsupported helper function value or partial application"
                                    , details =
                                        [ "Cannot pass a helper containing View.freeze as a function value or partial application (for example List.map Helper.view)."
                                        , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
                                        ]
                                    , under = "renderUser"
                                    }
                                    |> Review.Test.atExactly { start = { row = 12, column = 25 }, end = { row = 12, column = 35 } }
                                ]
                              )
                            ]
            , test "reports unsupported helper partial application in list.map" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View

view user =
    View.freeze (Html.text user.name)
"""
                    , """module CardWrapper exposing (view)

import Card

view prefix user =
    Card.view { name = prefix ++ user.name }
"""
                    , """module Route.Index exposing (view)

import CardWrapper

view app =
    { body =
        app.data.users
            |> List.map (CardWrapper.view app.data.prefix)
    }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Card"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                                ]
                              )
                            , ( "CardWrapper"
                              , [ Review.Test.error
                                    { message = "Server codemod: pass frozen ID to helper call"
                                    , details =
                                        [ "Adds a unique frozen ID seed when calling a helper function that contains View.freeze."
                                        ]
                                    , under = "Card.view { name = prefix ++ user.name }"
                                    }
                                    |> Review.Test.whenFixed
                                        """module CardWrapper exposing (view)

import Card

view elmPagesFid_cardwrapper_view prefix user =
    Card.view (elmPagesFid_cardwrapper_view ++ ":0") { name = prefix ++ user.name }
"""
                                ]
                              )
                            , ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Server codemod: unsupported helper function value or partial application"
                                    , details =
                                        [ "Cannot pass a helper containing View.freeze as a function value or partial application (for example List.map Helper.view)."
                                        , "Refactor this helper call to a static call site so each invocation can get a unique frozen ID."
                                        ]
                                    , under = "CardWrapper.view app.data.prefix"
                                    }
                                ]
                              )
                            ]
            , test "reports unsupported helper ID seeding in recursive helper function" <|
                \() ->
                    [ """module CardWrapper exposing (renderMany)

import Html
import View

renderMany users =
    case users of
        [] ->
            []

        user :: rest ->
            [ View.freeze (Html.text user.name)
            , renderMany rest
            ]
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "CardWrapper"
                              , [ Review.Test.error
                                    { message = "Server codemod: wrap freeze argument with data-static"
                                    , details =
                                        [ "Wrapping View.freeze argument with data-static attribute for frozen view extraction."
                                        ]
                                    , under = "View.freeze (Html.text user.name)"
                                    }
                                    |> Review.Test.whenFixed
                                        """module CardWrapper exposing (renderMany)

import Html
import View
import Html.Attributes

renderMany elmPagesFid_cardwrapper_rendermany users =
    case users of
        [] ->
            []

        user :: rest ->
            [ View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_cardwrapper_rendermany ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
            , renderMany rest
            ]
"""
                                , Review.Test.error
                                    { message = "Server codemod: unsupported helper ID seeding in repeated context"
                                    , details =
                                        [ "Cannot auto-seed frozen helper IDs inside recursive helper functions."
                                        , "Refactor recursion so each invocation receives an explicit unique frozen ID seed."
                                        ]
                                    , under = "renderMany rest"
                                    }
                                ]
                              )
                            ]
            , test "idempotent: already wrapped helper freeze and seeded route call produce no errors" <|
                \() ->
                    [ """module Card exposing (view)

import Html
import View
import Html.Attributes

view elmPagesFid_card_view user =
    View.freeze (View.htmlToFreezable (Html.div [ Html.Attributes.attribute "data-static" (elmPagesFid_card_view ++ ":0") ] [ View.freezableToHtml (Html.text user.name) ]))
"""
                    , """module Route.Index exposing (view)

import Card

view app =
    { body = [ Card.view "0" app.data.user ] }
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            ]
        ]
