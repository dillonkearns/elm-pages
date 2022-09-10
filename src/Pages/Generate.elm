module Pages.Generate exposing (Type(..), serverRender, withLocalState)

{-|

@docs Type, serverRender, withLocalState

-}

import Elm
import Elm.Annotation
import Elm.Declare
import Pages.Internal.RoutePattern as RoutePattern


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


type Builder
    = Builder
        { data : ( Type, Elm.Expression -> Elm.Expression )
        , action : ( Type, Elm.Expression -> Elm.Expression )
        , head : Elm.Expression -> Elm.Expression
        , moduleName : List String
        }


serverRender :
    { data : ( Type, Elm.Expression -> Elm.Expression )
    , action : ( Type, Elm.Expression -> Elm.Expression )
    , head : Elm.Expression -> Elm.Expression
    , moduleName : List String
    }
    -> Builder
serverRender =
    Builder


withLocalState :
    { view : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , update : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , init : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , subscriptions : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , msg : Type
    , model : Type
    }
    -> Builder
    -> Elm.File
withLocalState definitions (Builder builder) =
    userFunction builder.moduleName
        { view = definitions.view
        , update = definitions.update
        , init = definitions.init
        , subscriptions = definitions.subscriptions
        , data = builder.data |> Tuple.second
        , action = builder.action |> Tuple.second
        , head = builder.head
        , types =
            { model = definitions.model
            , msg = definitions.msg
            , data = builder.data |> Tuple.first
            , actionData = builder.action |> Tuple.first
            }
        }



-- Msg for noState must be type alias `()`
-- Model for noState must be type alias `{}`


{-| -}
userFunction :
    List String
    ->
        { view : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
        , update : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
        , init : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
        , subscriptions : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
        , data : Elm.Expression -> Elm.Expression
        , action : Elm.Expression -> Elm.Expression
        , head : Elm.Expression -> Elm.Expression
        , types : { model : Type, msg : Type, data : Type, actionData : Type }
        }
    -> Elm.File
userFunction moduleName definitions =
    let
        viewFn =
            Elm.Declare.fn4 "view"
                ( "maybeUrl"
                , "PageUrl"
                    |> Elm.Annotation.named [ "Pages", "PageUrl" ]
                    |> Elm.Annotation.maybe
                    |> Just
                )
                ( "sharedModel"
                , Nothing
                )
                ( "model", Just (Elm.Annotation.named [] "Model") )
                ( "app", Just appType )
                definitions.view

        updateFn =
            Elm.Declare.fn5 "update"
                ( "pageUrl"
                , "PageUrl"
                    |> Elm.Annotation.named [ "Pages", "PageUrl" ]
                    |> Just
                )
                ( "sharedModel", Nothing )
                ( "app", Just appType )
                ( "msg", Just (Elm.Annotation.named [] "Msg") )
                ( "model", Just (Elm.Annotation.named [] "Model") )
                definitions.update

        initFn =
            Elm.Declare.fn3 "init"
                ( "pageUrl"
                , "PageUrl"
                    |> Elm.Annotation.named [ "Pages", "PageUrl" ]
                    |> Elm.Annotation.maybe
                    |> Just
                )
                ( "sharedModel", Nothing )
                ( "app", Just appType )
                definitions.init

        subscriptionsFn =
            Elm.Declare.fn5
                "subscriptions"
                ( "maybePageUrl"
                , "PageUrl"
                    |> Elm.Annotation.named [ "Pages", "PageUrl" ]
                    |> Elm.Annotation.maybe
                    |> Just
                )
                ( "routeParams", Nothing )
                ( "path", Nothing )
                ( "sharedModel", Nothing )
                ( "model", Nothing )
                definitions.subscriptions

        dataFn =
            Elm.Declare.fn "data"
                ( "routeParams"
                , "RouteParams"
                    |> Elm.Annotation.named []
                    |> Just
                )
                (definitions.data >> Elm.withType (myType "Data"))

        actionFn =
            Elm.Declare.fn "action"
                ( "routeParams"
                , "RouteParams"
                    |> Elm.Annotation.named []
                    |> Just
                )
                (definitions.action >> Elm.withType (myType "ActionData"))

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
        [ definitions.types.model |> typeToDeclaration "Model"
        , definitions.types.msg |> typeToDeclaration "Msg"
        , Elm.alias "RouteParams"
            (Elm.Annotation.record
                (RoutePattern.fromModuleName moduleName
                    -- TODO give error if not parseable here
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Maybe.withDefault []
                )
            )
        , Elm.declaration "route"
            (serverRender_
                { action =
                    \routeParams ->
                        actionFn.call routeParams
                            |> Elm.withType (myType "ActionData")
                , data =
                    \routeParams ->
                        dataFn.call routeParams
                            |> Elm.withType (myType "Data")
                , head = headFn.call
                }
                |> buildWithLocalState
                    { view = viewFn.call
                    , update = updateFn.call
                    , init = initFn.call
                    , subscriptions = subscriptionsFn.call
                    }
                |> Elm.withType
                    (Elm.Annotation.namedWith [ "RouteBuilder" ]
                        "StatefulRoute"
                        [ localType "RouteParams"
                        , localType "Data"
                        , localType "ActionData"
                        , localType "Model"
                        , localType "Msg"
                        ]
                    )
            )
        , initFn.declaration
        , updateFn.declaration
        , subscriptionsFn.declaration
        , definitions.types.data |> typeToDeclaration "Data"
        , definitions.types.actionData |> typeToDeclaration "ActionData"
        , dataFn.declaration
        , actionFn.declaration
        , headFn.declaration
        , viewFn.declaration
        ]


