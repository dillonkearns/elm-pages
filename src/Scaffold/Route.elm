module Scaffold.Route exposing
    ( buildWithLocalState, buildWithSharedState, buildNoState, Builder
    , Type(..)
    , serverRender
    , preRender, single
    , addDeclarations
    , moduleNameCliArg
    )

{-| This module provides some functions for scaffolding code for a new Route Module. It uses [`elm-codegen`'s API](https://package.elm-lang.org/packages/mdgriffith/elm-codegen/latest/) for generating code.

Typically you'll want to use this via the `elm-pages run` CLI command. The default starter template includes a Script that uses these functions, which you can tweak to customize your scaffolding commands.
[Learn more about writing and running elm-pages Scripts for scaffolding](https://elm-pages.com/docs/elm-pages-scripts#scaffolding-a-route-module).

It's typically easiest to modify the `AddRoute` script from the starter template and adjust it to your needs rather than writing one from scratch.


## Initializing the Generator Builder

These functions mirror the `RouteBuilder` API that you use in your Route modules to define your route. The difference is that
instead of defining a route, this is defining a code generator for a Route module.

@docs buildWithLocalState, buildWithSharedState, buildNoState, Builder

@docs Type


## Generating Server-Rendered Pages

@docs serverRender


## Generating pre-rendered pages

@docs preRender, single


## Including Additional elm-codegen Declarations

@docs addDeclarations


## CLI Options Parsing Helpers

@docs moduleNameCliArg

-}

import Cli.Option as Option
import Cli.Validate
import Elm
import Elm.Annotation
import Elm.Declare
import Elm.Op
import Pages.Internal.RoutePattern as RoutePattern


{-| A positional argument for elm-cli-options-parser that does a Regex validation to check that the module name is a valid Elm Route module name.
-}
moduleNameCliArg : Option.Option from String builderState -> Option.Option from (List String) builderState
moduleNameCliArg =
    Option.validate
        (Cli.Validate.regex moduleNameRegex)
        >> Option.map
            (\rawModuleName ->
                rawModuleName |> String.split "."
            )


moduleNameRegex : String
moduleNameRegex =
    "^[A-Z][a-zA-Z0-9_]*(\\.([A-Z][a-zA-Z0-9_]*))*$"


{-| -}
type Type
    = Alias Elm.Annotation.Annotation
    | Custom (List Elm.Variant)


typeToDeclaration : String -> Type -> Elm.Declaration
typeToDeclaration name type_ =
    case type_ of
        Alias annotation ->
            Elm.alias name annotation

        Custom variants ->
            Elm.customType name variants


{-| -}
type Builder
    = ServerRender
        (List Elm.Declaration)
        { data : ( Type, Elm.Expression -> Elm.Expression -> Elm.Expression )
        , action : ( Type, Elm.Expression -> Elm.Expression -> Elm.Expression )
        , head : Elm.Expression -> Elm.Expression
        , moduleName : List String
        }
    | PreRender
        (List Elm.Declaration)
        { data : ( Type, Elm.Expression -> Elm.Expression )
        , pages : Maybe Elm.Expression
        , head : Elm.Expression -> Elm.Expression
        , moduleName : List String
        }


{-| -}
serverRender :
    { data : ( Type, Elm.Expression -> Elm.Expression -> Elm.Expression )
    , action : ( Type, Elm.Expression -> Elm.Expression -> Elm.Expression )
    , head : Elm.Expression -> Elm.Expression
    , moduleName : List String
    }
    -> Builder
serverRender =
    ServerRender []


{-| -}
preRender :
    { data : ( Type, Elm.Expression -> Elm.Expression )
    , pages : Elm.Expression
    , head : Elm.Expression -> Elm.Expression
    , moduleName : List String
    }
    -> Builder
preRender input =
    --let
    --    hasDynamicRouteSegments : Bool
    --    hasDynamicRouteSegments =
    --        RoutePattern.fromModuleName input.moduleName
    --            -- TODO give error if not parseable here
    --            |> Maybe.map RoutePattern.hasRouteParams
    --            |> Maybe.withDefault False
    --in
    PreRender []
        { data = input.data
        , pages =
            input.pages
                |> Elm.withType
                    (throwableTask
                        (Elm.Annotation.list <| Elm.Annotation.named [] "RouteParams")
                    )
                |> Just
        , head = input.head
        , moduleName = input.moduleName
        }


{-| -}
single :
    { data : ( Type, Elm.Expression )
    , head : Elm.Expression -> Elm.Expression
    , moduleName : List String
    }
    -> Builder
single input =
    PreRender []
        { data = ( Tuple.first input.data, \_ -> Tuple.second input.data )
        , pages = Nothing
        , head = input.head
        , moduleName = input.moduleName
        }


{-| -}
buildNoState :
    { view : { shared : Elm.Expression, app : Elm.Expression } -> Elm.Expression
    }
    -> Builder
    -> { path : String, body : String }
buildNoState definitions builder_ =
    case builder_ of
        ServerRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared _ ->
                        definitions.view
                            { shared = shared
                            , app = app
                            }
                , localState = Nothing
                , data = builder.data |> Tuple.second
                , action = builder.action |> Tuple.second |> Action
                , head = builder.head
                , types =
                    { model = Alias (Elm.Annotation.record [])
                    , msg = Alias Elm.Annotation.unit
                    , data = builder.data |> Tuple.first
                    , actionData = builder.action |> Tuple.first
                    }
                , declarations = declarations
                }

        PreRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared _ ->
                        definitions.view
                            { shared = shared
                            , app = app
                            }
                , localState = Nothing
                , data = builder.data |> Tuple.second |> (\fn -> \_ -> fn)
                , action = builder.pages |> Pages
                , head = builder.head
                , types =
                    { model = Alias (Elm.Annotation.record [])
                    , msg = Alias Elm.Annotation.unit
                    , data = builder.data |> Tuple.first
                    , actionData =
                        throwableTask
                            (Elm.Annotation.list (Elm.Annotation.named [] "RouteParams"))
                            |> Alias
                    }
                , declarations = declarations
                }


