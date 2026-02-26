module CrossModuleHelperFieldTrackingTest exposing (all)

import Pages.Review.ServerDataTransform as ServerDataTransform
import Pages.Review.StaticViewTransform as StaticViewTransform
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Cross-module helper field tracking"
        [ test "server marks only freeze-only helper field as ephemeral" <|
            \() ->
                [ """module Helpers exposing (titleFromData, bodyFromData)

import Html

titleFromData data =
    data.title

bodyFromData data =
    Html.text data.body
"""
                , """module Route.Test exposing (Data, route)

import Helpers
import Html
import Html.Attributes
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = Helpers.titleFromData app.data
    , body =
        [ View.freeze
            (View.htmlToFreezable
                (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Helpers.bodyFromData app.data) ])
            )
        ]
    }
"""
                ]
                    |> Review.Test.runOnModules ServerDataTransform.rule
                    |> Review.Test.expectErrorsForModules
                        [ ( "Route.Test"
                          , [ Review.Test.error
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
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, Ephemeral, ephemeralToData, route)

import Helpers
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
    { title = Helpers.titleFromData app.data
    , body =
        [ View.freeze
            (View.htmlToFreezable
                (Html.div [ Html.Attributes.attribute "data-static" "__STATIC__" ] [ View.freezableToHtml (Helpers.bodyFromData app.data) ])
            )
        ]
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
                          )
                        ]
        , test "client marks only freeze-only helper field as ephemeral" <|
            \() ->
                [ """module Helpers exposing (titleFromData, bodyFromData)

import Html.Styled as Html

titleFromData data =
    data.title

bodyFromData data =
    Html.text data.body
"""
                , """module Route.Test exposing (Data, route)

import Helpers
import Html
import Html.Attributes
import Html.Styled as Html
import Html.Lazy
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = Helpers.titleFromData app.data
    , body = [ View.freeze (Helpers.bodyFromData app.data) ]
    }
"""
                ]
                    |> Review.Test.runOnModules StaticViewTransform.rule
                    |> Review.Test.expectErrorsForModules
                        [ ( "Route.Test"
                          , [ Review.Test.error
                                { message = "Frozen view codemod: transform View.freeze to inlined lazy thunk"
                                , details = [ "Transforms View.freeze to inlined lazy thunk for client-side adoption and DCE" ]
                                , under = "View.freeze (Helpers.bodyFromData app.data)"
                                }
                                |> Review.Test.whenFixed """module Route.Test exposing (Data, route)

import Helpers
import Html
import Html.Attributes
import Html.Styled as Html
import Html.Lazy
import View

type alias Data =
    { title : String
    , body : String
    }

view app =
    { title = Helpers.titleFromData app.data
    , body = [ (Html.Lazy.lazy (\\_ -> Html.text "") "__ELM_PAGES_STATIC__0" |> View.htmlToFreezable |> View.freeze) ]
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

import Helpers
import Html
import Html.Attributes
import Html.Styled as Html
import Html.Lazy
import View

type alias Data =
    { title : String }

view app =
    { title = Helpers.titleFromData app.data
    , body = [ View.freeze (Helpers.bodyFromData app.data) ]
    }
"""
                            , Review.Test.error
                                { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Test\",\"ephemeralFields\":[\"body\"],\"newDataType\":\"{ title : String }\",\"range\":{\"start\":{\"row\":11,\"column\":5},\"end\":{\"row\":13,\"column\":6}}}"
                                , details = [ "This is machine-readable output for the build system." ]
                                , under = "m"
                                }
                                |> Review.Test.atExactly { start = { row = 1, column = 1 }, end = { row = 1, column = 2 } }
                            ]
                          )
                        ]
        ]
