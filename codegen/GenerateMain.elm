module GenerateMain exposing (..)

import Elm exposing (File)
import Elm.Annotation as Type
import Elm.Case
import Elm.Declare
import Elm.Extra exposing (expose, fnIgnore, topLevelValue)
import Elm.Let
import Elm.Op
import Elm.Pattern
import Gen.Api
import Gen.ApiRoute
import Gen.BackendTask
import Gen.Basics
import Gen.Bytes
import Gen.Bytes.Decode
import Gen.Bytes.Encode
import Gen.Dict
import Gen.Effect
import Gen.ErrorPage
import Gen.Head
import Gen.Html
import Gen.Json.Decode
import Gen.Json.Encode
import Gen.List
import Gen.Maybe
import Gen.Pages.ConcurrentSubmission
import Gen.Pages.Fetcher
import Gen.Pages.Internal.NotFoundReason
import Gen.Pages.Internal.Platform
import Gen.Pages.Internal.Platform.Cli
import Gen.Pages.Internal.RoutePattern
import Gen.Pages.PageUrl
import Gen.Pages.ProgramConfig
import Gen.PagesMsg
import Gen.Platform.Sub
import Gen.Server.Request
import Gen.Server.Response
import Gen.Shared
import Gen.Site
import Gen.String
import Gen.Tuple
import Gen.Url
import Gen.UrlPath
import Gen.View
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import String.Case


type Phase
    = Browser
    | Cli