{-| The helpers in this module help you generate a Route module file with the core boilerplate abstracted away.

You can also define additional top-level declarations in the generated Route module using this helper.

-}
addDeclarations : List Elm.Declaration -> Builder -> Builder
addDeclarations declarations builder =
    case builder of
        ServerRender existingDeclarations record ->
            ServerRender (existingDeclarations ++ declarations) record

        PreRender existingDeclarations record ->
            PreRender (existingDeclarations ++ declarations) record


{-| -}
buildWithLocalState :
    { view :
        { shared : Elm.Expression, model : Elm.Expression, app : Elm.Expression } -> Elm.Expression
    , update :
        { shared : Elm.Expression
        , app : Elm.Expression
        , msg : Elm.Expression
        , model : Elm.Expression
        }
        -> Elm.Expression
    , init :
        { shared : Elm.Expression
        , app : Elm.Expression
        }
        -> Elm.Expression
    , subscriptions :
        { routeParams : Elm.Expression
        , path : Elm.Expression
        , shared : Elm.Expression
        , model : Elm.Expression
        }
        -> Elm.Expression
    , msg : Type
    , model : Type
    }
    -> Builder
    -> { path : String, body : String }
buildWithLocalState definitions builder_ =
    case builder_ of
        ServerRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared model ->
                        definitions.view
                            { shared = shared
                            , model = model
                            , app = app
                            }
                , localState =
                    Just
                        { update =
                            \app shared msg model ->
                                definitions.update
                                    { shared = shared
                                    , app = app
                                    , msg = msg
                                    , model = model
                                    }
                        , init =
                            \app shared ->
                                definitions.init
                                    { shared = shared
                                    , app = app
                                    }
                        , subscriptions =
                            \routeParams path shared model ->
                                definitions.subscriptions
                                    { routeParams = routeParams
                                    , path = path
                                    , shared = shared
                                    , model = model
                                    }
                        , state = LocalState
                        }
                , data = builder.data |> Tuple.second
                , action = builder.action |> Tuple.second |> Action
                , head = builder.head
                , types =
                    { model = definitions.model
                    , msg = definitions.msg
                    , data = builder.data |> Tuple.first
                    , actionData = builder.action |> Tuple.first
                    }
                , declarations = declarations
                }

        PreRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared model ->
                        definitions.view
                            { shared = shared
                            , model = model
                            , app = app
                            }
                , localState =
                    Just
                        { update =
                            \app shared msg model ->
                                definitions.update
                                    { shared = shared
                                    , app = app
                                    , msg = msg
                                    , model = model
                                    }
                        , init =
                            \app shared ->
                                definitions.init
                                    { shared = shared
                                    , app = app
                                    }
                        , subscriptions =
                            \routeParams path shared model ->
                                definitions.subscriptions
                                    { routeParams = routeParams
                                    , path = path
                                    , shared = shared
                                    , model = model
                                    }
                        , state = LocalState
                        }
                , data = builder.data |> Tuple.second |> (\fn -> \_ -> fn)
                , action = builder.pages |> Pages
                , head = builder.head
                , types =
                    { model = definitions.model
                    , msg = definitions.msg
                    , data = builder.data |> Tuple.first
                    , actionData =
                        throwableTask
                            (Elm.Annotation.list (Elm.Annotation.named [] "RouteParams"))
                            |> Alias
                    }
                , declarations = declarations
                }