localType =
    Elm.Annotation.named []


myType dataType =
    Elm.Annotation.namedWith [ "Server", "Request" ]
        "Parser"
        [ Elm.Annotation.namedWith [ "DataSource" ]
            "DataSource"
            [ Elm.Annotation.namedWith [ "Server", "Response" ]
                "Response"
                [ Elm.Annotation.named [] dataType
                , Elm.Annotation.named [ "ErrorPage" ] "ErrorPage"
                ]
            ]
        ]


appType : Elm.Annotation.Annotation
appType =
    Elm.Annotation.namedWith [ "RouteBuilder" ]
        "StaticPayload"
        [ Elm.Annotation.named [] "Data"
        , Elm.Annotation.named [] "ActionData"
        , Elm.Annotation.named [] "RouteParams"
        ]


serverRender_ :
    { data : Elm.Expression -> Elm.Expression
    , action : Elm.Expression -> Elm.Expression
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
                                        [ Elm.Annotation.namedWith
                                            [ "DataSource" ]
                                            "DataSource"
                                            [ Elm.Annotation.namedWith
                                                [ "Server", "Response" ]
                                                "Response"
                                                [ Elm.Annotation.var "data"
                                                , Elm.Annotation.namedWith
                                                    [ "ErrorPage" ]
                                                    "ErrorPage"
                                                    []
                                                ]
                                            ]
                                        ]
                                    )
                              )
                            , ( "action"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.var "routeParams" ]
                                    (Elm.Annotation.namedWith
                                        [ "Server", "Request" ]
                                        "Parser"
                                        [ Elm.Annotation.namedWith
                                            [ "DataSource" ]
                                            "DataSource"
                                            [ Elm.Annotation.namedWith
                                                [ "Server", "Response" ]
                                                "Response"
                                                [ Elm.Annotation.var "action"
                                                , Elm.Annotation.namedWith
                                                    [ "ErrorPage" ]
                                                    "ErrorPage"
                                                    []
                                                ]
                                            ]
                                        ]
                                    )
                              )
                            , ( "head"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "StaticPayload"
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
                (Elm.functionReduced "serverRenderUnpack" serverRenderArg.data)
            , Tuple.pair
                "action"
                (Elm.functionReduced "serverRenderUnpack" serverRenderArg.action)
            , Tuple.pair
                "head"
                (Elm.functionReduced "serverRenderUnpack" serverRenderArg.head)
            ]
        ]


buildWithLocalState :
    { view :
        Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
        -> Elm.Expression
    , init :
        Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , update :
        Elm.Expression
        -> Elm.Expression
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
        -> Elm.Expression
    }
    -> Elm.Expression
    -> Elm.Expression