otherFile : List RoutePattern.RoutePattern -> String -> File
otherFile routes phaseString =
    let
        phase : Phase
        phase =
            case phaseString of
                "browser" ->
                    Browser

                _ ->
                    Cli

        --config :
        --    { declaration : Elm.Declaration
        --    , reference : Elm.Expression
        --    , referenceFrom : List String -> Elm.Expression
        --    }
        config =
            { init = Elm.apply (Elm.val "init") [ Elm.nothing ]
            , update = update.value []
            , subscriptions = subscriptions.value []
            , sharedData =
                Gen.Shared.values_.template
                    |> Elm.get "data"
            , data = dataForRoute.value []
            , action = action.value []
            , onActionData = onActionData.value []
            , view = view.value []
            , handleRoute = handleRoute.value []
            , getStaticRoutes =
                case phase of
                    Browser ->
                        Gen.BackendTask.succeed (Elm.list [])

                    Cli ->
                        getStaticRoutes.reference
                            |> Gen.BackendTask.map (Gen.List.call_.map (Elm.val "Just"))
            , urlToRoute =
                Elm.value
                    { annotation = Nothing
                    , name = "urlToRoute"
                    , importFrom = [ "Route" ]
                    }
            , routeToPath =
                Elm.fn ( "route", Nothing )
                    (\route ->
                        route
                            |> Gen.Maybe.map
                                (\value ->
                                    Elm.apply
                                        (Elm.value
                                            { annotation = Nothing
                                            , name = "routeToPath"
                                            , importFrom = [ "Route" ]
                                            }
                                        )
                                        [ value ]
                                )
                            |> Gen.Maybe.withDefault (Elm.list [])
                    )
            , site =
                case phase of
                    Browser ->
                        Elm.nothing

                    Cli ->
                        Elm.just Gen.Site.values_.config
            , toJsPort = Elm.val "toJsPort"
            , fromJsPort = applyIdentityTo (Elm.val "fromJsPort")
            , gotBatchSub =
                case phase of
                    Browser ->
                        Gen.Platform.Sub.values_.none

                    Cli ->
                        applyIdentityTo (Elm.val "gotBatchSub")
            , hotReloadData =
                applyIdentityTo (Elm.val "hotReloadData")
            , onPageChange = Elm.val "OnPageChange"
            , apiRoutes =
                Elm.fn ( "htmlToString", Nothing )
                    (\htmlToString ->
                        case phase of
                            Browser ->
                                Elm.list []

                            Cli ->
                                Elm.Op.cons pathsToGenerateHandler.reference
                                    (Elm.Op.cons routePatterns.reference
                                        (Elm.Op.cons apiPatterns.reference
                                            (Gen.Api.call_.routes
                                                getStaticRoutes.reference
                                                htmlToString
                                            )
                                        )
                                    )
                    )
            , pathPatterns = pathPatterns.reference
            , basePath =
                Elm.value
                    { name = "baseUrlAsPath"
                    , importFrom = [ "Route" ]
                    , annotation = Nothing
                    }
            , sendPageData = Elm.val "sendPageData"
            , byteEncodePageData = byteEncodePageData.value []
            , byteDecodePageData = byteDecodePageData.value []
            , encodeResponse = encodeResponse.reference
            , encodeAction = encodeActionData.value []
            , decodeResponse = decodeResponse.reference
            , globalHeadTags =
                case phase of
                    Browser ->
                        Elm.nothing

                    Cli ->
                        Elm.just (globalHeadTags.value [])
            , cmdToEffect = Gen.Effect.values_.fromCmd
            , perform = Gen.Effect.values_.perform
            , errorStatusCode = Gen.ErrorPage.values_.statusCode
            , notFoundPage = Gen.ErrorPage.values_.notFound
            , internalError = Gen.ErrorPage.values_.internalError
            , errorPageToData = Elm.val "DataErrorPage____"
            , notFoundRoute = Elm.nothing
            }
                |> Gen.Pages.ProgramConfig.make_.programConfig
                |> Elm.withType Type.unit

        --|> Elm.withType
        --    (Gen.Pages.ProgramConfig.annotation_.programConfig
        --        (Type.named [] "Msg")
        --        (Type.named [] "Model")
        --        (Type.maybe (Type.named [ "Route" ] "Route"))
        --        (Type.named [] "PageData")
        --        (Type.named [] "ActionData")
        --        (Type.named [ "Shared" ] "Data")
        --        (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ])
        --        (Type.var "mappedMsg")
        --        (Type.named [ "ErrorPage" ] "ErrorPage")
        --    )
        --|> topLevelValue "config"
        pathPatterns :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        pathPatterns =
            topLevelValue "routePatterns3"
                (routes
                    |> List.map routePatternToExpression
                    |> Elm.list
                )

        view :
            { declaration : Elm.Declaration
            , call : List Elm.Expression -> Elm.Expression
            , callFrom : List String -> List Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        view =
            Elm.Declare.function "view"
                [ ( "pageFormState", Type.named [ "Form" ] "Model" |> Just )
                , ( "concurrentSubmissions"
                  , Gen.Dict.annotation_.dict Type.string
                        (Gen.Pages.ConcurrentSubmission.annotation_.concurrentSubmission (Type.named [] "ActionData"))
                        |> Just
                  )
                , ( "navigation", Type.named [ "Pages", "Navigation" ] "Navigation" |> Type.maybe |> Just )
                , ( "page"
                  , Type.record
                        [ ( "path", Type.named [ "UrlPath" ] "UrlPath" )
                        , ( "route", Type.maybe (Type.named [ "Route" ] "Route") )
                        ]
                        |> Just
                  )
                , ( "maybePageUrl", Type.maybe (Type.named [ "Pages", "PageUrl" ] "PageUrl") |> Just )
                , ( "globalData", Type.named [ "Shared" ] "Data" |> Just )
                , ( "pageData", Type.named [] "PageData" |> Just )
                , ( "actionData", Type.maybe (Type.named [] "ActionData") |> Just )
                ]
                (\args ->
                    case args of
                        [ pageFormState, concurrentSubmissions, navigation, page, maybePageUrl, globalData, pageData, actionData ] ->
                            let
                                routeToBranch route =
                                    Elm.Pattern.tuple (Elm.Pattern.variant1 "Just" (routeToSyntaxPattern route))
                                        (Elm.Pattern.variant1 (prefixedRouteType "Data" route) (Elm.Pattern.var "data"))
                                        |> Elm.Case.patternToBranch
                                            (\( maybeRouteParams, data ) ->
                                                Elm.Let.letIn
                                                    (\actionDataOrNothing ->
                                                        Elm.record
                                                            [ ( "view"
                                                              , Elm.fn ( "model", Nothing )
                                                                    (\model ->
                                                                        Elm.Case.custom (model |> Elm.get "page")
                                                                            Type.unit
                                                                            [ destructureRouteVariant Model "subModel" route
                                                                                |> Elm.Case.patternToBranch
                                                                                    (\subModel ->
                                                                                        Elm.apply
                                                                                            (Gen.Shared.values_.template
                                                                                                |> Elm.get "view"
                                                                                            )
                                                                                            [ globalData
                                                                                            , page
                                                                                            , model |> Elm.get "global"
                                                                                            , Elm.fn ( "myMsg", Nothing )
                                                                                                (\myMsg ->
                                                                                                    Gen.PagesMsg.fromMsg
                                                                                                        (Elm.apply (Elm.val "MsgGlobal") [ myMsg ])
                                                                                                )
                                                                                            , Gen.View.call_.map
                                                                                                (Elm.functionReduced
                                                                                                    "innerPageMsg"
                                                                                                    (Gen.PagesMsg.call_.map (route |> routeVariantExpression Msg))
                                                                                                )
                                                                                                (Elm.apply (route |> routeTemplateFunction "view")
                                                                                                    [ model |> Elm.get "global"
                                                                                                    , subModel
                                                                                                    , Elm.record
                                                                                                        [ ( "data", data )
                                                                                                        , ( "sharedData", globalData )
                                                                                                        , ( "routeParams", maybeRouteParams |> Maybe.withDefault (Elm.record []) )
                                                                                                        , ( "action", Gen.Maybe.andThen actionDataOrNothing actionData )
                                                                                                        , ( "path", page |> Elm.get "path" )
                                                                                                        , ( "url", maybePageUrl )
                                                                                                        , ( "submit"
                                                                                                          , Elm.functionReduced
                                                                                                                "fetcherArg"
                                                                                                                (Gen.Pages.Fetcher.call_.submit (decodeRouteType ActionData route))
                                                                                                          )
                                                                                                        , ( "navigation", navigation )
                                                                                                        , ( "concurrentSubmissions"
                                                                                                          , concurrentSubmissions
                                                                                                                |> Gen.Dict.map
                                                                                                                    (\_ fetcherState ->
                                                                                                                        fetcherState
                                                                                                                            |> Gen.Pages.ConcurrentSubmission.map (\ad -> actionDataOrNothing ad)
                                                                                                                    )
                                                                                                          )
                                                                                                        , ( "pageFormState", pageFormState )
                                                                                                        ]
                                                                                                    ]
                                                                                                )
                                                                                            ]
                                                                                    )
                                                                            , Elm.Pattern.ignore
                                                                                |> Elm.Case.patternToBranch
                                                                                    (\() ->
                                                                                        modelMismatchView.value
                                                                                    )
                                                                            ]
                                                                    )
                                                              )
                                                            , ( "head"
                                                              , case phase of
                                                                    Browser ->
                                                                        Elm.list []

                                                                    Cli ->
                                                                        Elm.apply
                                                                            (route
                                                                                |> routeTemplateFunction "head"
                                                                            )
                                                                            [ Elm.record
                                                                                [ ( "data", data )
                                                                                , ( "sharedData", globalData )
                                                                                , ( "routeParams", maybeRouteParams |> Maybe.withDefault (Elm.record []) )
                                                                                , ( "action", Elm.nothing )
                                                                                , ( "path", page |> Elm.get "path" )
                                                                                , ( "url", Elm.nothing )
                                                                                , ( "submit", Elm.functionReduced "value" (Gen.Pages.Fetcher.call_.submit (decodeRouteType ActionData route)) )
                                                                                , ( "navigation", Elm.nothing )
                                                                                , ( "concurrentSubmissions", Gen.Dict.empty )
                                                                                , ( "pageFormState", Gen.Dict.empty )
                                                                                ]
                                                                            ]
                                                              )
                                                            ]
                                                    )
                                                    |> Elm.Let.fn "actionDataOrNothing"
                                                        ( "thisActionData", Nothing )
                                                        (\thisActionData ->
                                                            Elm.Case.custom thisActionData
                                                                Type.unit
                                                                (ignoreBranchIfNeeded
                                                                    { primary =
                                                                        destructureRouteVariant ActionData "justActionData" route
                                                                            |> Elm.Case.patternToBranch
                                                                                (\justActionData ->
                                                                                    Elm.just justActionData
                                                                                )
                                                                    , otherwise = Elm.nothing
                                                                    }
                                                                    routes
                                                                )
                                                        )
                                                    |> Elm.Let.toExpression
                                            )
                            in
                            Elm.Case.custom (Elm.tuple (page |> Elm.get "route") pageData)
                                Type.unit
                                ((Elm.Pattern.tuple Elm.Pattern.ignore (Elm.Pattern.variant1 "DataErrorPage____" (Elm.Pattern.var "data"))
                                    |> Elm.Case.patternToBranch
                                        (\( (), data ) ->
                                            Elm.record
                                                [ ( "view"
                                                  , Elm.fn ( "model", Nothing )
                                                        (\model ->
                                                            Elm.Case.custom (model |> Elm.get "page")
                                                                Type.unit
                                                                [ Elm.Pattern.variant1 "ModelErrorPage____"
                                                                    (Elm.Pattern.var "subModel")
                                                                    |> Elm.Case.patternToBranch
                                                                        (\subModel ->
                                                                            Elm.apply
                                                                                (Gen.Shared.values_.template
                                                                                    |> Elm.get "view"
                                                                                )
                                                                                [ globalData
                                                                                , page
                                                                                , model |> Elm.get "global"
                                                                                , Elm.fn ( "myMsg", Nothing )
                                                                                    (\myMsg ->
                                                                                        Gen.PagesMsg.fromMsg
                                                                                            (Elm.apply (Elm.val "MsgGlobal") [ myMsg ])
                                                                                    )
                                                                                , Gen.View.call_.map
                                                                                    (Elm.functionReduced "myMsg"
                                                                                        (\myMsg ->
                                                                                            Gen.PagesMsg.fromMsg
                                                                                                (Elm.apply (Elm.val "MsgErrorPage____") [ myMsg ])
                                                                                        )
                                                                                    )
                                                                                    (Gen.ErrorPage.call_.view
                                                                                        data
                                                                                        subModel
                                                                                    )
                                                                                ]
                                                                        )
                                                                , Elm.Pattern.ignore
                                                                    |> Elm.Case.patternToBranch
                                                                        (\() ->
                                                                            modelMismatchView.value
                                                                        )
                                                                ]
                                                        )
                                                  )
                                                , ( "head", Elm.list [] )
                                                ]
                                        )
                                 )
                                    :: (routes
                                            |> List.map routeToBranch
                                       )
                                    ++ [ Elm.Case.otherwise
                                            (\_ ->
                                                Elm.record
                                                    [ ( "view"
                                                      , Elm.fn ( "_", Nothing )
                                                            (\_ ->
                                                                Elm.record
                                                                    [ ( "title", Elm.string "Page not found" )
                                                                    , ( "body"
                                                                      , [ Gen.Html.div [] [ Gen.Html.text "This page could not be found." ] ]
                                                                            |> Elm.list
                                                                      )
                                                                    ]
                                                            )
                                                      )
                                                    , ( "head"
                                                      , Elm.list []
                                                      )
                                                    ]
                                            )
                                       ]
                                )
                                |> Elm.withType
                                    (Type.record
                                        [ ( "view"
                                          , Type.function [ Type.named [] "Model" ]
                                                (Type.record
                                                    [ ( "title", Type.string )
                                                    , ( "body"
                                                      , Gen.Html.annotation_.html
                                                            (Gen.PagesMsg.annotation_.pagesMsg (Type.named [] "Msg"))
                                                            |> Type.list
                                                      )
                                                    ]
                                                )
                                          )
                                        , ( "head", Type.list Gen.Head.annotation_.tag )
                                        ]
                                    )

                        _ ->
                            todo
                )

        modelMismatchView :
            { declaration : Elm.Declaration
            , value : Elm.Expression
            , valueFrom : List String -> Elm.Expression
            }
        modelMismatchView =
            Elm.Declare.topLevelValue "modelMismatchView"
                (Elm.record
                    [ ( "title", Elm.string "Model mismatch" )
                    , ( "body", [ Gen.Html.text "Model mismatch" ] |> Elm.list )
                    ]
                )

        subscriptions :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        subscriptions =
            Elm.Declare.fn3 "subscriptions"
                ( "route", Type.named [ "Route" ] "Route" |> Type.maybe |> Just )
                ( "path", pathType |> Just )
                ( "model", Type.named [] "Model" |> Just )
                (\route path model ->
                    subBatch
                        [ Elm.apply
                            (Gen.Shared.values_.template
                                |> Elm.get "subscriptions"
                            )
                            [ path
                            , model
                                |> Elm.get "global"
                            ]
                            |> subMap (Elm.val "MsgGlobal")
                        , templateSubscriptions.call route path model
                        ]
                        |> Elm.withType (subType (Type.named [] "Msg"))
                )

        onActionData :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        onActionData =
            Elm.Declare.fn "onActionData"
                ( "actionData", Type.named [] "ActionData" |> Just )
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        (routes
                            |> List.map
                                (\route ->
                                    route
                                        |> destructureRouteVariant ActionData "thisActionData"
                                        |> Elm.Case.patternToBranch
                                            (\thisActionData ->
                                                (Elm.value
                                                    { annotation = Nothing
                                                    , importFrom = "Route" :: RoutePattern.toModuleName route
                                                    , name = "route"
                                                    }
                                                    |> Elm.get "onAction"
                                                )
                                                    |> Gen.Maybe.map
                                                        (\onAction ->
                                                            Elm.apply
                                                                (route |> routeVariantExpression Msg)
                                                                [ Elm.apply onAction [ thisActionData ] ]
                                                        )
                                            )
                                )
                        )
                        |> Elm.withType (Type.maybe (Type.named [] "Msg"))
                )

        templateSubscriptions :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        templateSubscriptions =
            Elm.Declare.fn3 "templateSubscriptions"
                ( "route", Type.maybe (Type.named [ "Route" ] "Route") |> Just )
                ( "path", pathType |> Just )
                ( "model", Type.named [] "Model" |> Just )
                (\maybeRoute path model ->
                    Elm.Case.maybe maybeRoute
                        { nothing = Gen.Platform.Sub.values_.none
                        , just =
                            ( "justRoute"
                            , \justRoute ->
                                branchHelper justRoute
                                    (\route maybeRouteParams ->
                                        Elm.Case.custom (model |> Elm.get "page")
                                            Type.unit
                                            [ route
                                                |> destructureRouteVariant Model "templateModel"
                                                |> Elm.Case.patternToBranch
                                                    (\templateModel ->
                                                        Elm.apply
                                                            (Elm.value
                                                                { importFrom = "Route" :: RoutePattern.toModuleName route
                                                                , name = "route"
                                                                , annotation = Nothing
                                                                }
                                                                |> Elm.get "subscriptions"
                                                            )
                                                            [ maybeRouteParams |> Maybe.withDefault (Elm.record [])
                                                            , path
                                                            , templateModel
                                                            , model |> Elm.get "global"
                                                            ]
                                                            |> subMap (route |> routeVariantExpression Msg)
                                                    )
                                            , Elm.Case.otherwise (\_ -> Gen.Platform.Sub.values_.none)
                                            ]
                                    )
                            )
                        }
                        |> Elm.withType (subType (Type.named [] "Msg"))
                )

        dataForRoute :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        dataForRoute =
            Elm.Declare.fn2
                "dataForRoute"
                ( "requestPayload", Just Gen.Server.Request.annotation_.request )
                ( "maybeRoute", Type.maybe (Type.named [ "Route" ] "Route") |> Just )
                (\requestPayload maybeRoute ->
                    Elm.Case.maybe maybeRoute
                        { nothing =
                            Gen.BackendTask.succeed
                                (Gen.Server.Response.mapError Gen.Basics.never
                                    (Gen.Server.Response.withStatusCode 404
                                        (Gen.Server.Response.render (Elm.val "Data404NotFoundPage____"))
                                    )
                                )
                        , just =
                            ( "justRoute"
                            , \justRoute ->
                                branchHelper justRoute
                                    (\route maybeRouteParams ->
                                        Elm.apply
                                            (Elm.value
                                                { name = "route"
                                                , importFrom = "Route" :: (route |> RoutePattern.toModuleName)
                                                , annotation = Nothing
                                                }
                                                |> Elm.get "data"
                                            )
                                            [ requestPayload
                                            , maybeRouteParams
                                                |> Maybe.withDefault (Elm.record [])
                                            ]
                                            |> Gen.BackendTask.map
                                                (Gen.Server.Response.call_.map (Elm.val ("Data" ++ (RoutePattern.toModuleName route |> String.join "__"))))
                                    )
                            )
                        }
                        |> Elm.withType
                            (Gen.BackendTask.annotation_.backendTask
                                (Type.named [ "FatalError" ] "FatalError")
                                (Gen.Server.Response.annotation_.response
                                    (Type.named [] "PageData")
                                    (Type.named [ "ErrorPage" ] "ErrorPage")
                                )
                            )
                )

        action :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        action =
            Elm.Declare.fn2
                "action"
                ( "requestPayload", Just Gen.Server.Request.annotation_.request )
                ( "maybeRoute", Type.maybe (Type.named [ "Route" ] "Route") |> Just )
                (\requestPayload maybeRoute ->
                    Elm.Case.maybe maybeRoute
                        { nothing =
                            Gen.BackendTask.succeed
                                (Gen.Server.Response.plainText "TODO")
                        , just =
                            ( "justRoute"
                            , \justRoute ->
                                branchHelper justRoute
                                    (\route maybeRouteParams ->
                                        Elm.apply
                                            (Elm.value
                                                { name = "route"
                                                , importFrom = "Route" :: (route |> RoutePattern.toModuleName)
                                                , annotation = Nothing
                                                }
                                                |> Elm.get "action"
                                            )
                                            [ requestPayload
                                            , maybeRouteParams
                                                |> Maybe.withDefault (Elm.record [])
                                            ]
                                            |> Gen.BackendTask.map
                                                (Gen.Server.Response.call_.map
                                                    (route |> routeVariantExpression ActionData)
                                                )
                                    )
                            )
                        }
                        |> Elm.withType
                            (Gen.BackendTask.annotation_.backendTask
                                (Type.named [ "FatalError" ] "FatalError")
                                (Gen.Server.Response.annotation_.response
                                    (Type.named [] "ActionData")
                                    (Type.named [ "ErrorPage" ] "ErrorPage")
                                )
                            )
                )

        init :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        init =
            Elm.Declare.fn6 "init"
                ( "currentGlobalModel", Type.maybe (Type.named [ "Shared" ] "Model") |> Just )
                ( "userFlags", Type.named [ "Pages", "Flags" ] "Flags" |> Just )
                ( "sharedData", Type.named [ "Shared" ] "Data" |> Just )
                ( "pageData", Type.named [] "PageData" |> Just )
                ( "actionData", Type.named [] "ActionData" |> Type.maybe |> Just )
                ( "maybePagePath"
                , Type.record
                    [ ( "path"
                      , Type.record
                            [ ( "path", pathType )
                            , ( "query", Type.string |> Type.maybe )
                            , ( "fragment", Type.string |> Type.maybe )
                            ]
                      )
                    , ( "metadata", Type.maybe (Type.named [ "Route" ] "Route") )
                    , ( "pageUrl", Type.maybe (Type.named [ "Pages", "PageUrl" ] "PageUrl") )
                    ]
                    |> Type.maybe
                    |> Just
                )
                (\currentGlobalModel userFlags sharedData pageData actionData maybePagePath ->
                    Elm.Let.letIn
                        (\( sharedModel, globalCmd ) ->
                            Elm.Let.letIn
                                (\( templateModel, templateCmd ) ->
                                    Elm.tuple
                                        (Elm.record
                                            [ ( "global", sharedModel )
                                            , ( "page", templateModel )
                                            , ( "current", maybePagePath )
                                            ]
                                        )
                                        (Gen.Effect.call_.batch
                                            (Elm.list
                                                [ templateCmd
                                                , Gen.Effect.call_.map
                                                    (Elm.val "MsgGlobal")
                                                    globalCmd
                                                ]
                                            )
                                        )
                                )
                                |> Elm.Let.tuple "templateModel"
                                    "templateCmd"
                                    (Elm.Case.maybe
                                        (Gen.Maybe.map2 Gen.Tuple.pair
                                            (maybePagePath |> Gen.Maybe.andThen (Elm.get "metadata"))
                                            (maybePagePath |> Gen.Maybe.map (Elm.get "path"))
                                        )
                                        { nothing = initErrorPage.call pageData
                                        , just =
                                            ( "justRouteAndPath"
                                            , \justRouteAndPath ->
                                                Elm.Case.custom (Elm.tuple (Gen.Tuple.first justRouteAndPath) pageData)
                                                    Type.unit
                                                    ((routes
                                                        |> List.map
                                                            (\route ->
                                                                Elm.Pattern.tuple
                                                                    (routeToSyntaxPattern route)
                                                                    (route |> destructureRouteVariant Data "thisPageData")
                                                                    |> Elm.Case.patternToBranch
                                                                        (\( maybeRouteParams, thisPageData ) ->
                                                                            Elm.apply
                                                                                (Elm.value
                                                                                    { name = "route"
                                                                                    , importFrom = "Route" :: RoutePattern.toModuleName route
                                                                                    , annotation = Nothing
                                                                                    }
                                                                                    |> Elm.get "init"
                                                                                )
                                                                                [ sharedModel
                                                                                , Elm.record
                                                                                    [ ( "data", thisPageData )
                                                                                    , ( "sharedData", sharedData )
                                                                                    , ( "action"
                                                                                      , actionData
                                                                                            |> Gen.Maybe.andThen
                                                                                                (\justActionData ->
                                                                                                    Elm.Case.custom justActionData
                                                                                                        Type.unit
                                                                                                        (ignoreBranchIfNeeded
                                                                                                            { primary =
                                                                                                                route
                                                                                                                    |> destructureRouteVariant ActionData "thisActionData"
                                                                                                                    |> Elm.Case.patternToBranch
                                                                                                                        (\thisActionData ->
                                                                                                                            Elm.just thisActionData
                                                                                                                        )
                                                                                                            , otherwise = Elm.nothing
                                                                                                            }
                                                                                                            routes
                                                                                                        )
                                                                                                )
                                                                                      )
                                                                                    , ( "routeParams", maybeRouteParams |> Maybe.withDefault (Elm.record []) )
                                                                                    , ( "path"
                                                                                      , Elm.apply (Elm.val ".path") [ justRouteAndPath |> Gen.Tuple.second ]
                                                                                      )
                                                                                    , ( "url"
                                                                                      , Gen.Maybe.andThen (Elm.get "pageUrl") maybePagePath
                                                                                      )
                                                                                    , ( "submit"
                                                                                      , Elm.apply
                                                                                            Gen.Pages.Fetcher.values_.submit
                                                                                            [ route |> decodeRouteType ActionData
                                                                                            ]
                                                                                      )
                                                                                    , ( "navigation", Elm.nothing )
                                                                                    , ( "concurrentSubmissions", Gen.Dict.empty )
                                                                                    , ( "pageFormState", Gen.Dict.empty )
                                                                                    ]
                                                                                ]
                                                                                |> Gen.Tuple.call_.mapBoth
                                                                                    (route |> routeVariantExpression Model)
                                                                                    (Elm.apply
                                                                                        Gen.Effect.values_.map
                                                                                        [ route |> routeVariantExpression Msg
                                                                                        ]
                                                                                    )
                                                                        )
                                                            )
                                                     )
                                                        ++ [ Elm.Pattern.ignore |> Elm.Case.patternToBranch (\() -> initErrorPage.call pageData)
                                                           ]
                                                    )
                                            )
                                        }
                                    )
                                |> Elm.Let.toExpression
                        )
                        |> Elm.Let.tuple "sharedModel"
                            "globalCmd"
                            (currentGlobalModel
                                |> Gen.Maybe.map
                                    (\m ->
                                        Elm.tuple m Gen.Effect.values_.none
                                    )
                                |> Gen.Maybe.withDefault
                                    (Elm.apply
                                        (Gen.Shared.values_.template
                                            |> Elm.get "init"
                                        )
                                        [ userFlags, maybePagePath ]
                                    )
                            )
                        |> Elm.Let.toExpression
                        |> Elm.withType
                            (Type.tuple
                                (Type.named [] "Model")
                                (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ])
                            )
                )

        update :
            { declaration : Elm.Declaration
            , call : List Elm.Expression -> Elm.Expression
            , callFrom : List String -> List Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        update =
            Elm.Declare.function "update"
                [ ( "pageFormState", Type.named [ "Form" ] "Model" |> Just )
                , ( "concurrentSubmissions"
                  , Gen.Dict.annotation_.dict
                        Type.string
                        (Gen.Pages.ConcurrentSubmission.annotation_.concurrentSubmission (Type.named [] "ActionData"))
                        |> Just
                  )
                , ( "navigation", Type.named [ "Pages", "Navigation" ] "Navigation" |> Type.maybe |> Just )
                , ( "sharedData", Type.named [ "Shared" ] "Data" |> Just )
                , ( "pageData", Type.named [] "PageData" |> Just )
                , ( "navigationKey", Type.named [ "Browser", "Navigation" ] "Key" |> Type.maybe |> Just )
                , ( "msg", Type.named [] "Msg" |> Just )
                , ( "model", Type.named [] "Model" |> Just )
                ]
                (\args ->
                    case args of
                        [ pageFormState, concurrentSubmissions, navigation, sharedData, pageData, navigationKey, msg, model ] ->
                            let
                                routeToBranch route =
                                    (route |> destructureRouteVariant Msg "msg_")
                                        |> Elm.Case.patternToBranch
                                            (\msg_ ->
                                                Elm.Case.custom
                                                    (Elm.triple
                                                        (model |> Elm.get "page")
                                                        pageData
                                                        (Gen.Maybe.call_.map3
                                                            (toTriple.value [])
                                                            (model
                                                                |> Elm.get "current"
                                                                |> Gen.Maybe.andThen
                                                                    (Elm.get "metadata")
                                                            )
                                                            (model
                                                                |> Elm.get "current"
                                                                |> Gen.Maybe.andThen
                                                                    (Elm.get "pageUrl")
                                                            )
                                                            (model
                                                                |> Elm.get "current"
                                                                |> Gen.Maybe.map
                                                                    (Elm.get "path")
                                                            )
                                                        )
                                                    )
                                                    Type.unit
                                                    [ Elm.Pattern.triple
                                                        (route |> destructureRouteVariant Model "pageModel")
                                                        (route |> destructureRouteVariant Data "thisPageData")
                                                        (Elm.Pattern.variant1
                                                            "Just"
                                                            (Elm.Pattern.triple
                                                                (routeToSyntaxPattern route)
                                                                (Elm.Pattern.var "pageUrl")
                                                                (Elm.Pattern.var "justPage")
                                                            )
                                                        )
                                                        |> Elm.Case.patternToBranch
                                                            (\( pageModel, thisPageData, ( maybeRouteParams, pageUrl, justPage ) ) ->
                                                                Elm.Let.letIn
                                                                    (\( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) ->
                                                                        Elm.tuple
                                                                            (model
                                                                                |> Elm.updateRecord
                                                                                    [ ( "page", updatedPageModel )
                                                                                    , ( "global", newGlobalModel )
                                                                                    ]
                                                                            )
                                                                            (Gen.Effect.call_.batch
                                                                                (Elm.list
                                                                                    [ pageCmd
                                                                                    , Gen.Effect.call_.map
                                                                                        (Elm.val "MsgGlobal")
                                                                                        newGlobalCmd
                                                                                    ]
                                                                                )
                                                                            )
                                                                    )
                                                                    |> Elm.Let.destructure
                                                                        (Elm.Pattern.triple
                                                                            (Elm.Pattern.var "updatedPageModel")
                                                                            (Elm.Pattern.var "pageCmd")
                                                                            (Elm.Pattern.tuple (Elm.Pattern.var "newGlobalModel")
                                                                                (Elm.Pattern.var "newGlobalCmd")
                                                                            )
                                                                        )
                                                                        (fooFn.call
                                                                            (route |> routeVariantExpression Model)
                                                                            (route |> routeVariantExpression Msg)
                                                                            model
                                                                            (Elm.apply
                                                                                (Elm.value
                                                                                    { annotation = Nothing
                                                                                    , importFrom = "Route" :: RoutePattern.toModuleName route
                                                                                    , name = "route"
                                                                                    }
                                                                                    |> Elm.get "update"
                                                                                )
                                                                                [ Elm.record
                                                                                    [ ( "data", thisPageData )
                                                                                    , ( "sharedData", sharedData )
                                                                                    , ( "action", Elm.nothing )
                                                                                    , ( "routeParams", maybeRouteParams |> Maybe.withDefault (Elm.record []) )
                                                                                    , ( "path", justPage |> Elm.get "path" )
                                                                                    , ( "url", Elm.just pageUrl )
                                                                                    , ( "submit", Elm.fn ( "options", Nothing ) (Gen.Pages.Fetcher.call_.submit (decodeRouteType ActionData route)) )
                                                                                    , ( "navigation", navigation )
                                                                                    , ( "concurrentSubmissions"
                                                                                      , concurrentSubmissions
                                                                                            |> Gen.Dict.map
                                                                                                (\_ fetcherState ->
                                                                                                    fetcherState
                                                                                                        |> Gen.Pages.ConcurrentSubmission.map
                                                                                                            (\ad ->
                                                                                                                Elm.Case.custom ad
                                                                                                                    Type.unit
                                                                                                                    (ignoreBranchIfNeeded
                                                                                                                        { primary =
                                                                                                                            route
                                                                                                                                |> destructureRouteVariant ActionData "justActionData"
                                                                                                                                |> Elm.Case.patternToBranch
                                                                                                                                    (\justActionData ->
                                                                                                                                        Elm.just justActionData
                                                                                                                                    )
                                                                                                                        , otherwise = Elm.nothing
                                                                                                                        }
                                                                                                                        routes
                                                                                                                    )
                                                                                                            )
                                                                                                )
                                                                                      )
                                                                                    , ( "pageFormState", pageFormState )
                                                                                    ]
                                                                                , msg_
                                                                                , pageModel
                                                                                , model |> Elm.get "global"
                                                                                ]
                                                                            )
                                                                        )
                                                                    |> Elm.Let.toExpression
                                                            )
                                                    , Elm.Pattern.ignore
                                                        |> Elm.Case.patternToBranch
                                                            (\() ->
                                                                Elm.tuple model Gen.Effect.values_.none
                                                            )
                                                    ]
                                            )
                            in
                            Elm.Case.custom msg
                                Type.unit
                                ([ Elm.Pattern.variant1 "MsgErrorPage____" (Elm.Pattern.var "msg_")
                                    |> Elm.Case.patternToBranch
                                        (\msg_ ->
                                            Elm.Let.letIn
                                                (\( updatedPageModel, pageCmd ) ->
                                                    Elm.tuple
                                                        (Elm.updateRecord
                                                            [ ( "page", updatedPageModel )
                                                            ]
                                                            model
                                                        )
                                                        pageCmd
                                                )
                                                |> Elm.Let.destructure (Elm.Pattern.tuple (Elm.Pattern.var "updatedPageModel") (Elm.Pattern.var "pageCmd"))
                                                    (Elm.Case.custom (Elm.tuple (model |> Elm.get "page") pageData)
                                                        Type.unit
                                                        [ Elm.Pattern.tuple (Elm.Pattern.variant1 "ModelErrorPage____" (Elm.Pattern.var "pageModel"))
                                                            (Elm.Pattern.variant1 "DataErrorPage____" (Elm.Pattern.var "thisPageData"))
                                                            |> Elm.Case.patternToBranch
                                                                (\( pageModel, thisPageData ) ->
                                                                    Gen.ErrorPage.call_.update
                                                                        thisPageData
                                                                        msg_
                                                                        pageModel
                                                                        |> Gen.Tuple.call_.mapBoth (Elm.val "ModelErrorPage____")
                                                                            (effectMap_ (Elm.val "MsgErrorPage____"))
                                                                )
                                                        , Elm.Pattern.ignore
                                                            |> Elm.Case.patternToBranch
                                                                (\() ->
                                                                    Elm.tuple (model |> Elm.get "page") Gen.Effect.values_.none
                                                                )
                                                        ]
                                                    )
                                                |> Elm.Let.toExpression
                                        )
                                 , Elm.Pattern.variant1 "MsgGlobal" (Elm.Pattern.var "msg_")
                                    |> Elm.Case.patternToBranch
                                        (\msg_ ->
                                            Elm.Let.letIn
                                                (\( sharedModel, globalCmd ) ->
                                                    Elm.tuple
                                                        (Elm.updateRecord [ ( "global", sharedModel ) ] model)
                                                        (effectMap (Elm.val "MsgGlobal") globalCmd)
                                                )
                                                |> Elm.Let.destructure (Elm.Pattern.tuple (Elm.Pattern.var "sharedModel") (Elm.Pattern.var "globalCmd"))
                                                    (Elm.apply
                                                        (Gen.Shared.values_.template
                                                            |> Elm.get "update"
                                                        )
                                                        [ msg_, model |> Elm.get "global" ]
                                                    )
                                                |> Elm.Let.toExpression
                                        )
                                 , Elm.Pattern.variant1 "OnPageChange" (Elm.Pattern.var "record")
                                    |> Elm.Case.patternToBranch
                                        (\record ->
                                            Elm.Let.letIn
                                                (\() ( updatedModel, cmd ) ->
                                                    Elm.Case.maybe
                                                        (Gen.Shared.values_.template
                                                            |> Elm.get "onPageChange"
                                                        )
                                                        { nothing = Elm.tuple updatedModel cmd
                                                        , just =
                                                            ( "thingy"
                                                            , \thingy ->
                                                                Elm.Let.letIn
                                                                    (\( updatedGlobalModel, globalCmd ) ->
                                                                        Elm.tuple (Elm.updateRecord [ ( "global", updatedGlobalModel ) ] updatedModel)
                                                                            (Gen.Effect.call_.batch
                                                                                (Elm.list
                                                                                    [ cmd
                                                                                    , effectMap (Elm.val "MsgGlobal") globalCmd
                                                                                    ]
                                                                                )
                                                                            )
                                                                    )
                                                                    |> Elm.Let.destructure (Elm.Pattern.tuple (Elm.Pattern.var "updatedGlobalModel") (Elm.Pattern.var "globalCmd"))
                                                                        (Elm.apply
                                                                            (Gen.Shared.values_.template
                                                                                |> Elm.get "update"
                                                                            )
                                                                            [ Elm.apply thingy
                                                                                [ Elm.record
                                                                                    [ ( "path", record |> Elm.get "path" )
                                                                                    , ( "query", record |> Elm.get "query" )
                                                                                    , ( "fragment", record |> Elm.get "fragment" )
                                                                                    ]
                                                                                ]
                                                                            , model |> Elm.get "global"
                                                                            ]
                                                                        )
                                                                    |> Elm.Let.toExpression
                                                            )
                                                        }
                                                )
                                                |> Elm.Let.destructure
                                                    -- TODO there is a bug where the Browser.Navigation.Key type wasn't imported because the argument wasn't referenced.
                                                    -- Remove this hack when that bug is fixed
                                                    Elm.Pattern.ignore
                                                    navigationKey
                                                |> Elm.Let.destructure (Elm.Pattern.tuple (Elm.Pattern.var "updatedModel") (Elm.Pattern.var "cmd"))
                                                    (init.call
                                                        (Elm.just (model |> Elm.get "global"))
                                                        (Elm.value { importFrom = [ "Pages", "Flags" ], name = "PreRenderFlags", annotation = Nothing })
                                                        sharedData
                                                        pageData
                                                        Elm.nothing
                                                        (Elm.just
                                                            (Elm.record
                                                                [ ( "path"
                                                                  , Elm.record
                                                                        [ ( "path", record |> Elm.get "path" )
                                                                        , ( "query", record |> Elm.get "query" )
                                                                        , ( "fragment", record |> Elm.get "fragment" )
                                                                        ]
                                                                  )
                                                                , ( "metadata", record |> Elm.get "metadata" )
                                                                , ( "pageUrl"
                                                                  , Elm.record
                                                                        [ ( "protocol", record |> Elm.get "protocol" )
                                                                        , ( "host", record |> Elm.get "host" )
                                                                        , ( "port_", record |> Elm.get "port_" )
                                                                        , ( "path", record |> Elm.get "path" )
                                                                        , ( "query", record |> Elm.get "query" |> Gen.Maybe.map Gen.Pages.PageUrl.call_.parseQueryParams |> Gen.Maybe.withDefault Gen.Dict.empty )
                                                                        , ( "fragment", record |> Elm.get "fragment" )
                                                                        ]
                                                                        |> Elm.just
                                                                  )
                                                                ]
                                                            )
                                                        )
                                                    )
                                                |> Elm.Let.toExpression
                                        )
                                 ]
                                    ++ (routes
                                            |> List.map routeToBranch
                                       )
                                )
                                |> Elm.withType
                                    (Type.tuple
                                        (Type.named [] "Model")
                                        (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ])
                                    )

                        _ ->
                            todo
                )

        fooFn :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        fooFn =
            Elm.Declare.fn4 "fooFn"
                ( "wrapModel"
                , Type.function [ Type.var "a" ]
                    (Type.named [] "PageModel")
                    |> Just
                )
                ( "wrapMsg"
                , Type.function [ Type.var "b" ]
                    (Type.named [] "Msg")
                    |> Just
                )
                ( "model", Type.named [] "Model" |> Just )
                ( "triple"
                , Type.triple
                    (Type.var "a")
                    (Type.namedWith [ "Effect" ] "Effect" [ Type.var "b" ])
                    (Type.maybe (Type.named [ "Shared" ] "Msg"))
                    |> Just
                )
                (\wrapModel wrapMsg model triple ->
                    Elm.Case.custom triple
                        Type.unit
                        [ Elm.Pattern.triple
                            (Elm.Pattern.var "a")
                            (Elm.Pattern.var "b")
                            (Elm.Pattern.var "c")
                            |> Elm.Case.patternToBranch
                                (\( a, b, c ) ->
                                    Elm.triple
                                        (Elm.apply wrapModel [ a ])
                                        (Gen.Effect.call_.map
                                            wrapMsg
                                            b
                                        )
                                        (Elm.Case.maybe c
                                            { nothing =
                                                Elm.tuple
                                                    (model |> Elm.get "global")
                                                    Gen.Effect.values_.none
                                            , just =
                                                ( "sharedMsg"
                                                , \sharedMsg ->
                                                    Elm.apply
                                                        (Gen.Shared.values_.template
                                                            |> Elm.get "update"
                                                        )
                                                        [ sharedMsg
                                                        , model |> Elm.get "global"
                                                        ]
                                                )
                                            }
                                        )
                                )
                        ]
                        |> Elm.withType
                            (Type.triple
                                (Type.named [] "PageModel")
                                (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ])
                                (Type.tuple (Type.named [ "Shared" ] "Model")
                                    (Type.namedWith [ "Effect" ] "Effect" [ Type.named [ "Shared" ] "Msg" ])
                                )
                            )
                )

        toTriple :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        toTriple =
            Elm.Declare.fn3 "toTriple"
                ( "a", Nothing )
                ( "b", Nothing )
                ( "c", Nothing )
                (\a b c -> Elm.triple a b c)

        initErrorPage :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        initErrorPage =
            Elm.Declare.fn "initErrorPage"
                ( "pageData", Type.named [] "PageData" |> Just )
                (\pageData ->
                    Gen.ErrorPage.call_.init
                        (Elm.Case.custom pageData
                            Type.unit
                            [ Elm.Case.branch1 "DataErrorPage____"
                                ( "errorPage", Type.unit )
                                (\errorPage -> errorPage)
                            , Elm.Case.otherwise (\_ -> Gen.ErrorPage.values_.notFound)
                            ]
                        )
                        |> Gen.Tuple.call_.mapBoth (Elm.val "ModelErrorPage____") (Elm.apply Gen.Effect.values_.map [ Elm.val "MsgErrorPage____" ])
                        |> Elm.withType (Type.tuple (Type.named [] "PageModel") (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ]))
                )

        handleRoute :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        handleRoute =
            Elm.Declare.fn "handleRoute"
                ( "maybeRoute", Type.maybe (Type.named [ "Route" ] "Route") |> Just )
                (\maybeRoute ->
                    Elm.Case.maybe maybeRoute
                        { nothing = Gen.BackendTask.succeed Elm.nothing
                        , just =
                            ( "route"
                            , \justRoute ->
                                branchHelper justRoute
                                    (\route innerRecord ->
                                        Elm.apply
                                            (Elm.value
                                                { annotation = Nothing
                                                , importFrom = "Route" :: RoutePattern.toModuleName route
                                                , name = "route"
                                                }
                                                |> Elm.get "handleRoute"
                                            )
                                            [ Elm.record
                                                [ ( "moduleName"
                                                  , RoutePattern.toModuleName route
                                                        |> List.map Elm.string
                                                        |> Elm.list
                                                  )
                                                , ( "routePattern"
                                                  , routePatternToExpression route
                                                  )
                                                ]
                                            , Elm.fn ( "param", Nothing )
                                                (\routeParam ->
                                                    RoutePattern.toVariantName route
                                                        |> .params
                                                        |> List.filterMap
                                                            (\param ->
                                                                case param of
                                                                    RoutePattern.OptionalParam2 name ->
                                                                        ( name
                                                                        , maybeToString.call (routeParam |> Elm.get name)
                                                                        )
                                                                            |> Just

                                                                    RoutePattern.DynamicParam name ->
                                                                        ( name
                                                                        , stringToString.call (routeParam |> Elm.get name)
                                                                        )
                                                                            |> Just

                                                                    RoutePattern.RequiredSplatParam2 ->
                                                                        ( "splat"
                                                                        , nonEmptyToString.call (routeParam |> Elm.get "splat")
                                                                        )
                                                                            |> Just

                                                                    RoutePattern.OptionalSplatParam2 ->
                                                                        ( "splat"
                                                                        , listToString.call (routeParam |> Elm.get "splat")
                                                                        )
                                                                            |> Just

                                                                    RoutePattern.StaticParam _ ->
                                                                        Nothing
                                                            )
                                                        |> List.map (\( key, value ) -> Elm.tuple (Elm.string key) value)
                                                        |> Elm.list
                                                )
                                            , innerRecord |> Maybe.withDefault (Elm.record [])
                                            ]
                                    )
                            )
                        }
                        |> Elm.withType
                            (Gen.BackendTask.annotation_.backendTask
                                (Type.named [ "FatalError" ] "FatalError")
                                (Type.maybe Gen.Pages.Internal.NotFoundReason.annotation_.notFoundReason)
                            )
                )

        maybeToString : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        maybeToString =
            Elm.Declare.fn "maybeToString"
                ( "maybeString", Type.maybe Type.string |> Just )
                (\maybeString ->
                    Elm.Case.maybe maybeString
                        { nothing = Elm.string "Nothing"
                        , just =
                            ( "string"
                            , \string ->
                                Elm.Op.append
                                    (Elm.string "Just ")
                                    (stringToString.call string)
                            )
                        }
                )

        stringToString : { declaration : Elm.Declaration, call : Elm.Expression -> Elm.Expression, callFrom : List String -> Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
        stringToString =
            Elm.Declare.fn "stringToString"
                ( "string", Type.string |> Just )
                (\string ->
                    Elm.Op.append
                        (Elm.string "\"")
                        (Elm.Op.append
                            string
                            (Elm.string "\"")
                        )
                )

        nonEmptyToString :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        nonEmptyToString =
            Elm.Declare.fn "nonEmptyToString"
                ( "nonEmpty", Type.tuple Type.string (Type.list Type.string) |> Just )
                (\nonEmpty ->
                    Elm.Case.custom
                        nonEmpty
                        Type.unit
                        [ Elm.Pattern.tuple (Elm.Pattern.var "first") (Elm.Pattern.var "rest")
                            |> Elm.Case.patternToBranch
                                (\( first, rest ) ->
                                    append
                                        [ Elm.string "( "
                                        , stringToString.call first
                                        , Elm.string ", [ "
                                        , rest
                                            |> Gen.List.call_.map (stringToString.value [])
                                            |> Gen.String.call_.join (Elm.string ", ")
                                        , Elm.string " ] )"
                                        ]
                                )
                        ]
                )

        listToString :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        listToString =
            Elm.Declare.fn "listToString"
                ( "strings", Type.list Type.string |> Just )
                (\strings ->
                    append
                        [ Elm.string "[ "
                        , strings
                            |> Gen.List.call_.map (stringToString.value [])
                            |> Gen.String.call_.join (Elm.string ", ")
                        , Elm.string " ]"
                        ]
                )

        branchHelper : Elm.Expression -> (RoutePattern -> Maybe Elm.Expression -> Elm.Expression) -> Elm.Expression
        branchHelper routeExpression toInnerExpression =
            Elm.Case.custom routeExpression
                Type.unit
                (routes
                    |> List.map
                        (\route ->
                            let
                                moduleName : String
                                moduleName =
                                    "Route." ++ (RoutePattern.toModuleName route |> String.join "__")
                            in
                            if RoutePattern.hasRouteParams route then
                                Elm.Case.branch1 moduleName
                                    ( "routeParams", Type.unit )
                                    (\routeParams ->
                                        toInnerExpression route (Just routeParams)
                                    )

                            else
                                Elm.Case.branch0 moduleName
                                    (toInnerExpression route Nothing)
                        )
                )

        encodeActionData :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        encodeActionData =
            Elm.Declare.fn "encodeActionData"
                ( "actionData", Type.named [] "ActionData" |> Just )
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        (routes
                            |> List.map
                                (\route ->
                                    route
                                        |> destructureRouteVariant ActionData "thisActionData"
                                        |> Elm.Case.patternToBranch
                                            (\thisActionData ->
                                                Elm.apply
                                                    (route |> encodeRouteType ActionData)
                                                    [ thisActionData ]
                                            )
                                )
                        )
                        |> Elm.withType Gen.Bytes.Encode.annotation_.encoder
                )

        byteEncodePageData :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        byteEncodePageData =
            Elm.Declare.fn "byteEncodePageData"
                ( "pageData", Type.named [] "PageData" |> Just )
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        ([ Elm.Case.branch1
                            "DataErrorPage____"
                            ( "thisPageData", Type.unit )
                            (\thisPageData ->
                                Elm.apply
                                    (Elm.value
                                        { annotation = Nothing
                                        , importFrom = [ "ErrorPage" ]
                                        , name = "w3_encode_ErrorPage"
                                        }
                                    )
                                    [ thisPageData ]
                            )
                         , Elm.Case.branch0 "Data404NotFoundPage____" (Gen.Bytes.Encode.unsignedInt8 0)
                         ]
                            ++ (routes
                                    |> List.map
                                        (\route ->
                                            Elm.Case.branch1
                                                ("Data" ++ (RoutePattern.toModuleName route |> String.join "__"))
                                                ( "thisPageData", Type.unit )
                                                (\thisPageData ->
                                                    Elm.apply
                                                        (route |> encodeRouteType Data)
                                                        [ thisPageData ]
                                                )
                                        )
                               )
                        )
                        |> Elm.withType Gen.Bytes.Encode.annotation_.encoder
                )

        byteDecodePageData :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        byteDecodePageData =
            Elm.Declare.fn "byteDecodePageData"
                ( "route", Type.named [ "Route" ] "Route" |> Type.maybe |> Just )
                (\maybeRoute ->
                    Elm.Case.maybe maybeRoute
                        { nothing = Gen.Bytes.Decode.values_.fail
                        , just =
                            ( "route"
                            , \route_ ->
                                Elm.Case.custom route_
                                    Type.unit
                                    (routes
                                        |> List.map
                                            (\route ->
                                                let
                                                    mappedDecoder : Elm.Expression
                                                    mappedDecoder =
                                                        Gen.Bytes.Decode.call_.map
                                                            (Elm.val ("Data" ++ (RoutePattern.toModuleName route |> String.join "__")))
                                                            (decodeRouteType Data route)

                                                    routeVariant : String
                                                    routeVariant =
                                                        "Route." ++ (RoutePattern.toModuleName route |> String.join "__")
                                                in
                                                if RoutePattern.hasRouteParams route then
                                                    Elm.Case.branch1
                                                        routeVariant
                                                        ( "_", Type.unit )
                                                        (\_ ->
                                                            mappedDecoder
                                                        )

                                                else
                                                    Elm.Case.branch0 routeVariant mappedDecoder
                                            )
                                    )
                            )
                        }
                        |> Elm.withType (Gen.Bytes.Decode.annotation_.decoder (Type.named [] "PageData"))
                )

        pathsToGenerateHandler :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        pathsToGenerateHandler =
            topLevelValue "pathsToGenerateHandler"
                (Gen.ApiRoute.succeed
                    (Gen.BackendTask.map2
                        (\pageRoutes apiRoutes ->
                            Elm.Op.append pageRoutes
                                (apiRoutes
                                    |> Gen.List.call_.map (Elm.fn ( "api", Nothing ) (\api -> Elm.Op.append (Elm.string "/") api))
                                )
                                |> Gen.Json.Encode.call_.list Gen.Json.Encode.values_.string
                                |> Gen.Json.Encode.encode 0
                        )
                        (Gen.BackendTask.map
                            (Gen.List.call_.map
                                (Elm.fn ( "route", Nothing )
                                    (\route_ ->
                                        Elm.apply
                                            (Elm.value
                                                { name = "toPath"
                                                , importFrom = [ "Route" ]
                                                , annotation = Nothing
                                                }
                                            )
                                            [ route_ ]
                                            |> Gen.UrlPath.toAbsolute
                                    )
                                )
                            )
                            getStaticRoutes.reference
                        )
                        (Elm.Op.cons routePatterns.reference
                            (Elm.Op.cons apiPatterns.reference
                                (Gen.Api.call_.routes
                                    getStaticRoutes.reference
                                    (Elm.fn2 ( "a", Nothing ) ( "b", Nothing ) (\_ _ -> Elm.string ""))
                                )
                            )
                            |> Gen.List.call_.map Gen.ApiRoute.values_.getBuildTimeRoutes
                            |> Gen.BackendTask.call_.combine
                            |> Gen.BackendTask.call_.map Gen.List.values_.concat
                        )
                    )
                    |> Gen.ApiRoute.literal "all-paths.json"
                    |> Gen.ApiRoute.single
                )

        apiPatterns :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        apiPatterns =
            topLevelValue "apiPatterns"
                (Gen.ApiRoute.succeed
                    (Gen.Json.Encode.call_.list
                        Gen.Basics.values_.identity
                        (Gen.Api.call_.routes
                            getStaticRoutes.reference
                            (Elm.fn2 ( "a", Nothing ) ( "b", Nothing ) (\_ _ -> Elm.string ""))
                            |> Gen.List.call_.map Gen.ApiRoute.values_.toJson
                        )
                        |> Gen.Json.Encode.encode 0
                        |> Gen.BackendTask.succeed
                    )
                    |> Gen.ApiRoute.literal "api-patterns.json"
                    |> Gen.ApiRoute.single
                    |> Elm.withType
                        (Gen.ApiRoute.annotation_.apiRoute
                            Gen.ApiRoute.annotation_.response
                        )
                )

        routePatterns :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        routePatterns =
            topLevelValue "routePatterns"
                (Gen.ApiRoute.succeed
                    (Gen.Json.Encode.call_.list
                        (Elm.fn ( "info", Nothing )
                            (\info ->
                                Gen.Json.Encode.object
                                    [ Elm.tuple (Elm.string "kind") (Gen.Json.Encode.call_.string (info |> Elm.get "kind"))
                                    , Elm.tuple (Elm.string "pathPattern") (Gen.Json.Encode.call_.string (info |> Elm.get "pathPattern"))
                                    ]
                            )
                        )
                        (routes
                            |> List.concatMap
                                (\route ->
                                    let
                                        params =
                                            route
                                                |> RoutePattern.toVariantName
                                                |> .params
                                    in
                                    case params |> RoutePattern.repeatWithoutOptionalEnding of
                                        Just repeated ->
                                            [ ( route, repeated ), ( route, params ) ]

                                        Nothing ->
                                            [ ( route, params ) ]
                                )
                            |> List.map
                                (\( route, params ) ->
                                    let
                                        pattern : String
                                        pattern =
                                            "/"
                                                ++ (params
                                                        |> List.map
                                                            (\param ->
                                                                case param of
                                                                    RoutePattern.StaticParam name ->
                                                                        String.Case.toKebabCaseLower name

                                                                    RoutePattern.DynamicParam name ->
                                                                        ":" ++ String.Case.toCamelCaseLower name

                                                                    RoutePattern.OptionalParam2 name ->
                                                                        ":" ++ String.Case.toCamelCaseLower name

                                                                    RoutePattern.OptionalSplatParam2 ->
                                                                        "*"

                                                                    RoutePattern.RequiredSplatParam2 ->
                                                                        "*"
                                                            )
                                                        |> String.join "/"
                                                   )
                                    in
                                    Elm.record
                                        [ ( "pathPattern", Elm.string pattern )
                                        , ( "kind"
                                          , Elm.value
                                                { name = "route"
                                                , importFrom = "Route" :: (route |> RoutePattern.toModuleName)
                                                , annotation = Nothing
                                                }
                                                |> Elm.get "kind"
                                          )
                                        ]
                                )
                            |> Elm.list
                        )
                        |> Gen.Json.Encode.encode 0
                        |> Gen.BackendTask.succeed
                    )
                    |> Gen.ApiRoute.literal "route-patterns.json"
                    |> Gen.ApiRoute.single
                    |> Elm.withType
                        (Gen.ApiRoute.annotation_.apiRoute
                            Gen.ApiRoute.annotation_.response
                        )
                )

        globalHeadTags :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            , value : List String -> Elm.Expression
            }
        globalHeadTags =
            Elm.Declare.fn "globalHeadTags"
                ( "htmlToString"
                , Type.function
                    [ Type.maybe
                        (Type.record
                            [ ( "indent", Type.int )
                            , ( "newLines", Type.bool )
                            ]
                        )
                    , Gen.Html.annotation_.html Gen.Basics.annotation_.never
                    ]
                    Type.string
                    |> Just
                )
                (\htmlToString ->
                    Elm.Op.cons
                        (Gen.Site.values_.config
                            |> Elm.get "head"
                        )
                        (Gen.Api.call_.routes
                            getStaticRoutes.reference
                            htmlToString
                            |> Gen.List.call_.filterMap Gen.ApiRoute.values_.getGlobalHeadTagsBackendTask
                        )
                        |> Gen.BackendTask.call_.combine
                        |> Gen.BackendTask.call_.map Gen.List.values_.concat
                        |> Elm.withType
                            (Gen.BackendTask.annotation_.backendTask
                                (Type.named [ "FatalError" ] "FatalError")
                                (Type.list Gen.Head.annotation_.tag)
                            )
                )

        encodeResponse :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        encodeResponse =
            topLevelValue "encodeResponse"
                (Elm.apply
                    (Elm.value
                        { annotation = Nothing
                        , name = "w3_encode_ResponseSketch"
                        , importFrom =
                            [ "Pages", "Internal", "ResponseSketch" ]
                        }
                    )
                    [ Elm.val "w3_encode_PageData"
                    , Elm.val "w3_encode_ActionData"
                    , Elm.value
                        { annotation = Nothing
                        , name = "w3_encode_Data"
                        , importFrom =
                            [ "Shared" ]
                        }
                    ]
                    |> Elm.withType
                        (Type.function
                            [ Type.namedWith [ "Pages", "Internal", "ResponseSketch" ]
                                "ResponseSketch"
                                [ Type.named [] "PageData"
                                , Type.named [] "ActionData"
                                , Type.named [ "Shared" ] "Data"
                                ]
                            ]
                            Gen.Bytes.Encode.annotation_.encoder
                        )
                )

        decodeResponse :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        decodeResponse =
            topLevelValue "decodeResponse"
                (Elm.apply
                    (Elm.value
                        { annotation = Nothing
                        , name = "w3_decode_ResponseSketch"
                        , importFrom =
                            [ "Pages", "Internal", "ResponseSketch" ]
                        }
                    )
                    [ Elm.val "w3_decode_PageData"
                    , Elm.val "w3_decode_ActionData"
                    , Elm.value
                        { annotation = Nothing
                        , name = "w3_decode_Data"
                        , importFrom =
                            [ "Shared" ]
                        }
                    ]
                    |> Elm.withType
                        (Type.namedWith [ "Pages", "Internal", "ResponseSketch" ]
                            "ResponseSketch"
                            [ Type.named [] "PageData"
                            , Type.named [] "ActionData"
                            , Type.named [ "Shared" ] "Data"
                            ]
                            |> Gen.Bytes.Decode.annotation_.decoder
                        )
                )

        getStaticRoutes :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        getStaticRoutes =
            topLevelValue "getStaticRoutes"
                (Gen.BackendTask.combine
                    (routes
                        |> List.map
                            (\route ->
                                Elm.value
                                    { name = "route"
                                    , annotation = Nothing
                                    , importFrom = "Route" :: (route |> RoutePattern.toModuleName)
                                    }
                                    |> Elm.get "staticRoutes"
                                    |> Gen.BackendTask.map
                                        (Gen.List.call_.map
                                            (if RoutePattern.hasRouteParams route then
                                                Elm.value
                                                    { annotation = Nothing
                                                    , name =
                                                        (route |> RoutePattern.toModuleName)
                                                            |> String.join "__"
                                                    , importFrom = [ "Route" ]
                                                    }

                                             else
                                                fnIgnore
                                                    (Elm.value
                                                        { annotation = Nothing
                                                        , name =
                                                            (route |> RoutePattern.toModuleName)
                                                                |> String.join "__"
                                                        , importFrom = [ "Route" ]
                                                        }
                                                    )
                                            )
                                        )
                            )
                    )
                    |> Gen.BackendTask.call_.map Gen.List.values_.concat
                    |> Elm.withType
                        (Gen.BackendTask.annotation_.backendTask
                            (Type.named [ "FatalError" ] "FatalError")
                            (Type.list (Type.named [ "Route" ] "Route"))
                        )
                )
    in
    Elm.file [ "Main" ]
        [ Elm.alias "Model"
            (Type.record
                [ ( "global", Type.named [ "Shared" ] "Model" )
                , ( "page", Type.named [] "PageModel" )
                , ( "current"
                  , Type.maybe
                        (Type.record
                            [ ( "path"
                              , Type.record
                                    [ ( "path", Type.named [ "UrlPath" ] "UrlPath" )
                                    , ( "query", Type.string |> Type.maybe )
                                    , ( "fragment", Type.string |> Type.maybe )
                                    ]
                              )
                            , ( "metadata", Type.maybe (Type.named [ "Route" ] "Route") )
                            , ( "pageUrl", Type.maybe (Type.named [ "Pages", "PageUrl" ] "PageUrl") )
                            ]
                        )
                  )
                ]
            )
        , Elm.customType "PageModel"
            ((routes
                |> List.map
                    (\route ->
                        Elm.variantWith
                            ("Model"
                                ++ (RoutePattern.toModuleName route |> String.join "__")
                            )
                            [ Type.named
                                ("Route"
                                    :: RoutePattern.toModuleName route
                                )
                                "Model"
                            ]
                    )
             )
                ++ [ Elm.variantWith "ModelErrorPage____"
                        [ Type.named [ "ErrorPage" ] "Model" ]
                   , Elm.variant "NotFound"
                   ]
            )
        , Elm.customType "Msg"
            ((routes
                |> List.map
                    (\route ->
                        Elm.variantWith
                            ("Msg"
                                ++ (RoutePattern.toModuleName route |> String.join "__")
                            )
                            [ Type.named
                                ("Route"
                                    :: RoutePattern.toModuleName route
                                )
                                "Msg"
                            ]
                    )
             )
                ++ [ Elm.variantWith "MsgGlobal" [ Type.named [ "Shared" ] "Msg" ]
                   , Elm.variantWith "OnPageChange"
                        [ Type.record
                            [ ( "protocol", Gen.Url.annotation_.protocol )
                            , ( "host", Type.string )
                            , ( "port_", Type.maybe Type.int )
                            , ( "path", pathType )
                            , ( "query", Type.maybe Type.string )
                            , ( "fragment", Type.maybe Type.string )
                            , ( "metadata", Type.maybe (Type.named [ "Route" ] "Route") )
                            ]
                        ]
                   , Elm.variantWith "MsgErrorPage____" [ Type.named [ "ErrorPage" ] "Msg" ]
                   ]
            )
        , Elm.customType "PageData"
            ((routes
                |> List.map
                    (\route ->
                        Elm.variantWith
                            ("Data"
                                ++ (RoutePattern.toModuleName route |> String.join "__")
                            )
                            [ Type.named
                                ("Route"
                                    :: RoutePattern.toModuleName route
                                )
                                "Data"
                            ]
                    )
             )
                ++ [ Elm.variant "Data404NotFoundPage____"
                   , Elm.variantWith "DataErrorPage____" [ Type.named [ "ErrorPage" ] "ErrorPage" ]
                   ]
            )
        , Elm.customType "ActionData"
            (routes
                |> List.map
                    (\route ->
                        Elm.variantWith
                            ("ActionData"
                                ++ (RoutePattern.toModuleName route |> String.join "__")
                            )
                            [ Type.named
                                ("Route"
                                    :: RoutePattern.toModuleName route
                                )
                                "ActionData"
                            ]
                    )
            )
        , case phase of
            Browser ->
                Gen.Pages.Internal.Platform.application config
                    |> Elm.withType
                        (Type.namedWith [ "Platform" ]
                            "Program"
                            [ Gen.Pages.Internal.Platform.annotation_.flags
                            , Gen.Pages.Internal.Platform.annotation_.model (Type.named [] "Model")
                                (Type.named [] "PageData")
                                (Type.named [] "ActionData")
                                (Type.named [ "Shared" ] "Data")
                            , Gen.Pages.Internal.Platform.annotation_.msg
                                (Type.named [] "Msg")
                                (Type.named [] "PageData")
                                (Type.named [] "ActionData")
                                (Type.named [ "Shared" ] "Data")
                                (Type.named [ "ErrorPage" ] "ErrorPage")
                            ]
                        )
                    |> Elm.declaration "main"
                    |> expose

            Cli ->
                Gen.Pages.Internal.Platform.Cli.cliApplication config
                    |> Elm.withType
                        (Gen.Pages.Internal.Platform.Cli.annotation_.program
                            (Type.named [ "Route" ] "Route" |> Type.maybe)
                        )
                    |> Elm.declaration "main"
                    |> expose
        , dataForRoute.declaration
        , toTriple.declaration
        , action.declaration
        , fooFn.declaration
        , templateSubscriptions.declaration
        , onActionData.declaration
        , byteEncodePageData.declaration
        , byteDecodePageData.declaration
        , apiPatterns.declaration
        , init.declaration
        , update.declaration
        , view.declaration
        , maybeToString.declaration
        , stringToString.declaration
        , nonEmptyToString.declaration
        , listToString.declaration
        , initErrorPage.declaration
        , routePatterns.declaration
        , pathsToGenerateHandler.declaration
        , getStaticRoutes.declaration
        , handleRoute.declaration
        , encodeActionData.declaration
        , subscriptions.declaration
        , modelMismatchView.declaration
        , Elm.portOutgoing "sendPageData"
            (Type.record
                [ ( "oldThing", Gen.Json.Encode.annotation_.value )
                , ( "binaryPageData", Gen.Bytes.annotation_.bytes )
                ]
            )
        , globalHeadTags.declaration
        , encodeResponse.declaration
        , pathPatterns.declaration
        , decodeResponse.declaration
        , Elm.portIncoming "hotReloadData"
            [ Gen.Bytes.annotation_.bytes ]
        , Elm.portOutgoing "toJsPort"
            Gen.Json.Encode.annotation_.value
        , Elm.portIncoming "fromJsPort"
            [ Gen.Json.Decode.annotation_.value ]
        , Elm.portIncoming "gotBatchSub"
            [ Gen.Json.Decode.annotation_.value ]
        ]