{-| -}
buildWithSharedState :
    { view :
        { shared : Elm.Expression, model : Elm.Expression, app : Elm.Expression } -> Elm.Expression
    , update :
        { shared : Elm.Expression
        , app : Elm.Expression
        , msg : Elm.Expression
        , model : Elm.Expression
        }
        -> Elm.Expression
    , init :
        { shared : Elm.Expression
        , app : Elm.Expression
        }
        -> Elm.Expression
    , subscriptions :
        { routeParams : Elm.Expression
        , path : Elm.Expression
        , shared : Elm.Expression
        , model : Elm.Expression
        }
        -> Elm.Expression
    , msg : Type
    , model : Type
    }
    -> Builder
    -> { path : String, body : String }
buildWithSharedState definitions builder_ =
    case builder_ of
        ServerRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared model ->
                        definitions.view
                            { shared = shared
                            , model = model
                            , app = app
                            }
                , localState =
                    Just
                        { update =
                            \app shared msg model ->
                                definitions.update
                                    { shared = shared
                                    , app = app
                                    , msg = msg
                                    , model = model
                                    }
                        , init =
                            \app shared ->
                                definitions.init
                                    { shared = shared
                                    , app = app
                                    }
                        , subscriptions =
                            \routeParams path shared model ->
                                definitions.subscriptions
                                    { routeParams = routeParams
                                    , path = path
                                    , shared = shared
                                    , model = model
                                    }
                        , state = SharedState
                        }
                , data = builder.data |> Tuple.second
                , action = builder.action |> Tuple.second |> Action
                , head = builder.head
                , types =
                    { model = definitions.model
                    , msg = definitions.msg
                    , data = builder.data |> Tuple.first
                    , actionData = builder.action |> Tuple.first
                    }
                , declarations = declarations
                }

        PreRender declarations builder ->
            userFunction builder.moduleName
                { view =
                    \app shared model ->
                        definitions.view
                            { shared = shared
                            , model = model
                            , app = app
                            }
                , localState =
                    Just
                        { update =
                            \app shared msg model ->
                                definitions.update
                                    { shared = shared
                                    , app = app
                                    , msg = msg
                                    , model = model
                                    }
                        , init =
                            \app shared ->
                                definitions.init
                                    { shared = shared
                                    , app = app
                                    }
                        , subscriptions =
                            \routeParams path shared model ->
                                definitions.subscriptions
                                    { routeParams = routeParams
                                    , path = path
                                    , shared = shared
                                    , model = model
                                    }
                        , state = SharedState
                        }
                , data = builder.data |> Tuple.second |> (\fn -> \_ -> fn)
                , action = builder.pages |> Pages
                , head = builder.head
                , types =
                    { model = definitions.model
                    , msg = definitions.msg
                    , data = builder.data |> Tuple.first
                    , actionData =
                        throwableTask
                            (Elm.Annotation.list (Elm.Annotation.named [] "RouteParams"))
                            |> Alias
                    }
                , declarations = declarations
                }


type State
    = SharedState
    | LocalState


type ActionOrPages
    = Action (Elm.Expression -> Elm.Expression -> Elm.Expression)
    | Pages (Maybe Elm.Expression)


{-| -}
userFunction :
    List String
    ->
        { view : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
        , localState :
            Maybe
                { update : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                , init : Elm.Expression -> Elm.Expression -> Elm.Expression
                , subscriptions : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                , state : State
                }
        , data : Elm.Expression -> Elm.Expression -> Elm.Expression
        , action : ActionOrPages
        , head : Elm.Expression -> Elm.Expression
        , types : { model : Type, msg : Type, data : Type, actionData : Type }
        , declarations : List Elm.Declaration
        }
    -> { path : String, body : String }