buildWithLocalState buildWithLocalStateArg buildWithLocalStateArg0 =
    Elm.apply
        (Elm.value
            { importFrom = [ "RouteBuilder" ]
            , name = "buildWithLocalState"
            , annotation =
                Just
                    (Elm.Annotation.function
                        [ Elm.Annotation.record
                            [ ( "view"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.maybe
                                        (Elm.Annotation.namedWith
                                            [ "Pages", "PageUrl" ]
                                            "PageUrl"
                                            []
                                        )
                                    , Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                    , Elm.Annotation.var "model"
                                    , Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "StaticPayload"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    ]
                                    (Elm.Annotation.namedWith
                                        [ "View" ]
                                        "View"
                                        [ Elm.Annotation.namedWith
                                            [ "Pages", "Msg" ]
                                            "Msg"
                                            [ Elm.Annotation.var "msg" ]
                                        ]
                                    )
                              )
                            , ( "init"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.maybe
                                        (Elm.Annotation.namedWith
                                            [ "Pages", "PageUrl" ]
                                            "PageUrl"
                                            []
                                        )
                                    , Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                    , Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "StaticPayload"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    ]
                                    (Elm.Annotation.tuple
                                        (Elm.Annotation.var "model")
                                        (Elm.Annotation.namedWith
                                            [ "Effect" ]
                                            "Effect"
                                            [ Elm.Annotation.var "msg" ]
                                        )
                                    )
                              )
                            , ( "update"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.namedWith
                                        [ "Pages", "PageUrl" ]
                                        "PageUrl"
                                        []
                                    , Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                    , Elm.Annotation.namedWith
                                        [ "RouteBuilder" ]
                                        "StaticPayload"
                                        [ Elm.Annotation.var "data"
                                        , Elm.Annotation.var "action"
                                        , Elm.Annotation.var "routeParams"
                                        ]
                                    , Elm.Annotation.var "msg"
                                    , Elm.Annotation.var "model"
                                    ]
                                    (Elm.Annotation.tuple
                                        (Elm.Annotation.var "model")
                                        (Elm.Annotation.namedWith
                                            [ "Effect" ]
                                            "Effect"
                                            [ Elm.Annotation.var "msg" ]
                                        )
                                    )
                              )
                            , ( "subscriptions"
                              , Elm.Annotation.function
                                    [ Elm.Annotation.maybe
                                        (Elm.Annotation.namedWith
                                            [ "Pages", "PageUrl" ]
                                            "PageUrl"
                                            []
                                        )
                                    , Elm.Annotation.var "routeParams"
                                    , Elm.Annotation.namedWith [ "Path" ] "Path" []
                                    , Elm.Annotation.namedWith [ "Shared" ] "Model" []
                                    , Elm.Annotation.var "model"
                                    ]
                                    (Elm.Annotation.namedWith [] "Sub" [ Elm.Annotation.var "msg" ])
                              )
                            ]
                        , Elm.Annotation.namedWith
                            [ "RouteBuilder" ]
                            "Builder"
                            [ Elm.Annotation.var "routeParams"
                            , Elm.Annotation.var "data"
                            , Elm.Annotation.var "action"
                            ]
                        ]
                        (Elm.Annotation.namedWith
                            [ "RouteBuilder" ]
                            "StatefulRoute"
                            [ Elm.Annotation.var "routeParams"
                            , Elm.Annotation.var "data"
                            , Elm.Annotation.var "action"
                            , Elm.Annotation.var "model"
                            , Elm.Annotation.var "msg"
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
                            (\functionReducedUnpack0 ->
                                Elm.functionReduced
                                    "unpack"
                                    (\functionReducedUnpack_2_1_2_0_2_2_0_1_0_2_0_0 ->
                                        Elm.functionReduced
                                            "unpack"
                                            (buildWithLocalStateArg.view
                                                functionReducedUnpack
                                                functionReducedUnpack0
                                                functionReducedUnpack_2_1_2_0_2_2_0_1_0_2_0_0
                                            )
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
                            (\functionReducedUnpack0 ->
                                Elm.functionReduced
                                    "unpack"
                                    (buildWithLocalStateArg.init
                                        functionReducedUnpack
                                        functionReducedUnpack0
                                    )
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
                            (\functionReducedUnpack0 ->
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
                                                        functionReducedUnpack0
                                                        functionReducedUnpack_2_1_2_0_2_2_2_1_0_2_0_0
                                                        functionReducedUnpack_2_1_2_1_2_0_2_2_2_1_0_2_0_0
                                                    )
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
                            (\functionReducedUnpack0 ->
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
                                                        functionReducedUnpack0
                                                        functionReducedUnpack_2_1_2_0_2_2_3_1_0_2_0_0
                                                        functionReducedUnpack_2_1_2_1_2_0_2_2_3_1_0_2_0_0
                                                    )
                                            )
                                    )
                            )
                    )
                )
            ]
        , buildWithLocalStateArg0
        ]