routeToSyntaxPattern : RoutePattern -> Elm.Pattern.Pattern (Maybe Elm.Expression)
routeToSyntaxPattern route =
    let
        moduleName : String
        moduleName =
            "Route." ++ (RoutePattern.toModuleName route |> String.join "__")
    in
    if RoutePattern.hasRouteParams route then
        Elm.Pattern.variant1 moduleName
            (Elm.Pattern.var "routeParams" |> Elm.Pattern.map Just)

    else
        Elm.Pattern.variant0 moduleName
            |> Elm.Pattern.map (\() -> Nothing)


type RouteVariant
    = Data
    | ActionData
    | Model
    | Msg


routeVariantToString : RouteVariant -> String
routeVariantToString variant =
    case variant of
        Data ->
            "Data"

        ActionData ->
            "ActionData"

        Model ->
            "Model"

        Msg ->
            "Msg"


destructureRouteVariant : RouteVariant -> String -> RoutePattern -> Elm.Pattern.Pattern Elm.Expression
destructureRouteVariant variant varName route =
    let
        moduleName : String
        moduleName =
            routeVariantToString variant ++ (RoutePattern.toModuleName route |> String.join "__")
    in
    Elm.Pattern.variant1 moduleName
        (Elm.Pattern.var varName)


routeVariantExpression : RouteVariant -> RoutePattern -> Elm.Expression
routeVariantExpression variant route =
    let
        moduleName : String
        moduleName =
            routeVariantToString variant ++ (RoutePattern.toModuleName route |> String.join "__")
    in
    Elm.val moduleName