userFunction moduleName definitions =
    let
        viewFn :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        viewFn =
            case definitions.localState of
                Just _ ->
                    Elm.Declare.fn3 "view"
                        ( "app", Just appType )
                        ( "shared"
                        , Just (Elm.Annotation.named [ "Shared" ] "Model")
                        )
                        ( "model", Just (Elm.Annotation.named [] "Model") )
                        (\app shared model ->
                            definitions.view app shared model
                                |> Elm.withType
                                    (Elm.Annotation.namedWith [ "View" ]
                                        "View"
                                        [ Elm.Annotation.namedWith [ "PagesMsg" ]
                                            "PagesMsg"
                                            [ localType "Msg"
                                            ]
                                        ]
                                    )
                        )

                Nothing ->
                    let
                        viewDeclaration :
                            { declaration : Elm.Declaration
                            , call : Elm.Expression -> Elm.Expression -> Elm.Expression
                            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
                            , value : List String -> Elm.Expression
                            }
                        viewDeclaration =
                            Elm.Declare.fn2 "view"
                                ( "app", Just appType )
                                ( "shared"
                                , Just (Elm.Annotation.named [ "Shared" ] "Model")
                                )
                                (\app shared ->
                                    definitions.view app shared Elm.unit
                                        |> Elm.withType
                                            (Elm.Annotation.namedWith [ "View" ]
                                                "View"
                                                [ Elm.Annotation.namedWith [ "PagesMsg" ]
                                                    "PagesMsg"
                                                    [ localType "Msg"
                                                    ]
                                                ]
                                            )
                                )
                    in
                    { declaration = viewDeclaration.declaration
                    , call = \app shared _ -> viewDeclaration.call app shared
                    , callFrom = \a _ c d -> viewDeclaration.callFrom a c d
                    , value = viewDeclaration.value
                    }

        localDefinitions :
            Maybe
                { updateFn :
                    { declaration : Elm.Declaration
                    , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                    , value : List String -> Elm.Expression
                    }
                , initFn :
                    { declaration : Elm.Declaration
                    , call : Elm.Expression -> Elm.Expression -> Elm.Expression
                    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
                    , value : List String -> Elm.Expression
                    }
                , subscriptionsFn :
                    { declaration : Elm.Declaration
                    , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
                    , value : List String -> Elm.Expression
                    }
                , state : State
                }
        localDefinitions =
            definitions.localState
                |> Maybe.map
                    (\localState ->
                        { updateFn =
                            Elm.Declare.fn4 "update"
                                ( "app", Just appType )
                                ( "shared", Just (Elm.Annotation.named [ "Shared" ] "Model") )
                                ( "msg", Just (Elm.Annotation.named [] "Msg") )
                                ( "model", Just (Elm.Annotation.named [] "Model") )
                                (\app shared msg model ->
                                    localState.update app shared msg model
                                        |> Elm.withType
                                            (Elm.Annotation.tuple
                                                (localType "Model")
                                                effectType
                                            )
                                )
                        , initFn =
                            Elm.Declare.fn2 "init"
                                ( "app", Just appType )
                                ( "shared", Just (Elm.Annotation.named [ "Shared" ] "Model") )
                                (\shared app ->
                                    localState.init app shared
                                        |> Elm.withType
                                            (Elm.Annotation.tuple
                                                (localType "Model")
                                                effectType
                                            )
                                )
                        , subscriptionsFn =
                            Elm.Declare.fn4
                                "subscriptions"
                                ( "routeParams", "RouteParams" |> Elm.Annotation.named [] |> Just )
                                ( "path", Elm.Annotation.namedWith [ "UrlPath" ] "UrlPath" [] |> Just )
                                ( "shared", Just (Elm.Annotation.named [ "Shared" ] "Model") )
                                ( "model", localType "Model" |> Just )
                                (\routeParams path shared model ->
                                    localState.subscriptions routeParams path shared model
                                        |> Elm.withType (Elm.Annotation.namedWith [] "Sub" [ localType "Msg" ])
                                )
                        , state = localState.state
                        }
                    )

        dataFn : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        dataFn =
            case definitions.action of
                Pages Nothing ->
                    Elm.Declare.function "data"
                        []
                        (\_ ->
                            definitions.data Elm.unit Elm.unit
                                |> Elm.withType
                                    (case definitions.action of
                                        Pages _ ->
                                            throwableTask (Elm.Annotation.named [] "Data")

                                        Action _ ->
                                            myType "Data"
                                    )
                        )

                _ ->
                    Elm.Declare.function "data"
                        [ ( "routeParams"
                          , "RouteParams"
                                |> Elm.Annotation.named []
                                |> Just
                          )
                        , ( "request"
                          , "Request"
                                |> Elm.Annotation.named [ "Server", "Request" ]
                                |> Just
                          )
                        ]
                        (\args ->
                            case args of
                                [ arg, arg2 ] ->
                                    definitions.data arg arg2
                                        |> Elm.withType
                                            (case definitions.action of
                                                Pages _ ->
                                                    throwableTask (Elm.Annotation.named [] "Data")

                                                Action _ ->
                                                    myType "Data"
                                            )

                                _ ->
                                    Elm.unit
                        )

        actionFn : Maybe { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        actionFn =
            case definitions.action of
                Action action_ ->
                    Elm.Declare.function "action"
                        [ ( "routeParams"
                          , "RouteParams"
                                |> Elm.Annotation.named []
                                |> Just
                          )
                        , ( "request"
                          , "Request"
                                |> Elm.Annotation.named [ "Server", "Request" ]
                                |> Just
                          )
                        ]
                        (\args ->
                            case args of
                                [ arg1, arg2 ] ->
                                    action_ arg1 arg2 |> Elm.withType (myType "ActionData")

                                _ ->
                                    Elm.unit
                        )
                        |> Just

                Pages pages_ ->
                    pages_
                        |> Maybe.map
                            (\justPagesExpression ->
                                Elm.Declare.function "pages"
                                    []
                                    (\_ -> justPagesExpression)
                            )

        headFn : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        headFn =
            Elm.Declare.fn "head"
                ( "app", Just appType )
                (definitions.head
                    >> Elm.withType
                        (Elm.Annotation.list
                            (Elm.Annotation.named [ "Head" ] "Tag")
                        )
                )
    in
    Elm.file ("Route" :: moduleName)
        ([ definitions.types.model |> typeToDeclaration "Model" |> Elm.expose
         , definitions.types.msg |> typeToDeclaration "Msg" |> Elm.expose
         , Elm.alias "RouteParams"
            (Elm.Annotation.record
                (RoutePattern.fromModuleName moduleName
                    -- TODO give error if not parseable here
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Maybe.withDefault []
                )
            )
            |> Elm.expose
         , Elm.declaration "route"
            ((case definitions.action of
                Action _ ->
                    serverRender_
                        { action =
                            \routeParams request ->
                                actionFn
                                    |> Maybe.map
                                        (\justActionFn ->
                                            justActionFn.call [ routeParams, request ]
                                                |> Elm.withType (myType "ActionData")
                                        )
                                    |> Maybe.withDefault Elm.unit
                        , data =
                            \routeParams request ->
                                dataFn.call [ routeParams, request ]
                                    |> Elm.withType (myType "Data")
                        , head = headFn.call
                        }

                Pages _ ->
                    case actionFn of
                        Nothing ->
                            single_
                                { data =
                                    dataFn.call []
                                        |> Elm.withType
                                            (throwableTask
                                                (Elm.Annotation.named [] "Data")
                                            )
                                , head = headFn.call
                                }

                        Just justActionFn ->
                            preRender_
                                { pages = justActionFn.call []
                                , data =
                                    \routeParams ->
                                        dataFn.call [ routeParams ]
                                            |> Elm.withType
                                                (throwableTask (Elm.Annotation.named [] "Data"))
                                , head = headFn.call
                                }
             )
                |> (case localDefinitions of
                        Just local ->
                            buildWithLocalState_
                                { view = viewFn.call
                                , update = local.updateFn.call
                                , init = local.initFn.call
                                , subscriptions = local.subscriptionsFn.call
                                , state = local.state
                                }
                                >> Elm.withType
                                    (Elm.Annotation.namedWith [ "RouteBuilder" ]
                                        "StatefulRoute"
                                        [ localType "RouteParams"
                                        , localType "Data"
                                        , localType "ActionData"
                                        , localType "Model"
                                        , localType "Msg"
                                        ]
                                    )

                        Nothing ->
                            buildNoState_
                                { view = \app shared -> viewFn.call app shared Elm.unit
                                }
                                >> Elm.withType
                                    (Elm.Annotation.namedWith [ "RouteBuilder" ]
                                        "StatelessRoute"
                                        [ localType "RouteParams"
                                        , localType "Data"
                                        , localType "ActionData"
                                        ]
                                    )
                   )
            )
            |> Elm.expose
         ]
            ++ (case localDefinitions of
                    Just local ->
                        [ local.initFn.declaration
                        , local.updateFn.declaration
                        , local.subscriptionsFn.declaration
                        ]

                    Nothing ->
                        []
               )
            ++ [ definitions.types.data |> typeToDeclaration "Data" |> Elm.expose
               , definitions.types.actionData |> typeToDeclaration "ActionData" |> Elm.expose
               , dataFn.declaration
               , headFn.declaration
               , viewFn.declaration
               ]
            ++ ([ actionFn |> Maybe.map .declaration
                ]
                    |> List.filterMap identity
               )
            ++ definitions.declarations
        )
        |> (\{ path, contents } ->
                { path = "app/" ++ path
                , body = contents
                }
           )


localType : String -> Elm.Annotation.Annotation
localType =
    Elm.Annotation.named []


myType : String -> Elm.Annotation.Annotation
myType dataType =
    --Elm.Annotation.function
    --    [ Elm.Annotation.namedWith [ "Server", "Request" ]
    --        "Request"
    --        []
    --    ]
    throwableTask
        (Elm.Annotation.namedWith [ "Server", "Response" ]
            "Response"
            [ Elm.Annotation.named [] dataType
            , Elm.Annotation.named [ "ErrorPage" ] "ErrorPage"
            ]
        )


appType : Elm.Annotation.Annotation
appType =
    Elm.Annotation.namedWith [ "RouteBuilder" ]
        "App"
        [ Elm.Annotation.named [] "Data"
        , Elm.Annotation.named [] "ActionData"
        , Elm.Annotation.named [] "RouteParams"
        ]


serverRender_ :
    { data : Elm.Expression -> Elm.Expression -> Elm.Expression
    , action : Elm.Expression -> Elm.Expression -> Elm.Expression
    , head : Elm.Expression -> Elm.Expression
    }
    -> Elm.Expression
serverRender_ serverRenderArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "RouteBuilder" ]
            , name = "serverRender"
            , annotation =
                Just
                    (Elm.Annotation.function
                        [ Elm.Annotation.record
                            [ ( "data"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.var "routeParams" ]
                                    (Elm.Annotation.namedWith
                                        [ "Server", "Request" ]
                                        "Parser"
                                        [ throwableTask
                                            (Elm.Annotation.namedWith
                                                [ "Server", "Response" ]
                                                "Response"
                                                [ Elm.Annotation.var "data"
                                                , Elm.Annotation.namedWith
                                                    [ "ErrorPage" ]
                                                    "ErrorPage"
                                                    []
                                                ]
                                            )
                                        ]
                                    )
                              )
                            , ( "action"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.var "routeParams"
                                    , Elm.Annotation.named [ "Server", "Request" ] "Request"
                                    ]
                                    (throwableTask
                                        (Elm.Annotation.namedWith
                                            [ "Server", "Response" ]
                                            "Response"
                                            [ Elm.Annotation.var "action"
                                            , Elm.Annotation.namedWith
                                                [ "ErrorPage" ]
                                                "ErrorPage"
                                                []
                                            ]
                                        )
                                    )
                              )
                            , ( "head"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "App"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    ]
                                    (Elm.Annotation.list
                                        (Elm.Annotation.namedWith [ "Head" ] "Tag" [])
                                    )
                              )
                            ]
                        ]
                        (Elm.Annotation.namedWith
                            [ "RouteBuilder" ]
                            "Builder"
                            [ Elm.Annotation.var "routeParams"
                            , Elm.Annotation.var "data"
                            , Elm.Annotation.var "action"
                            ]
                        )
                    )
            }
        )
        [ Elm.record
            [ Tuple.pair
                "data"
                (Elm.functionReduced
                    "dataUnpack"
                    (\functionReducedUnpack ->
                        Elm.functionReduced "dataUnpack2" (serverRenderArg.data functionReducedUnpack)
                    )
                )
            , Tuple.pair
                "action"
                (Elm.functionReduced
                    "actionUnpack"
                    (\functionReducedUnpack ->
                        Elm.functionReduced "actionUnpack2" (serverRenderArg.action functionReducedUnpack)
                    )
                )
            , Tuple.pair
                "head"
                (Elm.functionReduced "serverRenderUnpack" serverRenderArg.head)
            ]
        ]


