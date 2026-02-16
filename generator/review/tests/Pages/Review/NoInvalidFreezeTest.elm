module Pages.Review.NoInvalidFreezeTest exposing (all)

import Pages.Review.NoInvalidFreeze exposing (rule)
import Review.Test
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Pages.Review.NoInvalidFreeze"
        [ describe "Module scope restrictions"
            [ test "allows View.freeze in Route modules" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text "hello")
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows View.freeze in View module" <|
                \() ->
                    [ """module View exposing (helper)

import Html exposing (text)

helper =
    View.freeze (text "hello")
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows View.freeze in Shared module" <|
                \() ->
                    [ """module Shared exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text "hello")
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "reports View.freeze in helper module" <|
                \() ->
                    [ """module Helpers exposing (frozenContent)

import View
import Html exposing (text)

frozenContent =
    View.freeze (text "hello")
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Helpers"
                              , [ Review.Test.error
                                    { message = "`View.freeze` can only be called from Route modules and Shared.elm"
                                    , details =
                                        [ "`View.freeze` currently has no effect outside of Shared.elm and your Route modules (files in your `app/Route/` directory)."
                                        , "To fix this, either:"
                                        , "1. Use `View.freeze` in a Route Module (it could simply be `View.freeze (myHelperFunction app.data.user)`)"
                                        , "2. Remove this invalid use of `View.freeze`"
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "allows View.freeze in nested Route modules" <|
                \() ->
                    [ """module Route.Blog.Slug_ exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text "hello")
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "Runtime app fields"
            [ test "allows app.action inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text (Debug.toString app.action))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "detects app.navigation inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text (Debug.toString app.navigation))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Runtime field `navigation` accessed inside View.freeze"
                                    , details =
                                        [ "`app.navigation` is runtime-only data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time, so runtime fields like `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                        , "To fix this, either:"
                                        , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                        , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.action`, `app.sharedData`, `app.routeParams`, `app.path`"
                                        ]
                                    , under = "app.navigation"
                                    }
                                ]
                              )
                            ]
            , test "detects app.url inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text (Debug.toString app.url))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Runtime field `url` accessed inside View.freeze"
                                    , details =
                                        [ "`app.url` is runtime-only data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time, so runtime fields like `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                        , "To fix this, either:"
                                        , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                        , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.action`, `app.sharedData`, `app.routeParams`, `app.path`"
                                        ]
                                    , under = "app.url"
                                    }
                                ]
                              )
                            ]
            , test "allows app.data inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text app.data.name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows app.routeParams inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text app.routeParams.slug)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "detects app.submit inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text (Debug.toString app.submit))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Runtime field `submit` accessed inside View.freeze"
                                    , details =
                                        [ "`app.submit` is runtime-only data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time, so runtime fields like `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                        , "To fix this, either:"
                                        , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                        , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.action`, `app.sharedData`, `app.routeParams`, `app.path`"
                                        ]
                                    , under = "app.submit"
                                    }
                                ]
                              )
                            ]
            ]
        , describe "Cross-module taint detection"
            [ test "detects taint through helper function" <|
                \() ->
                    -- With deduplication, only one error per location is reported.
                    -- The cross-module error is reported first (Application visited before RecordAccess).
                    [ """module Helpers exposing (formatUser)

formatUser user =
    user.name
"""
                    , """module Route.Index exposing (view)

import View
import Html exposing (text)
import Helpers

view app shared model =
    View.freeze (text (Helpers.formatUser model.user))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value passed to `formatUser` inside View.freeze"
                                    , details =
                                        [ "This argument depends on `model` or other runtime data, and `formatUser` passes it through to the result."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "model.user"
                                    }
                                ]
                              )
                            ]
            , test "allows helper function with pure argument" <|
                \() ->
                    [ """module Helpers exposing (formatUser)

formatUser user =
    user.name
"""
                    , """module Route.Index exposing (view)

import View
import Html exposing (text)
import Helpers

view app shared model =
    View.freeze (text (Helpers.formatUser app.data.user))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "detects taint through let binding passed to helper" <|
                \() ->
                    -- With deduplication, only one error per location.
                    -- The cross-module error is reported first (Application visited before FunctionOrValue).
                    [ """module Helpers exposing (formatName)

formatName name =
    name
"""
                    , """module Route.Index exposing (view)

import View
import Html exposing (text)
import Helpers

view app shared model =
    let
        userName = model.name
    in
    View.freeze (text (Helpers.formatName userName))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value passed to `formatName` inside View.freeze"
                                    , details =
                                        [ "This argument depends on `model` or other runtime data, and `formatName` passes it through to the result."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "userName"
                                    }
                                    |> Review.Test.atExactly { start = { row = 11, column = 43 }, end = { row = 11, column = 51 } }
                                ]
                              )
                            ]
            ]
        , describe "Local taint detection (same as module rule)"
            [ test "detects let binding taint" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        userName = model.name
    in
    View.freeze (text userName)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `userName` used inside View.freeze"
                                    , details =
                                        [ "`userName` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "userName"
                                    }
                                    |> Review.Test.atExactly { start = { row = 10, column = 23 }, end = { row = 10, column = 31 } }
                                ]
                              )
                            ]
            , test "detects model.field inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text model.name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "model.name"
                                    }
                                ]
                              )
                            ]
            , test "detects shared model param (2nd arg) inside freeze in stateless route" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared =
    View.freeze (text shared.name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "shared.name"
                                    }
                                ]
                              )
                            ]
            , test "detects shared model param (2nd arg) inside freeze in stateful route" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text shared.name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "shared.name"
                                    }
                                ]
                              )
                            ]
            , test "detects taint through record destructuring in let" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        { name } = model
    in
    View.freeze (text name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `name` used inside View.freeze"
                                    , details =
                                        [ "`name` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "name"
                                    }
                                    |> Review.Test.atExactly { start = { row = 10, column = 23 }, end = { row = 10, column = 27 } }
                                ]
                              )
                            ]
            , test "detects taint through chained let bindings" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        user = model.user
        name = user.name
        greeting = "Hello " ++ name
    in
    View.freeze (text greeting)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `greeting` used inside View.freeze"
                                    , details =
                                        [ "`greeting` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "greeting"
                                    }
                                    |> Review.Test.atExactly { start = { row = 12, column = 23 }, end = { row = 12, column = 31 } }
                                ]
                              )
                            ]
            , test "allows pure let bindings inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        staticValue = "Hello"
    in
    View.freeze (text staticValue)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows app.data through let binding" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        name = app.data.name
    in
    View.freeze (text name)
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "Case expressions and pattern matching"
            [ test "detects case on model inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (
        case model of
            { name } -> text name
    )
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Pattern match on model inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Using `case model of` inside `View.freeze` depends on model data that won't exist at build time."
                                        , "To fix this, move the model-dependent content outside of `View.freeze`."
                                        ]
                                    , under = "model"
                                    }
                                    |> Review.Test.atExactly { start = { row = 8, column = 14 }, end = { row = 8, column = 19 } }
                                , Review.Test.error
                                    { message = "Tainted value `name` used inside View.freeze"
                                    , details =
                                        [ "`name` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "name"
                                    }
                                    |> Review.Test.atExactly { start = { row = 9, column = 30 }, end = { row = 9, column = 34 } }
                                ]
                              )
                            ]
            , test "detects case on tainted let binding inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        user = model.user
    in
    View.freeze (
        case user of
            { name } -> text name
    )
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Pattern match on tainted value `user` inside View.freeze"
                                    , details =
                                        [ "`user` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Using `case user of` inside `View.freeze` depends on data that won't exist at build time."
                                        , "To fix this, move the model-dependent content outside of `View.freeze`."
                                        ]
                                    , under = "user"
                                    }
                                    |> Review.Test.atExactly { start = { row = 11, column = 14 }, end = { row = 11, column = 18 } }
                                , Review.Test.error
                                    { message = "Tainted value `name` used inside View.freeze"
                                    , details =
                                        [ "`name` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "name"
                                    }
                                    |> Review.Test.atExactly { start = { row = 12, column = 30 }, end = { row = 12, column = 34 } }
                                ]
                              )
                            ]
            , test "allows case on pure value inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        maybeName = app.data.maybeName
    in
    View.freeze (
        case maybeName of
            Just name -> text name
            Nothing -> text "No name"
    )
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "propagates taint through case branch bindings" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        maybeUser = model.maybeUser
    in
    View.freeze (
        case maybeUser of
            Just user -> text user.name
            Nothing -> text "No user"
    )
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Pattern match on tainted value `maybeUser` inside View.freeze"
                                    , details =
                                        [ "`maybeUser` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Using `case maybeUser of` inside `View.freeze` depends on data that won't exist at build time."
                                        , "To fix this, move the model-dependent content outside of `View.freeze`."
                                        ]
                                    , under = "maybeUser"
                                    }
                                    |> Review.Test.atExactly { start = { row = 11, column = 14 }, end = { row = 11, column = 23 } }
                                , Review.Test.error
                                    { message = "Tainted value `user` used inside View.freeze"
                                    , details =
                                        [ "`user` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "user.name"
                                    }
                                , Review.Test.error
                                    { message = "Tainted value `user` used inside View.freeze"
                                    , details =
                                        [ "`user` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "user"
                                    }
                                    |> Review.Test.atExactly { start = { row = 12, column = 31 }, end = { row = 12, column = 35 } }
                                ]
                              )
                            ]
            ]
        , describe "Let-bound functions"
            [ test "detects taint in let-bound function that captures model" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        greet name = model.greeting ++ name
    in
    View.freeze (text (greet "World"))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `greet` used inside View.freeze"
                                    , details =
                                        [ "`greet` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "greet"
                                    }
                                    |> Review.Test.atExactly { start = { row = 10, column = 24 }, end = { row = 10, column = 29 } }
                                ]
                              )
                            ]
            , test "allows pure let-bound function inside freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        greet name = "Hello " ++ name
    in
    View.freeze (text (greet "World"))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "Pipe expressions"
            [ test "detects accessor on model using pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (text (model |> .name))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Accessor on model inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Using `model |> .field` inside `View.freeze` accesses model data that won't exist at build time."
                                        , "To fix this, move the model-dependent content outside of `View.freeze`."
                                        ]
                                    , under = "model"
                                    }
                                    |> Review.Test.atExactly { start = { row = 7, column = 24 }, end = { row = 7, column = 29 } }
                                ]
                              )
                            ]
            , test "detects accessor on tainted let binding using pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        user = model.user
    in
    View.freeze (text (user |> .name))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `user` used inside View.freeze"
                                    , details =
                                        [ "`user` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "user"
                                    }
                                    |> Review.Test.atExactly { start = { row = 10, column = 24 }, end = { row = 10, column = 28 } }
                                ]
                              )
                            ]
            ]
        , describe "View.freeze inside tainted conditionals"
            [ test "reports error when View.freeze is inside tainted if" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    if model.isVisible then
        View.freeze (text "visible")
    else
        text "hidden"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "reports error when View.freeze is inside tainted case" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    case model.status of
        Active -> View.freeze (text "active")
        Inactive -> text "inactive"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "reports error in nested tainted conditionals" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    if model.a then
        if True then
            View.freeze (text "nested")
        else
            text "other"
    else
        text "outer"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "allows freeze when conditional uses pure data" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    if app.data.showContent then
        View.freeze (text "content")
    else
        text "hidden"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "reports error when let-bound tainted value in condition" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        x = model.y
    in
    if x then
        View.freeze (text "tainted")
    else
        text "other"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "reports error when freeze argument is pure but conditional is tainted" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    if model.flag then
        View.freeze (text app.data.title)
    else
        text ""
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            ]
        , describe "Nested freeze calls"
            [ test "allows nested View.freeze calls" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (View.freeze (text "nested"))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows deeply nested View.freeze calls" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (View.freeze (View.freeze (text "deeply nested")))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "detects tainted value in nested freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (View.freeze (text model.name))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "model.name"
                                    }
                                ]
                              )
                            ]
            , test "allows app.data inside nested freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze (View.freeze (text app.data.name))
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            ]
        , describe "Pipeline expressions with View.freeze"
            [ test "detects model.field inside freeze via right pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    text model.name
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "model.name"
                                    }
                                ]
                              )
                            ]
            , test "detects model.field inside freeze via left pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze <| text model.name
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "model.name"
                                    }
                                ]
                              )
                            ]
            , test "allows pure content via right pipe into View.freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    text app.data.name
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "allows pure content via left pipe from View.freeze" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    View.freeze <| text app.data.name
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectNoErrors
            , test "detects tainted let binding inside freeze via right pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    let
        userName = model.name
    in
    text userName
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value `userName` used inside View.freeze"
                                    , details =
                                        [ "`userName` depends on `model` or other runtime data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "userName"
                                    }
                                    |> Review.Test.atExactly { start = { row = 10, column = 10 }, end = { row = 10, column = 18 } }
                                ]
                              )
                            ]
            , test "reports View.freeze via pipe in helper module" <|
                \() ->
                    [ """module Helpers exposing (frozenContent)

import View
import Html exposing (text)

frozenContent =
    text "hello"
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Helpers"
                              , [ Review.Test.error
                                    { message = "`View.freeze` can only be called from Route modules and Shared.elm"
                                    , details =
                                        [ "`View.freeze` currently has no effect outside of Shared.elm and your Route modules (files in your `app/Route/` directory)."
                                        , "To fix this, either:"
                                        , "1. Use `View.freeze` in a Route Module (it could simply be `View.freeze (myHelperFunction app.data.user)`)"
                                        , "2. Remove this invalid use of `View.freeze`"
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "detects runtime app field inside freeze via right pipe" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    text (Debug.toString app.navigation)
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Runtime field `navigation` accessed inside View.freeze"
                                    , details =
                                        [ "`app.navigation` is runtime-only data that doesn't exist at build time."
                                        , "Frozen content is rendered once at build time, so runtime fields like `navigation`, `pageFormState`, `concurrentSubmissions`, `submit`, and `url` are not available."
                                        , "To fix this, either:"
                                        , "1. Move the runtime-dependent content outside of `View.freeze`, or"
                                        , "2. Only use build-time fields inside `View.freeze`: `app.data`, `app.action`, `app.sharedData`, `app.routeParams`, `app.path`"
                                        ]
                                    , under = "app.navigation"
                                    }
                                ]
                              )
                            ]
            , test "detects cross-module taint inside freeze via right pipe" <|
                \() ->
                    [ """module Helpers exposing (formatUser)

formatUser user =
    user.name
"""
                    , """module Route.Index exposing (view)

import View
import Html exposing (text)
import Helpers

view app shared model =
    text (Helpers.formatUser model.user)
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Tainted value passed to `formatUser` inside View.freeze"
                                    , details =
                                        [ "This argument depends on `model` or other runtime data, and `formatUser` passes it through to the result."
                                        , "Frozen content is rendered once at build time. Values derived from `model` will be stale and won't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use values derived from `app.data` or other build-time data inside `View.freeze`"
                                        ]
                                    , under = "model.user"
                                    }
                                ]
                              )
                            ]
            , test "detects View.freeze via right pipe inside tainted conditional" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text)

view app shared model =
    if model.isVisible then
        text "visible"
            |> View.freeze
    else
        text "hidden"
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "View.freeze inside conditionally-executed code path"
                                    , details =
                                        [ "This View.freeze is inside an if/case that depends on `model`."
                                        , "The server renders at build time with initial model state, but the client may have different state."
                                        , "This can cause server/client mismatch where different freeze indices are rendered."
                                        , "Move the conditional logic outside of View.freeze, or ensure the condition only depends on build-time data."
                                        ]
                                    , under = "View.freeze"
                                    }
                                ]
                              )
                            ]
            , test "detects model inside freeze via chained right pipes" <|
                \() ->
                    [ """module Route.Index exposing (view)

import View
import Html exposing (text, div)
import Html.Attributes exposing (class)

view app shared model =
    text model.name
        |> List.singleton
        |> div [ class "wrapper" ]
        |> View.freeze
"""
                    ]
                        |> Review.Test.runOnModules rule
                        |> Review.Test.expectErrorsForModules
                            [ ( "Route.Index"
                              , [ Review.Test.error
                                    { message = "Model referenced inside View.freeze"
                                    , details =
                                        [ "Frozen content is rendered at build time when no model state exists."
                                        , "Referencing `model` inside a `View.freeze` call would result in stale content that doesn't update when the model changes."
                                        , "To fix this, either:"
                                        , "1. Move the model-dependent content outside of `View.freeze`, or"
                                        , "2. Only use `app.data` fields inside `View.freeze` (data that is available at build time)"
                                        ]
                                    , under = "model.name"
                                    }
                                ]
                              )
                            ]
            ]
        ]