applyIdentityTo : Elm.Expression -> Elm.Expression
applyIdentityTo to =
    Elm.apply to [ Gen.Basics.values_.identity ]


todo : Elm.Expression
todo =
    Elm.apply (Elm.val "Debug.todo") [ Elm.string "" ]


pathType : Type.Annotation
pathType =
    Type.named [ "UrlPath" ] "UrlPath"


routePatternToExpression : RoutePattern -> Elm.Expression
routePatternToExpression route =
    Gen.Pages.Internal.RoutePattern.make_.routePattern
        { segments =
            route.segments
                |> List.map
                    (\segment ->
                        case segment of
                            RoutePattern.StaticSegment name ->
                                Gen.Pages.Internal.RoutePattern.make_.staticSegment (Elm.string (String.Case.toKebabCaseLower name))

                            RoutePattern.DynamicSegment name ->
                                Gen.Pages.Internal.RoutePattern.make_.dynamicSegment (Elm.string (String.Case.toCamelCaseLower name))
                    )
                |> Elm.list
        , ending =
            route.ending
                |> Maybe.map
                    (\ending ->
                        case ending of
                            RoutePattern.Optional name ->
                                Gen.Pages.Internal.RoutePattern.make_.optional (Elm.string (String.Case.toCamelCaseLower name))

                            RoutePattern.RequiredSplat ->
                                Gen.Pages.Internal.RoutePattern.make_.requiredSplat

                            RoutePattern.OptionalSplat ->
                                Gen.Pages.Internal.RoutePattern.make_.optionalSplat
                    )
                |> Elm.maybe
        }