preRender_ :
    { data : Elm.Expression -> Elm.Expression
    , pages : Elm.Expression
    , head : Elm.Expression -> Elm.Expression
    }
    -> Elm.Expression
preRender_ serverRenderArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "RouteBuilder" ]
            , name = "preRender"
            , annotation =
                Just
                    (Elm.Annotation.function
                        [ Elm.Annotation.record
                            [ ( "data"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.var "routeParams" ]
                                    (throwableTask (Elm.Annotation.var "data"))
                              )
                            , ( "pages"
                              , throwableTask
                                    (Elm.Annotation.list (Elm.Annotation.named [] "RouteParams"))
                              )
                            , ( "head"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "App"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    ]
                                    (Elm.Annotation.list
                                        (Elm.Annotation.namedWith [ "Head" ] "Tag" [])
                                    )
                              )
                            ]
                        ]
                        (Elm.Annotation.namedWith
                            [ "RouteBuilder" ]
                            "Builder"
                            [ Elm.Annotation.named [] "RouteParams"
                            , Elm.Annotation.named [] "Data"
                            , Elm.Annotation.named [] "Action"
                            ]
                        )
                    )
            }
        )
        [ Elm.record
            [ Tuple.pair "data" (Elm.functionReduced "serverRenderUnpack" serverRenderArg.data)
            , Tuple.pair "pages" serverRenderArg.pages
            , Tuple.pair "head" (Elm.functionReduced "serverRenderUnpack" serverRenderArg.head)
            ]
        ]


