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
        , describe "Model reference detection"
            [ test "errors on model.field inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text model.count) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Model referenced inside View.freeze"
                                , details =
                                    [ "Frozen content is rendered at build time when no model state exists."
                                    , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                    , "To fix this, either:"
                                    , "1. Move the model-dependent content outside of `View.freeze`, or"
                                    , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                    ]
                                , under = "model.count"
                                }
                            ]
            , test "errors on model |> .field inside freeze (complex example)" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text (model |> .count |> String.fromInt)) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Accessor on model inside View.freeze"
                                , details =
                                    [ "Frozen content is rendered at build time when no model state exists."
                                    , "Using `model |> .field` inside `View.freeze` accesses model data that won't exist at build time."
                                    , "To fix this, move the model-dependent content outside of `View.freeze`."
                                    ]
                                , under = "model"
                                }
                                |> Review.Test.atExactly { start = { row = 7, column = 35 }, end = { row = 7, column = 40 } }
                            ]
            , test "errors on case model of inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (case model of
                              _ -> text "hello") ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Pattern match on model inside View.freeze"
                                , details =
                                    [ "Frozen content is rendered at build time when no model state exists."
                                    , "Using `case model of` inside `View.freeze` depends on model data that won't exist at build time."
                                    , "To fix this, move the model-dependent content outside of `View.freeze`."
                                    ]
                                , under = "model"
                                }
                                |> Review.Test.atExactly { start = { row = 7, column = 34 }, end = { row = 7, column = 39 } }
                            ]
            , test "allows model outside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (div, text)

view app shared model =
    { body =
        [ View.freeze (text app.data.title)
        , div [] [ text model.count ]
        ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "Runtime app field detection"
            [ test "errors on app.action inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text app.action) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Runtime field `action` accessed inside View.freeze"
                                , details =
                                    [ "`app.action` is runtime-only data that doesn't exist at build time."
                                    , "Frozen content is rendered once at build time, so runtime fields like `action`, `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                    , "To fix this, either:"
                                    , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                    , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.sharedData`, `app.routeParams`, `app.path`"
                                    ]
                                , under = "app.action"
                                }
                            ]
            , test "errors on app.navigation inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text (Debug.toString app.navigation)) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Runtime field `navigation` accessed inside View.freeze"
                                , details =
                                    [ "`app.navigation` is runtime-only data that doesn't exist at build time."
                                    , "Frozen content is rendered once at build time, so runtime fields like `action`, `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                    , "To fix this, either:"
                                    , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                    , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.sharedData`, `app.routeParams`, `app.path`"
                                    ]
                                , under = "app.navigation"
                                }
                            ]
            , test "errors on model |> .field (simple pipe) inside freeze" <|
                \() ->
                    -- Test that model |> .field is caught
                    """module Route.Index exposing (view)

import View

view app shared model =
    View.freeze (model |> .count)
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectErrors
                            [ Review.Test.error
                                { message = "Accessor on model inside View.freeze"
                                , details =
                                    [ "Frozen content is rendered at build time when no model state exists."
                                    , "Using `model |> .field` inside `View.freeze` accesses model data that won't exist at build time."
                                    , "To fix this, move the model-dependent content outside of `View.freeze`."
                                    ]
                                , under = "model"
                                }
                                |> Review.Test.atExactly { start = { row = 6, column = 18 }, end = { row = 6, column = 23 } }
                            ]
            , test "allows app.data inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text app.data.title) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "allows app.sharedData inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text app.sharedData.siteName) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "allows app.routeParams inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text app.routeParams.slug) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "allows app.path inside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    { body = [ View.freeze (text (app.path |> Pages.Url.toString)) ] }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            , test "allows runtime fields outside freeze" <|
                \() ->
                    """module Route.Index exposing (view)

import View
import Html exposing (div, text)

view app shared model =
    { body =
        [ View.freeze (text app.data.title)
        , div [] [ text (Debug.toString app.action) ]
        ]
    }
"""
                        |> Review.Test.run rule
                        |> Review.Test.expectNoErrors
            ]
        ]