effectMap : Elm.Expression -> Elm.Expression -> Elm.Expression
effectMap mapTo value =
    Gen.Effect.call_.map
        mapTo
        value


effectMap_ : Elm.Expression -> Elm.Expression
effectMap_ mapTo =
    Elm.apply
        Gen.Effect.values_.map
        [ mapTo ]


append : List Elm.Expression -> Elm.Expression
append expressions =
    case expressions |> List.reverse of
        first :: rest ->
            List.foldl Elm.Op.append
                first
                rest

        [] ->
            Elm.string ""


decodeRouteType : RouteVariant -> RoutePattern -> Elm.Expression
decodeRouteType variant route =
    Elm.value
        { annotation = Nothing
        , importFrom = "Route" :: RoutePattern.toModuleName route
        , name = "w3_decode_" ++ routeVariantToString variant
        }


encodeRouteType : RouteVariant -> RoutePattern -> Elm.Expression
encodeRouteType variant route =
    Elm.value
        { annotation = Nothing
        , importFrom = "Route" :: RoutePattern.toModuleName route
        , name = "w3_encode_" ++ routeVariantToString variant
        }


prefixedRouteType : String -> RoutePattern -> String
prefixedRouteType prefix route =
    prefix ++ (RoutePattern.toModuleName route |> String.join "__")


routeTemplateFunction : String -> RoutePattern -> Elm.Expression
routeTemplateFunction functionName route =
    Elm.value
        { annotation = Nothing
        , importFrom = "Route" :: RoutePattern.toModuleName route
        , name = "route"
        }
        |> Elm.get functionName


ignoreBranchIfNeeded : { primary : Elm.Case.Branch, otherwise : Elm.Expression } -> List b -> List Elm.Case.Branch
ignoreBranchIfNeeded info routes =
    [ info.primary |> Just
    , if List.length routes > 1 then
        Elm.Pattern.ignore |> Elm.Case.patternToBranch (\() -> info.otherwise) |> Just

      else
        Nothing
    ]
        |> List.filterMap identity


subBatch : List Elm.Expression -> Elm.Expression
subBatch batchArg =
    Gen.Platform.Sub.call_.batch
        (Elm.list batchArg)


subType : Type.Annotation -> Type.Annotation
subType inner =
    Type.namedWith [ "Platform", "Sub" ] "Sub" [ inner ]


subMap : Elm.Expression -> Elm.Expression -> Elm.Expression
subMap mapArg mapArg0 =
    Gen.Platform.Sub.call_.map
        mapArg
        mapArg0