single_ :
    { data : Elm.Expression
    , head : Elm.Expression -> Elm.Expression
    }
    -> Elm.Expression
single_ serverRenderArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "RouteBuilder" ]
            , name = "single"
            , annotation =
                Just
                    (Elm.Annotation.function
                        [ Elm.Annotation.record
                            [ ( "data"
                              , throwableTask (Elm.Annotation.var "data")
                              )
                            , ( "head"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "App"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    ]
                                    (Elm.Annotation.list
                                        (Elm.Annotation.namedWith [ "Head" ] "Tag" [])
                                    )
                              )
                            ]
                        ]
                        (Elm.Annotation.namedWith
                            [ "RouteBuilder" ]
                            "Builder"
                            [ Elm.Annotation.named [] "RouteParams"
                            , Elm.Annotation.named [] "Data"
                            , Elm.Annotation.named [] "Action"
                            ]
                        )
                    )
            }
        )
        [ Elm.record
            [ Tuple.pair "data" serverRenderArg.data
            , Tuple.pair "head" (Elm.functionReduced "serverRenderUnpack" serverRenderArg.head)
            ]
        ]


buildWithLocalState_ :
    { view :
        Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
    , init :
        Elm.Expression -> Elm.Expression -> Elm.Expression
    , update :
        Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
    , subscriptions :
        Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
    , state : State
    }
    -> Elm.Expression
    -> Elm.Expression
