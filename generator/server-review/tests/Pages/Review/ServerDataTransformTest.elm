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
                                    [ "Wrapping View.freeze argument with data-static attribute for static region extraction."
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text "hello" ]) ]
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
    , body = [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text "hello" ]) ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "wraps multiple View.freeze calls with sequential indices" <|
                \() ->
                    -- Multiple freeze calls should get unique __STATIC__ markers
                    -- (the placeholder is the same, but extract-static-regions.js assigns indices)
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
                                    [ "Wrapping View.freeze argument with data-static attribute for static region extraction."
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
        [ View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text "first" ])
        , View.freeze (Html.text "second")
        ]
    }
"""
                            , Review.Test.error
                                { message = "Server codemod: wrap freeze argument with data-static"
                                , details =
                                    [ "Wrapping View.freeze argument with data-static attribute for static region extraction."
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
        , View.freeze (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ Html.text "second" ])
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
                                    [ "Wrapping View.freeze argument with data-static attribute for static region extraction."
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
    , body = [ View.freeze (H.div [ Attr.attribute "data-static" "__STATIC__" ] [ H.text "hello" ]) ]
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
                            ]
            ]
        ]
