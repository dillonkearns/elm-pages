module Pages.Review.StaticRegionScopeTest exposing (all)

import Pages.Review.StaticRegionScope exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Pages.Review.StaticRegionScope"
        [ describe "View.static"
            [ test "allows View.static in Route modules" <|
                \() ->
                    """module Route.Index exposing (view)

import View

view =
    View.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.static in non-Route modules" <|
                \() ->
                    """module Shared exposing (view)

import View

view =
    View.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.static` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.static"
                                }
                            ]
            , test "errors on View.static in helper modules" <|
                \() ->
                    """module Helpers.Views exposing (staticContent)

import View

staticContent =
    View.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.static` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.static"
                                }
                            ]
            ]
        , describe "View.staticView"
            [ test "allows View.staticView in Route modules" <|
                \() ->
                    """module Route.Blog.Slug_ exposing (view)

import View

view app =
    View.staticView app.staticData renderContent
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.staticView in non-Route modules" <|
                \() ->
                    """module Components.Article exposing (view)

import View

view staticData =
    View.staticView staticData renderContent
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.staticView` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.staticView"
                                }
                            ]
            ]
        , describe "View.staticBackendTask"
            [ test "allows View.staticBackendTask in Route modules" <|
                \() ->
                    """module Route.Index exposing (staticData)

import View

staticData =
    View.staticBackendTask parseMarkdown
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.staticBackendTask in non-Route modules" <|
                \() ->
                    """module Data.Content exposing (loadContent)

import View

loadContent =
    View.staticBackendTask parseMarkdown
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.staticBackendTask` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.staticBackendTask"
                                }
                            ]
            ]
        , describe "View.renderStatic"
            [ test "allows View.renderStatic in Route modules" <|
                \() ->
                    """module Route.Index exposing (view)

import View

view =
    View.renderStatic "id" content
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on View.renderStatic in non-Route modules" <|
                \() ->
                    """module Shared exposing (view)

import View

view =
    View.renderStatic "id" content
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.renderStatic` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.renderStatic"
                                }
                            ]
            ]
        , describe "View.Static module functions"
            [ test "allows View.Static.view in Route modules" <|
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
            , test "errors on View.Static.backendTask in non-Route modules" <|
                \() ->
                    """module Data.Loader exposing (loadContent)

import View.Static

loadContent =
    View.Static.backendTask parseMarkdown
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.Static.backendTask` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.Static.backendTask"
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
            , test "allows static regions in deeply nested Route modules" <|
                \() ->
                    """module Route.Blog.Category.Slug_ exposing (view)

import View

view =
    View.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "errors on Route module without submodule (Route is not enough)" <|
                \() ->
                    """module Route exposing (view)

import View

view =
    View.static (Html.text "hello")
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Static region function called outside Route module"
                                , details =
                                    [ "`View.static` can only be called from Route modules (Route.Index, Route.Blog.Slug_, etc.)."
                                    , "Static regions are transformed by elm-review during the build, and this transformation only works for Route modules. Calling static region functions from other modules will NOT eliminate heavy dependencies from the client bundle."
                                    , "To fix this, either:"
                                    , "1. Move this code to a Route module, or"
                                    , "2. Pass the static content as a parameter from the Route module"
                                    ]
                                , under = "View.static"
                                }
                            ]
            ]
        ]