buildWithLocalState_ buildWithLocalStateArg buildWithLocalStateArg0 =
    Elm.Op.pipe
        (Elm.apply
            (Elm.value
                { importFrom = [ "RouteBuilder" ]
                , name =
                    case buildWithLocalStateArg.state of
                        LocalState ->
                            "buildWithLocalState"

                        SharedState ->
                            "buildWithSharedState"
                , annotation =
                    Just
                        (Elm.Annotation.function
                            [ Elm.Annotation.record
                                [ ( "view"
                                  , Elm.Annotation.function
                                        [ Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                        , Elm.Annotation.var "model"
                                        , Elm.Annotation.namedWith
                                            [ "RouteBuilder" ]
                                            "App"
                                            [ Elm.Annotation.var "data"
                                            , Elm.Annotation.var "action"
                                            , Elm.Annotation.var "routeParams"
                                            ]
                                        ]
                                        (Elm.Annotation.namedWith
                                            [ "View" ]
                                            "View"
                                            [ Elm.Annotation.namedWith
                                                [ "PagesMsg" ]
                                                "PagesMsg"
                                                [ Elm.Annotation.named [] "Msg" ]
                                            ]
                                        )
                                  )
                                , ( "init"
                                  , Elm.Annotation.function
                                        [ Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                        , Elm.Annotation.namedWith
                                            [ "RouteBuilder" ]
                                            "App"
                                            [ Elm.Annotation.var "data"
                                            , Elm.Annotation.var "action"
                                            , Elm.Annotation.var "routeParams"
                                            ]
                                        ]
                                        (Elm.Annotation.tuple
                                            (Elm.Annotation.named [] "Model")
                                            (Elm.Annotation.namedWith
                                                [ "Effect" ]
                                                "Effect"
                                                [ Elm.Annotation.named [] "Msg" ]
                                            )
                                        )
                                  )
                                , ( "update"
                                  , Elm.Annotation.function
                                        [ Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                        , Elm.Annotation.namedWith
                                            [ "RouteBuilder" ]
                                            "App"
                                            [ localType "Data"
                                            , localType "ActionData"
                                            , localType "RouteParams"
                                            ]
                                        , Elm.Annotation.named [] "Msg"
                                        , Elm.Annotation.named [] "Model"
                                        ]
                                        (case buildWithLocalStateArg.state of
                                            LocalState ->
                                                Elm.Annotation.tuple
                                                    (localType "Model")
                                                    (Elm.Annotation.namedWith
                                                        [ "Effect" ]
                                                        "Effect"
                                                        [ localType "Msg" ]
                                                    )

                                            SharedState ->
                                                Elm.Annotation.triple
                                                    (localType "Model")
                                                    (Elm.Annotation.namedWith
                                                        [ "Effect" ]
                                                        "Effect"
                                                        [ localType "Msg" ]
                                                    )
                                                    (Elm.Annotation.maybe (Elm.Annotation.named [ "Shared" ] "Msg"))
                                        )
                                  )
                                , ( "subscriptions"
                                  , Elm.Annotation.function
                                        [ Elm.Annotation.var "routeParams"
                                        , Elm.Annotation.namedWith [ "UrlPath" ] "UrlPath" []
                                        , Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                        , Elm.Annotation.var "model"
                                        ]
                                        (Elm.Annotation.namedWith [] "Sub" [ localType "Msg" ])
                                  )
                                ]
                            , Elm.Annotation.namedWith
                                [ "RouteBuilder" ]
                                "Builder"
                                [ localType "RouteParams"
                                , localType "Data"
                                , localType "ActionData"
                                ]
                            ]
                            (Elm.Annotation.namedWith
                                [ "RouteBuilder" ]
                                "StatefulRoute"
                                [ localType "RouteParams"
                                , localType "Data"
                                , localType "ActionData"
                                , localType "Model"
                                , localType "Msg"
                                ]
                            )
                        )
                }
            )
            [ Elm.record
                [ Tuple.pair
                    "view"
                    (Elm.functionReduced
                        "buildWithLocalStateUnpack"
                        (\functionReducedUnpack ->
                            Elm.functionReduced
                                "unpack"
                                (\functionReducedUnpack_2_1_2_0_2_2_0_1_0_2_0_0 ->
                                    Elm.functionReduced
                                        "unpack"
                                        (buildWithLocalStateArg.view
                                            functionReducedUnpack
                                            functionReducedUnpack_2_1_2_0_2_2_0_1_0_2_0_0
                                        )
                                )
                        )
                    )
                , Tuple.pair
                    "init"
                    (Elm.functionReduced
                        "buildWithLocalStateUnpack"
                        (\functionReducedUnpack ->
                            Elm.functionReduced
                                "unpack"
                                (buildWithLocalStateArg.init
                                    functionReducedUnpack
                                )
                        )
                    )
                , Tuple.pair
                    "update"
                    (Elm.functionReduced
                        "buildWithLocalStateUnpack"
                        (\functionReducedUnpack ->
                            Elm.functionReduced
                                "unpack"
                                (\functionReducedUnpack_2_1_2_0_2_2_2_1_0_2_0_0 ->
                                    Elm.functionReduced
                                        "unpack"
                                        (\functionReducedUnpack_2_1_2_1_2_0_2_2_2_1_0_2_0_0 ->
                                            Elm.functionReduced
                                                "unpack"
                                                (buildWithLocalStateArg.update
                                                    functionReducedUnpack
                                                    functionReducedUnpack_2_1_2_0_2_2_2_1_0_2_0_0
                                                    functionReducedUnpack_2_1_2_1_2_0_2_2_2_1_0_2_0_0
                                                )
                                        )
                                )
                        )
                    )
                , Tuple.pair
                    "subscriptions"
                    (Elm.functionReduced
                        "buildWithLocalStateUnpack"
                        (\functionReducedUnpack ->
                            Elm.functionReduced
                                "unpack"
                                (\functionReducedUnpack_2_1_2_0_2_2_3_1_0_2_0_0 ->
                                    Elm.functionReduced
                                        "unpack"
                                        (\functionReducedUnpack_2_1_2_1_2_0_2_2_3_1_0_2_0_0 ->
                                            Elm.functionReduced
                                                "unpack"
                                                (buildWithLocalStateArg.subscriptions
                                                    functionReducedUnpack
                                                    functionReducedUnpack_2_1_2_0_2_2_3_1_0_2_0_0
                                                    functionReducedUnpack_2_1_2_1_2_0_2_2_3_1_0_2_0_0
                                                )
                                        )
                                )
                        )
                    )
                ]
            ]
        )
        buildWithLocalStateArg0


