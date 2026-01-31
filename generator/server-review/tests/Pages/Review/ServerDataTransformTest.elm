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
                    """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    }

view app =
    { title = app.data.title
    , body = [ View.freeze (Html.text app.data.title) ]
    }
"""
                        |> Review.Test.run rule
                        -- title is accessed both inside freeze and outside, so it's persistent
                        -- No ephemeral fields, so no transformation
                        |> Review.Test.expectNoErrors
            , test "app.data passed to helper in client context marks all fields persistent (safe fallback)" <|
                \() ->
                    -- When app.data is passed to a helper function in CLIENT context,
                    -- we can't track which fields are used, so ALL fields are persistent
                    -- This is the key test case that verifies the safe fallback behavior
                    """module Route.Test exposing (Data, route)

import View

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
                        -- All fields marked as persistent (safe fallback)
                        -- No ephemeral fields, so no transformation
                        |> Review.Test.expectNoErrors
            , test "app.data in list passed to function marks all fields persistent" <|
                \() ->
                    -- When [ app.data ] is passed to a function outside freeze,
                    -- we can't track which fields are used, so all are persistent
                    """module Route.Test exposing (Data, route)

import View

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
                        -- All fields marked as persistent (safe fallback)
                        |> Review.Test.expectNoErrors
            , test "app.data in tuple passed to function marks all fields persistent" <|
                \() ->
                    -- When ( app.data, x ) is passed to a function outside freeze,
                    -- we can't track which fields are used, so all are persistent
                    """module Route.Test exposing (Data, route)

import View

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
                        -- All fields marked as persistent (safe fallback)
                        |> Review.Test.expectNoErrors
            , test "app.data in nested function call marks all fields persistent" <|
                \() ->
                    -- When helper (fn app.data) is called outside freeze,
                    -- we can't track which fields are used
                    """module Route.Test exposing (Data, route)

import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = helper (transform app.data)
    , body = [ View.freeze (Html.text app.data.body) ]
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
                    """module Route.Test exposing (Data, Ephemeral, route)

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
    , body = [ View.freeze (Html.text app.data.body) ]
    }
"""
                        |> Review.Test.run rule
                        -- Should not produce any errors because Ephemeral already exists
                        |> Review.Test.expectNoErrors
            ]
        , describe "app.data passed inside freeze still allows optimization"
            [ test "app.data passed to helper inside freeze produces transformation" <|
                \() ->
                    -- When app.data is passed to a helper function inside View.freeze,
                    -- we should STILL optimize because the freeze context is ephemeral
                    -- The body field should be ephemeral (not used outside freeze)
                    """module Route.Test exposing (Data, route)

import View

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
    { title = app.data.title
    , body = [ View.freeze (renderContent app.data) ]
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

import View

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
                            ]
            ]
        ]
