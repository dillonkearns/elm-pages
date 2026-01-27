module Pages.Review.StaticRegionScopeTest exposing (all)

import Pages.Review.StaticRegionScope exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Pages.Review.StaticRegionScope"
        [ describe "View.freeze"
            [ test "allows View.freeze in Route modules" <|
                \() ->
                    """module Route.Index exposing (view)

import View

view =
    View.freeze (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.freeze in non-Route modules" <|
                \() ->
                    """module Shared exposing (view)

import View

view =
    View.freeze (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.freeze` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.freeze"
                                }
                            ]
            , test "errors on View.freeze in helper modules" <|
                \() ->
                    """module Helpers.Views exposing (staticContent)

import View

staticContent =
    View.freeze (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.freeze` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.freeze"
                                }
                            ]
            ]
        , describe "View.freeze with data"
            [ test "allows View.freeze with data in Route modules" <|
                \() ->
                    """module Route.Blog.Slug_ exposing (view)

import View

view app =
    View.freeze (renderContent app.data)
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.freeze with data in non-Route modules" <|
                \() ->
                    """module Components.Article exposing (view)

import View

view data =
    View.freeze (renderContent data)
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.freeze` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.freeze"
                                }
                            ]
            ]
        , describe "View.Static module functions"
            [ test "allows View.Static.static in Route modules" <|
                \() ->
                    """module Route.Index exposing (view)

import View.Static

view =
    View.Static.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.Static.static in non-Route modules" <|
                \() ->
                    """module Components.Article exposing (view)

import View.Static

view =
    View.Static.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.Static.static` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.Static.static"
                                }
                            ]
            , test "allows View.Static.view in Route modules" <|
                \() ->
                    """module Route.Index exposing (view)

import View.Static

view app =
    View.Static.view app.staticData renderContent
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.Static.view in non-Route modules" <|
                \() ->
                    """module Components.Article exposing (view)

import View.Static

view staticData =
    View.Static.view staticData renderContent
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.Static.view` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.Static.view"
                                }
                            ]
            ]
        , describe "Edge cases"
            [ test "allows non-static View functions in non-Route modules" <|
                \() ->
                    """module Shared exposing (view)

import View

view =
    View.map identity myView
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "allows freeze in deeply nested Route modules" <|
                \() ->
                    """module Route.Blog.Category.Slug_ exposing (view)

import View

view =
    View.freeze (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on Route module without submodule (Route is not enough)" <|
                \() ->
                    """module Route exposing (view)

import View

view =
    View.freeze (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.freeze` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.freeze"
                                }
                            ]
            ]
        ]