buildNoState_ :
    { view :
        Elm.Expression -> Elm.Expression -> Elm.Expression
    }
    -> Elm.Expression
    -> Elm.Expression
buildNoState_ buildNoStateArg buildNoStateArg0 =
    Elm.Op.pipe
        (Elm.apply
            (Elm.value
                { importFrom = [ "RouteBuilder" ]
                , name = "buildNoState"
                , annotation =
                    Just
                        (Elm.Annotation.function
                            [ Elm.Annotation.record
                                [ ( "view"
                                  , Elm.Annotation.function
                                        [ Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                        , Elm.Annotation.namedWith
                                            [ "RouteBuilder" ]
                                            "App"
                                            [ Elm.Annotation.named [] "Data"
                                            , Elm.Annotation.named [] "ActionData"
                                            , Elm.Annotation.named [] "RouteParams"
                                            ]
                                        ]
                                        (Elm.Annotation.namedWith
                                            [ "View" ]
                                            "View"
                                            [ Elm.Annotation.namedWith
                                                [ "PagesMsg" ]
                                                "PagesMsg"
                                                [ Elm.Annotation.named [] "Msg" ]
                                            ]
                                        )
                                  )
                                ]
                            , Elm.Annotation.namedWith
                                [ "RouteBuilder" ]
                                "Builder"
                                [ Elm.Annotation.named [] "RouteParams"
                                , Elm.Annotation.named [] "Data"
                                , Elm.Annotation.named [] "ActionData"
                                ]
                            ]
                            (Elm.Annotation.namedWith
                                [ "RouteBuilder" ]
                                "StatefulRoute"
                                [ Elm.Annotation.named [] "RouteParams"
                                , Elm.Annotation.named [] "Data"
                                , Elm.Annotation.named [] "ActionData"
                                , Elm.Annotation.record []
                                , Elm.Annotation.unit
                                ]
                            )
                        )
                }
            )
            [ Elm.record
                [ Tuple.pair
                    "view"
                    (Elm.functionReduced
                        "unpack"
                        (\functionReducedUnpack0 ->
                            Elm.functionReduced
                                "unpack"
                                (buildNoStateArg.view
                                    functionReducedUnpack0
                                )
                        )
                    )
                ]
            ]
        )
        buildNoStateArg0


effectType : Elm.Annotation.Annotation
effectType =
    Elm.Annotation.namedWith
        [ "Effect" ]
        "Effect"
        [ Elm.Annotation.named [] "Msg" ]


throwableTask : Elm.Annotation.Annotation -> Elm.Annotation.Annotation
throwableTask dataType =
    Elm.Annotation.namedWith [ "BackendTask" ]
        "BackendTask"
        [ Elm.Annotation.named [ "FatalError" ] "FatalError"
        , dataType
        ]
