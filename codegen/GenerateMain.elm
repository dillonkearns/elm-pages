module GenerateMain exposing (..)

import Elm exposing (File)
import Elm.Annotation as Type
import Elm.Arg
import Elm.Case
import Elm.Declare
import Elm.Let
import Elm.Op
import Gen.Api
import Gen.ApiRoute
import Gen.BackendTask
import Gen.Basics
import Gen.Bytes
import Gen.Bytes.Decode
import Gen.Bytes.Encode
import Gen.Debug
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
            , update = update.value
            , subscriptions = subscriptions.value
            , sharedData =
                Gen.Shared.values_.template
                    |> Elm.get "data"
            , data = dataForRoute.value
            , action = action.value
            , onActionData = onActionData.value
            , view = view.value
            , handleRoute = handleRoute.value
            , getStaticRoutes =
                case phase of
                    Browser ->
                        Gen.BackendTask.succeed (Elm.list [])

                    Cli ->
                        getStaticRoutes.value
                            |> Gen.BackendTask.map (Gen.List.call_.map (Elm.functionReduced "x" Gen.Maybe.make_.just))
            , urlToRoute =
                Elm.value
                    { annotation = Nothing
                    , name = "urlToRoute"
                    , importFrom = [ "Route" ]
                    }
            , routeToPath =
                Elm.fn (Elm.Arg.var "route")
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
                Elm.fn (Elm.Arg.var "htmlToString")
                    (\htmlToString ->
                        case phase of
                            Browser ->
                                Elm.list []

                            Cli ->
                                Elm.Op.cons pathsToGenerateHandler.value
                                    (Elm.Op.cons routePatterns.value
                                        (Elm.Op.cons apiPatterns.value
                                            (Gen.Api.call_.routes
                                                getStaticRoutes.value
                                                htmlToString
                                            )
                                        )
                                    )
                    )
            , pathPatterns = pathPatterns.value
            , basePath =
                Elm.value
                    { name = "baseUrlAsPath"
                    , importFrom = [ "Route" ]
                    , annotation = Nothing
                    }
            , sendPageData = Elm.val "sendPageData"
            , byteEncodePageData = byteEncodePageData.value
            , byteDecodePageData = byteDecodePageData.value
            , encodeResponse = encodeResponse.value
            , encodeAction = encodeActionData.value
            , decodeResponse = decodeResponse.value
            , globalHeadTags =
                case phase of
                    Browser ->
                        Elm.nothing

                    Cli ->
                        Elm.just globalHeadTags.value
            , cmdToEffect = Gen.Effect.values_.fromCmd
            , perform = Gen.Effect.values_.perform
            , errorStatusCode = Gen.ErrorPage.values_.statusCode
            , notFoundPage = Gen.ErrorPage.values_.notFound
            , internalError = Gen.ErrorPage.values_.internalError
            , errorPageToData = Elm.val "DataErrorPage____"
            , notFoundRoute = Elm.nothing
            }
                |> make_
                |> Elm.withType Type.unit

        --|> Elm.withType
        --    (Gen.Pages.ProgramConfig.annotation_.programConfig
        --        (msgType.annotation)
        --        (modelType.annotation)
        --        (Type.maybe (Type.named [ "Route" ] "Route"))
        --        (pageDataType.annotation)
        --        (actionDataType.annotation)
        --        (Type.named [ "Shared" ] "Data")
        --        (Type.namedWith [ "Effect" ] "Effect" [ msgType.annotation ])
        --        (Type.var "mappedMsg")
        --        (Type.named [ "ErrorPage" ] "ErrorPage")
        --    )
        --|> Elm.Declare.value "config"
        pathPatterns : Elm.Declare.Value
        pathPatterns =
            Elm.Declare.value "routePatterns3"
                (routes
                    |> List.map routePatternToExpression
                    |> Elm.list
                )

        view : Elm.Declare.Function (List Elm.Expression -> Elm.Expression)
        view =
            Elm.Declare.function "view"
                [ ( "pageFormState", Type.named [ "Form" ] "Model" |> Just )
                , ( "concurrentSubmissions"
                  , Gen.Dict.annotation_.dict Type.string
                        (Gen.Pages.ConcurrentSubmission.annotation_.concurrentSubmission actionDataType.annotation)
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
                , ( "pageData", pageDataType.annotation |> Just )
                , ( "actionData", Type.maybe actionDataType.annotation |> Just )
                ]
                (\args ->
                    case args of
                        [ pageFormState, concurrentSubmissions, navigation, page, maybePageUrl, globalData, pageData, actionData ] ->
                            let
                                routeToBranch route =
                                    Elm.Case.branch
                                        (Elm.Arg.tuple
                                            (Elm.Arg.customType "Just" identity |> Elm.Arg.item (routeToSyntaxPattern route))
                                            (Elm.Arg.customType (prefixedRouteType "Data" route) identity |> Elm.Arg.item (Elm.Arg.var "data"))
                                        )
                                        (\( maybeRouteParams, data ) ->
                                            Elm.Let.letIn
                                                (\actionDataOrNothing ->
                                                    Elm.record
                                                        [ ( "view"
                                                          , Elm.fn (Elm.Arg.var "model")
                                                                (\model ->
                                                                    Elm.Case.custom (model |> Elm.get "page")
                                                                        Type.unit
                                                                        [ Elm.Case.branch
                                                                            (destructureRouteVariant Model "subModel" route)
                                                                            (\subModel ->
                                                                                Elm.apply
                                                                                    (Gen.Shared.values_.template
                                                                                        |> Elm.get "view"
                                                                                    )
                                                                                    [ globalData
                                                                                    , page
                                                                                    , model |> Elm.get "global"
                                                                                    , Elm.fn (Elm.Arg.var "myMsg")
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
                                                                                                , ( "staticViews", Elm.record [] )
                                                                                                ]
                                                                                            ]
                                                                                        )
                                                                                    ]
                                                                            )
                                                                        , Elm.Case.branch Elm.Arg.ignore (\_ -> modelMismatchView.value)
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
                                                                            , ( "staticViews", Elm.record [] )
                                                                            ]
                                                                        ]
                                                          )
                                                        ]
                                                )
                                                |> Elm.Let.fn "actionDataOrNothing"
                                                    (Elm.Arg.var "thisActionData")
                                                    (\thisActionData ->
                                                        Elm.Case.custom thisActionData
                                                            Type.unit
                                                            (ignoreBranchIfNeeded
                                                                { primary =
                                                                    Elm.Case.branch
                                                                        (destructureRouteVariant ActionData "justActionData" route)
                                                                        Elm.just
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
                                (Elm.Case.branch
                                    (Elm.Arg.tuple
                                        Elm.Arg.ignore
                                        (Elm.Arg.customType "DataErrorPage____" identity
                                            |> Elm.Arg.item (Elm.Arg.var "data")
                                        )
                                    )
                                    (\( _, data ) ->
                                        Elm.record
                                            [ ( "view"
                                              , Elm.fn (Elm.Arg.var "model")
                                                    (\model ->
                                                        Elm.Case.custom (model |> Elm.get "page")
                                                            Type.unit
                                                            [ Elm.Case.branch
                                                                (Elm.Arg.customType "ModelErrorPage____" identity
                                                                    |> Elm.Arg.item (Elm.Arg.var "subModel")
                                                                )
                                                                (\subModel ->
                                                                    Elm.apply
                                                                        (Gen.Shared.values_.template
                                                                            |> Elm.get "view"
                                                                        )
                                                                        [ globalData
                                                                        , page
                                                                        , model |> Elm.get "global"
                                                                        , Elm.fn (Elm.Arg.var "myMsg")
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
                                                            , Elm.Case.branch Elm.Arg.ignore (\_ -> modelMismatchView.value)
                                                            ]
                                                    )
                                              )
                                            , ( "head", Elm.list [] )
                                            ]
                                    )
                                    :: (routes
                                            |> List.map routeToBranch
                                       )
                                    ++ [ Elm.Case.branch
                                            Elm.Arg.ignore
                                            (\_ ->
                                                Elm.record
                                                    [ ( "view"
                                                      , Elm.fn Elm.Arg.ignore
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
                                          , Type.function [ modelType.annotation ]
                                                (Type.record
                                                    [ ( "title", Type.string )
                                                    , ( "body"
                                                      , Gen.Html.annotation_.html
                                                            (Gen.PagesMsg.annotation_.pagesMsg msgType.annotation)
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

        modelMismatchView : Elm.Declare.Value
        modelMismatchView =
            Elm.Declare.value "modelMismatchView"
                (Elm.record
                    [ ( "title", Elm.string "Model mismatch" )
                    , ( "body", [ Gen.Html.text "Model mismatch" ] |> Elm.list )
                    ]
                )

        subscriptions : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
        subscriptions =
            Elm.Declare.fn3 "subscriptions"
                (Elm.Arg.varWith "route" (Type.named [ "Route" ] "Route" |> Type.maybe))
                (Elm.Arg.varWith "path" pathType)
                (Elm.Arg.varWith "model" modelType.annotation)
                (\route path model ->
                    Gen.Platform.Sub.batch
                        [ Elm.apply
                            (Gen.Shared.values_.template
                                |> Elm.get "subscriptions"
                            )
                            [ path
                            , model
                                |> Elm.get "global"
                            ]
                            |> Gen.Platform.Sub.call_.map (Elm.val "MsgGlobal")
                        , templateSubscriptions.call route path model
                        ]
                        |> Elm.withType (Gen.Platform.Sub.annotation_.sub msgType.annotation)
                )

        onActionData : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        onActionData =
            Elm.Declare.fn "onActionData"
                (Elm.Arg.varWith "actionData" actionDataType.annotation)
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        (routes
                            |> List.map
                                (\route ->
                                    Elm.Case.branch
                                        (destructureRouteVariant ActionData "thisActionData" route)
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
                        |> Elm.withType (Type.maybe msgType.annotation)
                )

        templateSubscriptions : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
        templateSubscriptions =
            Elm.Declare.fn3 "templateSubscriptions"
                (Elm.Arg.varWith "route" (Type.maybe (Type.named [ "Route" ] "Route")))
                (Elm.Arg.varWith "path" pathType)
                (Elm.Arg.varWith "model" modelType.annotation)
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
                                            [ Elm.Case.branch
                                                (destructureRouteVariant Model "templateModel" route)
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
                                                        |> Gen.Platform.Sub.call_.map (route |> routeVariantExpression Msg)
                                                )
                                            , Elm.Case.branch Elm.Arg.ignore (\_ -> Gen.Platform.Sub.values_.none)
                                            ]
                                    )
                            )
                        }
                        |> Elm.withType (Gen.Platform.Sub.annotation_.sub msgType.annotation)
                )

        dataForRoute : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
        dataForRoute =
            Elm.Declare.fn2
                "dataForRoute"
                (Elm.Arg.varWith "requestPayload" Gen.Server.Request.annotation_.request)
                (Elm.Arg.varWith "maybeRoute" (Type.maybe (Type.named [ "Route" ] "Route")))
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
                                    pageDataType.annotation
                                    (Type.named [ "ErrorPage" ] "ErrorPage")
                                )
                            )
                )

        action : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
        action =
            Elm.Declare.fn2
                "action"
                (Elm.Arg.varWith "requestPayload" Gen.Server.Request.annotation_.request)
                (Elm.Arg.varWith "maybeRoute" (Type.maybe (Type.named [ "Route" ] "Route")))
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
                                    actionDataType.annotation
                                    (Type.named [ "ErrorPage" ] "ErrorPage")
                                )
                            )
                )

        init : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
        init =
            Elm.Declare.fn6 "init"
                (Elm.Arg.varWith "currentGlobalModel" (Type.maybe (Type.named [ "Shared" ] "Model")))
                (Elm.Arg.varWith "userFlags" (Type.named [ "Pages", "Flags" ] "Flags"))
                (Elm.Arg.varWith "sharedData" (Type.named [ "Shared" ] "Data"))
                (Elm.Arg.varWith "pageData" pageDataType.annotation)
                (Elm.Arg.varWith "actionData" (actionDataType.annotation |> Type.maybe))
                (Elm.Arg.varWith "maybePagePath"
                    (Type.record
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
                    )
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
                                |> Elm.Let.unpack
                                    (Elm.Arg.tuple
                                        (Elm.Arg.var "templateModel")
                                        (Elm.Arg.var "templateCmd")
                                    )
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
                                                                Elm.Case.branch
                                                                    (Elm.Arg.tuple
                                                                        (routeToSyntaxPattern route)
                                                                        (destructureRouteVariant Data "thisPageData" route)
                                                                    )
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
                                                                                                            Elm.Case.branch
                                                                                                                (destructureRouteVariant ActionData "thisActionData" route)
                                                                                                                Elm.just
                                                                                                        , otherwise = Elm.nothing
                                                                                                        }
                                                                                                        routes
                                                                                                    )
                                                                                            )
                                                                                  )
                                                                                , ( "routeParams", maybeRouteParams |> Maybe.withDefault (Elm.record []) )
                                                                                , ( "path"
                                                                                  , justRouteAndPath
                                                                                        |> Gen.Tuple.second
                                                                                        |> Elm.get "path"
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
                                                                                , ( "staticViews", Elm.record [] )
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
                                                        ++ [ Elm.Case.branch Elm.Arg.ignore (\_ -> initErrorPage.call pageData)
                                                           ]
                                                    )
                                            )
                                        }
                                    )
                                |> Elm.Let.toExpression
                        )
                        |> Elm.Let.unpack
                            (Elm.Arg.tuple
                                (Elm.Arg.var "sharedModel")
                                (Elm.Arg.var "globalCmd")
                            )
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
                                modelType.annotation
                                (Type.namedWith [ "Effect" ] "Effect" [ msgType.annotation ])
                            )
                )

        update : Elm.Declare.Function (List Elm.Expression -> Elm.Expression)
        update =
            Elm.Declare.function "update"
                [ ( "pageFormState", Type.named [ "Form" ] "Model" |> Just )
                , ( "concurrentSubmissions"
                  , Gen.Dict.annotation_.dict
                        Type.string
                        (Gen.Pages.ConcurrentSubmission.annotation_.concurrentSubmission actionDataType.annotation)
                        |> Just
                  )
                , ( "navigation", Type.named [ "Pages", "Navigation" ] "Navigation" |> Type.maybe |> Just )
                , ( "sharedData", Type.named [ "Shared" ] "Data" |> Just )
                , ( "pageData", pageDataType.annotation |> Just )
                , ( "navigationKey", Type.named [ "Browser", "Navigation" ] "Key" |> Type.maybe |> Just )
                , ( "msg", msgType.annotation |> Just )
                , ( "model", modelType.annotation |> Just )
                ]
                (\args ->
                    case args of
                        [ pageFormState, concurrentSubmissions, navigation, sharedData, pageData, navigationKey, msg, model ] ->
                            let
                                routeToBranch route =
                                    Elm.Case.branch
                                        (route |> destructureRouteVariant Msg "msg_")
                                        (\msg_ ->
                                            Elm.Case.custom
                                                (Elm.triple
                                                    (model |> Elm.get "page")
                                                    pageData
                                                    (Gen.Maybe.call_.map3
                                                        toTriple.value
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
                                                [ Elm.Case.branch
                                                    (Elm.Arg.triple
                                                        (route |> destructureRouteVariant Model "pageModel")
                                                        (route |> destructureRouteVariant Data "thisPageData")
                                                        (Elm.Arg.customType "Just" identity
                                                            |> Elm.Arg.item
                                                                (Elm.Arg.triple
                                                                    (routeToSyntaxPattern route)
                                                                    (Elm.Arg.var "pageUrl")
                                                                    (Elm.Arg.var "justPage")
                                                                )
                                                        )
                                                    )
                                                    (\( pageModel, thisPageData, ( maybeRouteParams, pageUrl, justPage ) ) ->
                                                        Elm.Let.letIn
                                                            (\( updatedPageModel, pageCmd, newGLobalModelAndCmd ) ->
                                                                Elm.Let.letIn
                                                                    (\( newGlobalModel, newGlobalCmd ) ->
                                                                        Elm.tuple
                                                                            (model
                                                                                |> Elm.updateRecord
                                                                                    [ ( "page", updatedPageModel )
                                                                                    , ( "global", newGlobalModel )
                                                                                    ]
                                                                            )
                                                                            (Gen.Effect.batch
                                                                                [ pageCmd
                                                                                , Gen.Effect.call_.map
                                                                                    (Elm.val "MsgGlobal")
                                                                                    newGlobalCmd
                                                                                ]
                                                                            )
                                                                    )
                                                                    |> Elm.Let.unpack
                                                                        (Elm.Arg.tuple
                                                                            (Elm.Arg.var "newGlobalModel")
                                                                            (Elm.Arg.var "newGlobalCmd")
                                                                        )
                                                                        newGLobalModelAndCmd
                                                                    |> Elm.Let.toExpression
                                                            )
                                                            |> Elm.Let.unpack
                                                                (Elm.Arg.triple
                                                                    (Elm.Arg.var "updatedPageModel")
                                                                    (Elm.Arg.var "pageCmd")
                                                                    (Elm.Arg.var "globalModelAndCmd")
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
                                                                            , ( "submit", Elm.fn (Elm.Arg.var "options") (Gen.Pages.Fetcher.call_.submit (decodeRouteType ActionData route)) )
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
                                                                                                                    Elm.Case.branch
                                                                                                                        (destructureRouteVariant ActionData "justActionData" route)
                                                                                                                        Elm.just
                                                                                                                , otherwise = Elm.nothing
                                                                                                                }
                                                                                                                routes
                                                                                                            )
                                                                                                    )
                                                                                        )
                                                                              )
                                                                            , ( "pageFormState", pageFormState )
                                                                            , ( "staticViews", Elm.record [] )
                                                                            ]
                                                                        , msg_
                                                                        , pageModel
                                                                        , model |> Elm.get "global"
                                                                        ]
                                                                    )
                                                                )
                                                            |> Elm.Let.toExpression
                                                    )
                                                , Elm.Case.branch Elm.Arg.ignore
                                                    (\_ -> Elm.tuple model Gen.Effect.values_.none)
                                                ]
                                        )
                            in
                            Elm.Case.custom msg
                                Type.unit
                                ([ Elm.Case.branch
                                    (Elm.Arg.customType "MsgErrorPage____" identity
                                        |> Elm.Arg.item (Elm.Arg.var "msg_")
                                    )
                                   <|
                                    \msg_ ->
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
                                            |> Elm.Let.unpack
                                                (Elm.Arg.tuple
                                                    (Elm.Arg.var "updatedPageModel")
                                                    (Elm.Arg.var "pageCmd")
                                                )
                                                (Elm.Case.custom (Elm.tuple (model |> Elm.get "page") pageData)
                                                    Type.unit
                                                    [ Elm.Case.branch
                                                        (Elm.Arg.tuple
                                                            (Elm.Arg.customType "ModelErrorPage____" identity
                                                                |> Elm.Arg.item (Elm.Arg.var "pageModel")
                                                            )
                                                            (Elm.Arg.customType "DataErrorPage____" identity
                                                                |> Elm.Arg.item (Elm.Arg.var "thisPageData")
                                                            )
                                                        )
                                                        (\( pageModel, thisPageData ) ->
                                                            Gen.ErrorPage.update
                                                                thisPageData
                                                                msg_
                                                                pageModel
                                                                |> Gen.Tuple.call_.mapBoth (Elm.val "ModelErrorPage____")
                                                                    (Elm.apply Gen.Effect.values_.map [ Elm.val "MsgErrorPage____" ])
                                                        )
                                                    , Elm.Case.branch Elm.Arg.ignore (\_ -> Elm.tuple (model |> Elm.get "page") Gen.Effect.values_.none)
                                                    ]
                                                )
                                            |> Elm.Let.toExpression
                                 , Elm.Case.branch
                                    (Elm.Arg.customType "MsgGlobal" identity
                                        |> Elm.Arg.item (Elm.Arg.var "msg_")
                                    )
                                   <|
                                    \msg_ ->
                                        Elm.Let.letIn
                                            (\( sharedModel, globalCmd ) ->
                                                Elm.tuple
                                                    (Elm.updateRecord [ ( "global", sharedModel ) ] model)
                                                    (Gen.Effect.call_.map (Elm.val "MsgGlobal") globalCmd)
                                            )
                                            |> Elm.Let.unpack
                                                (Elm.Arg.tuple
                                                    (Elm.Arg.var "sharedModel")
                                                    (Elm.Arg.var "globalCmd")
                                                )
                                                (Elm.apply
                                                    (Gen.Shared.values_.template
                                                        |> Elm.get "update"
                                                    )
                                                    [ msg_, model |> Elm.get "global" ]
                                                )
                                            |> Elm.Let.toExpression
                                 , Elm.Case.branch
                                    (Elm.Arg.customType "OnPageChange" identity
                                        |> Elm.Arg.item (Elm.Arg.var "record")
                                    )
                                   <|
                                    \record ->
                                        Elm.Let.letIn
                                            (\( updatedModel, cmd ) ->
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
                                                                        (Gen.Effect.batch
                                                                            [ cmd
                                                                            , Gen.Effect.call_.map (Elm.val "MsgGlobal") globalCmd
                                                                            ]
                                                                        )
                                                                )
                                                                |> Elm.Let.unpack
                                                                    (Elm.Arg.tuple
                                                                        (Elm.Arg.var "updatedGlobalModel")
                                                                        (Elm.Arg.var "globalCmd")
                                                                    )
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
                                            -- |> Elm.Let.destructure
                                            --     -- TODO there is a bug where the Browser.Navigation.Key type wasn't imported because the argument wasn't referenced.
                                            --     -- Remove this hack when that bug is fixed
                                            --     Elm.Case.branch Elm.Arg.ignore
                                            --     navigationKey
                                            |> Elm.Let.unpack
                                                (Elm.Arg.tuple
                                                    (Elm.Arg.var "updatedModel")
                                                    (Elm.Arg.var "cmd")
                                                )
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
                                 ]
                                    ++ (routes
                                            |> List.map routeToBranch
                                       )
                                )
                                |> Elm.withType
                                    (Type.tuple
                                        modelType.annotation
                                        (Type.namedWith [ "Effect" ] "Effect" [ msgType.annotation ])
                                    )

                        _ ->
                            todo
                )

        fooFn : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
        fooFn =
            Elm.Declare.fn4 "fooFn"
                (Elm.Arg.varWith "wrapModel"
                    (Type.function [ Type.var "a" ]
                        pageModelType.annotation
                    )
                )
                (Elm.Arg.varWith "wrapMsg"
                    (Type.function [ Type.var "b" ]
                        msgType.annotation
                    )
                )
                (Elm.Arg.varWith "model"
                    modelType.annotation
                )
                (Elm.Arg.varWith "triple"
                    (Type.triple
                        (Type.var "a")
                        (Type.namedWith [ "Effect" ] "Effect" [ Type.var "b" ])
                        (Type.maybe (Type.named [ "Shared" ] "Msg"))
                    )
                )
                (\wrapModel wrapMsg model triple ->
                    Elm.Case.custom triple
                        Type.unit
                        [ Elm.Case.branch
                            (Elm.Arg.triple
                                (Elm.Arg.var "a")
                                (Elm.Arg.var "b")
                                (Elm.Arg.var "c")
                            )
                            (\( a, b, c ) ->
                                Elm.triple
                                    (Elm.apply wrapModel [ a ])
                                    (Gen.Effect.call_.map wrapMsg b)
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
                                pageModelType.annotation
                                (Type.namedWith [ "Effect" ] "Effect" [ msgType.annotation ])
                                (Type.tuple (Type.named [ "Shared" ] "Model")
                                    (Type.namedWith [ "Effect" ] "Effect" [ Type.named [ "Shared" ] "Msg" ])
                                )
                            )
                )

        toTriple : Elm.Declare.Function (Elm.Expression -> Elm.Expression -> Elm.Expression -> Elm.Expression)
        toTriple =
            Elm.Declare.fn3 "toTriple"
                (Elm.Arg.var "a")
                (Elm.Arg.var "b")
                (Elm.Arg.var "c")
                (\a b c -> Elm.triple a b c)

        initErrorPage : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        initErrorPage =
            Elm.Declare.fn "initErrorPage"
                (Elm.Arg.varWith "pageData" pageDataType.annotation)
                (\pageData ->
                    Gen.ErrorPage.init
                        (Elm.Case.custom pageData
                            Type.unit
                            [ Elm.Case.branch
                                (Elm.Arg.customType "DataErrorPage____" identity
                                    |> Elm.Arg.item (Elm.Arg.var "errorPage")
                                )
                                identity
                            , Elm.Case.branch Elm.Arg.ignore (\_ -> Gen.ErrorPage.values_.notFound)
                            ]
                        )
                        |> Gen.Tuple.call_.mapBoth (Elm.val "ModelErrorPage____") (Elm.apply Gen.Effect.values_.map [ Elm.val "MsgErrorPage____" ])
                        |> Elm.withType (Type.tuple pageModelType.annotation (Type.namedWith [ "Effect" ] "Effect" [ msgType.annotation ]))
                )

        handleRoute : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        handleRoute =
            Elm.Declare.fn "handleRoute"
                (Elm.Arg.varWith "maybeRoute" (Type.maybe (Type.named [ "Route" ] "Route")))
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
                                            , Elm.fn (Elm.Arg.var "param")
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

        maybeToString : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        maybeToString =
            Elm.Declare.fn "maybeToString"
                (Elm.Arg.varWith "maybeString" (Type.maybe Type.string))
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

        stringToString : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        stringToString =
            Elm.Declare.fn "stringToString"
                (Elm.Arg.varWith "string" Type.string)
                (\string ->
                    Elm.Op.append
                        (Elm.string "\"")
                        (Elm.Op.append
                            string
                            (Elm.string "\"")
                        )
                )

        nonEmptyToString : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        nonEmptyToString =
            Elm.Declare.fn "nonEmptyToString"
                (Elm.Arg.varWith "nonEmpty" (Type.tuple Type.string (Type.list Type.string)))
                (\nonEmpty ->
                    Elm.Case.custom
                        nonEmpty
                        Type.unit
                        [ Elm.Case.branch
                            (Elm.Arg.tuple
                                (Elm.Arg.var "first")
                                (Elm.Arg.var "rest")
                            )
                            (\( first, rest ) ->
                                append
                                    [ Elm.string "( "
                                    , stringToString.call first
                                    , Elm.string ", [ "
                                    , rest
                                        |> Gen.List.call_.map stringToString.value
                                        |> Gen.String.call_.join (Elm.string ", ")
                                    , Elm.string " ] )"
                                    ]
                            )
                        ]
                )

        listToString : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        listToString =
            Elm.Declare.fn "listToString"
                (Elm.Arg.varWith "strings" (Type.list Type.string))
                (\strings ->
                    append
                        [ Elm.string "[ "
                        , strings
                            |> Gen.List.call_.map stringToString.value
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
                            Elm.Case.branch
                                (if RoutePattern.hasRouteParams route then
                                    Elm.Arg.customType moduleName Just
                                        |> Elm.Arg.item (Elm.Arg.var "routeParams")

                                 else
                                    Elm.Arg.customType moduleName Nothing
                                )
                                (\routeParams -> toInnerExpression route routeParams)
                        )
                )

        encodeActionData : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        encodeActionData =
            Elm.Declare.fn "encodeActionData"
                (Elm.Arg.varWith "actionData" actionDataType.annotation)
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        (routes
                            |> List.map
                                (\route ->
                                    Elm.Case.branch
                                        (route |> destructureRouteVariant ActionData "thisActionData")
                                        (\thisActionData ->
                                            Elm.apply
                                                (route |> encodeRouteType ActionData)
                                                [ thisActionData ]
                                        )
                                )
                        )
                        |> Elm.withType Gen.Bytes.Encode.annotation_.encoder
                )

        byteEncodePageData : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        byteEncodePageData =
            Elm.Declare.fn "byteEncodePageData"
                (Elm.Arg.varWith "pageData" pageDataType.annotation)
                (\actionData ->
                    Elm.Case.custom actionData
                        Type.unit
                        ([ Elm.Case.branch
                            (Elm.Arg.customType "DataErrorPage____" identity
                                |> Elm.Arg.item (Elm.Arg.var "thisPageData")
                            )
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
                         , Elm.Case.branch (Elm.Arg.customType "Data404NotFoundPage____" ()) (\_ -> Gen.Bytes.Encode.unsignedInt8 0)
                         ]
                            ++ (routes
                                    |> List.map
                                        (\route ->
                                            Elm.Case.branch
                                                (Elm.Arg.customType ("Data" ++ (RoutePattern.toModuleName route |> String.join "__")) identity
                                                    |> Elm.Arg.item (Elm.Arg.var "thisPageData")
                                                )
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

        byteDecodePageData : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        byteDecodePageData =
            Elm.Declare.fn "byteDecodePageData"
                (Elm.Arg.varWith "maybeRoute" (Type.named [ "Route" ] "Route" |> Type.maybe))
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
                                                Elm.Case.branch
                                                    (if RoutePattern.hasRouteParams route then
                                                        Elm.Arg.customType routeVariant Just
                                                            |> Elm.Arg.item Elm.Arg.ignore

                                                     else
                                                        Elm.Arg.customType routeVariant Nothing
                                                    )
                                                    (\_ -> mappedDecoder)
                                            )
                                    )
                            )
                        }
                        |> Elm.withType (Gen.Bytes.Decode.annotation_.decoder pageDataType.annotation)
                )

        pathsToGenerateHandler : Elm.Declare.Value
        pathsToGenerateHandler =
            Elm.Declare.value "pathsToGenerateHandler"
                (Gen.ApiRoute.succeed
                    (Gen.BackendTask.map2
                        (\pageRoutes apiRoutes ->
                            Elm.Op.append pageRoutes
                                (apiRoutes
                                    |> Gen.List.call_.map (Elm.fn (Elm.Arg.var "api") (\api -> Elm.Op.append (Elm.string "/") api))
                                )
                                |> Gen.Json.Encode.call_.list Gen.Json.Encode.values_.string
                                |> Gen.Json.Encode.encode 0
                        )
                        (Gen.BackendTask.map
                            (Gen.List.call_.map
                                (Elm.fn (Elm.Arg.var "route")
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
                            getStaticRoutes.value
                        )
                        (Elm.Op.cons routePatterns.value
                            (Elm.Op.cons apiPatterns.value
                                (Gen.Api.routes
                                    getStaticRoutes.value
                                    (\_ _ -> Elm.string "")
                                )
                            )
                            |> Gen.List.call_.map Gen.ApiRoute.values_.getBuildTimeRoutes
                            |> Gen.BackendTask.call_.combine
                            |> Gen.BackendTask.map Gen.List.call_.concat
                        )
                    )
                    |> Gen.ApiRoute.literal "all-paths.json"
                    |> Gen.ApiRoute.single
                )

        apiPatterns : Elm.Declare.Value
        apiPatterns =
            Elm.Declare.value "apiPatterns"
                (Gen.ApiRoute.succeed
                    (Gen.Json.Encode.call_.list
                        Gen.Basics.values_.identity
                        (Gen.Api.routes
                            getStaticRoutes.value
                            (\_ _ -> Elm.string "")
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

        routePatterns : Elm.Declare.Value
        routePatterns =
            Elm.Declare.value "routePatterns"
                (Gen.ApiRoute.succeed
                    (Gen.Json.Encode.list
                        (\info ->
                            Gen.Json.Encode.object
                                [ Elm.tuple (Elm.string "kind") (Gen.Json.Encode.call_.string (info |> Elm.get "kind"))
                                , Elm.tuple (Elm.string "pathPattern") (Gen.Json.Encode.call_.string (info |> Elm.get "pathPattern"))
                                ]
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

        globalHeadTags : Elm.Declare.Function (Elm.Expression -> Elm.Expression)
        globalHeadTags =
            Elm.Declare.fn "globalHeadTags"
                (Elm.Arg.varWith "htmlToString"
                    (Type.function
                        [ Type.maybe
                            (Type.record
                                [ ( "indent", Type.int )
                                , ( "newLines", Type.bool )
                                ]
                            )
                        , Gen.Html.annotation_.html Gen.Basics.annotation_.never
                        ]
                        Type.string
                    )
                )
                (\htmlToString ->
                    Elm.Op.cons
                        (Gen.Site.values_.config
                            |> Elm.get "head"
                        )
                        (Gen.Api.call_.routes
                            getStaticRoutes.value
                            htmlToString
                            |> Gen.List.call_.filterMap Gen.ApiRoute.values_.getGlobalHeadTagsBackendTask
                        )
                        |> Gen.BackendTask.call_.combine
                        |> Gen.BackendTask.map Gen.List.call_.concat
                        |> Elm.withType
                            (Gen.BackendTask.annotation_.backendTask
                                (Type.named [ "FatalError" ] "FatalError")
                                (Type.list Gen.Head.annotation_.tag)
                            )
                )

        encodeResponse : Elm.Declare.Value
        encodeResponse =
            Elm.Declare.value "encodeResponse"
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
                                [ pageDataType.annotation
                                , actionDataType.annotation
                                , Type.named [ "Shared" ] "Data"
                                ]
                            ]
                            Gen.Bytes.Encode.annotation_.encoder
                        )
                )

        decodeResponse : Elm.Declare.Value
        decodeResponse =
            Elm.Declare.value "decodeResponse"
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
                            [ pageDataType.annotation
                            , actionDataType.annotation
                            , Type.named [ "Shared" ] "Data"
                            ]
                            |> Gen.Bytes.Decode.annotation_.decoder
                        )
                )

        getStaticRoutes : Elm.Declare.Value
        getStaticRoutes =
            Elm.Declare.value "getStaticRoutes"
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
                                                Elm.fn Elm.Arg.ignore
                                                    (\_ ->
                                                        Elm.value
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
                    |> Gen.BackendTask.map Gen.List.call_.concat
                    |> Elm.withType
                        (Gen.BackendTask.annotation_.backendTask
                            (Type.named [ "FatalError" ] "FatalError")
                            (Type.list (Type.named [ "Route" ] "Route"))
                        )
                )

        modelType : Elm.Declare.Annotation
        modelType =
            Elm.Declare.alias "Model"
                (Type.record
                    [ ( "global", Type.named [ "Shared" ] "Model" )
                    , ( "page", pageModelType.annotation )
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

        pageModelType : Elm.Declare.Annotation
        pageModelType =
            Elm.Declare.customType "PageModel"
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

        msgType : Elm.Declare.Annotation
        msgType =
            Elm.Declare.customType "Msg"
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

        pageDataType : Elm.Declare.Annotation
        pageDataType =
            Elm.Declare.customType "PageData"
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

        actionDataType : Elm.Declare.Annotation
        actionDataType =
            Elm.Declare.customType "ActionData"
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
    in
    Elm.file [ "Main" ]
        [ modelType.declaration
        , pageModelType.declaration
        , msgType.declaration
        , pageDataType.declaration
        , actionDataType.declaration
        , case phase of
            Browser ->
                Gen.Pages.Internal.Platform.application config
                    |> Elm.withType
                        (Type.namedWith [ "Platform" ]
                            "Program"
                            [ Gen.Pages.Internal.Platform.annotation_.flags
                            , Gen.Pages.Internal.Platform.annotation_.model modelType.annotation
                                pageDataType.annotation
                                actionDataType.annotation
                                (Type.named [ "Shared" ] "Data")
                            , Gen.Pages.Internal.Platform.annotation_.msg
                                msgType.annotation
                                pageDataType.annotation
                                actionDataType.annotation
                                (Type.named [ "Shared" ] "Data")
                                (Type.named [ "ErrorPage" ] "ErrorPage")
                            ]
                        )
                    |> Elm.declaration "main"
                    |> Elm.exposeConstructor

            Cli ->
                Gen.Pages.Internal.Platform.Cli.cliApplication config
                    |> Elm.withType
                        (Gen.Pages.Internal.Platform.Cli.annotation_.program
                            (Type.named [ "Route" ] "Route" |> Type.maybe)
                        )
                    |> Elm.declaration "main"
                    |> Elm.exposeConstructor
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
            Gen.Bytes.annotation_.bytes
        , Elm.portOutgoing "toJsPort"
            Gen.Json.Encode.annotation_.value
        , Elm.portIncoming "fromJsPort"
            Gen.Json.Decode.annotation_.value
        , Elm.portIncoming "gotBatchSub"
            Gen.Json.Decode.annotation_.value
        ]


routeToSyntaxPattern : RoutePattern -> Elm.Arg (Maybe Elm.Expression)
routeToSyntaxPattern route =
    let
        moduleName : String
        moduleName =
            "Route." ++ (RoutePattern.toModuleName route |> String.join "__")
    in
    if RoutePattern.hasRouteParams route then
        Elm.Arg.customType moduleName Just
            |> Elm.Arg.item (Elm.Arg.var "routeParams")

    else
        Elm.Arg.customType moduleName Nothing


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


destructureRouteVariant : RouteVariant -> String -> RoutePattern -> Elm.Arg Elm.Expression
destructureRouteVariant variant varName route =
    let
        moduleName : String
        moduleName =
            routeVariantToString variant ++ (RoutePattern.toModuleName route |> String.join "__")
    in
    Elm.Arg.customType moduleName identity
        |> Elm.Arg.item (Elm.Arg.var varName)


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
    Gen.Debug.todo ""


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
        Elm.Case.branch Elm.Arg.ignore (\_ -> info.otherwise) |> Just

      else
        Nothing
    ]
        |> List.filterMap identity


make_ :
    { init : Elm.Expression
    , update : Elm.Expression
    , subscriptions : Elm.Expression
    , sharedData : Elm.Expression
    , data : Elm.Expression
    , action : Elm.Expression
    , onActionData : Elm.Expression
    , view : Elm.Expression
    , handleRoute : Elm.Expression
    , getStaticRoutes : Elm.Expression
    , urlToRoute : Elm.Expression
    , routeToPath : Elm.Expression
    , site : Elm.Expression
    , toJsPort : Elm.Expression
    , fromJsPort : Elm.Expression
    , gotBatchSub : Elm.Expression
    , hotReloadData : Elm.Expression
    , onPageChange : Elm.Expression
    , apiRoutes : Elm.Expression
    , pathPatterns : Elm.Expression
    , basePath : Elm.Expression
    , sendPageData : Elm.Expression
    , byteEncodePageData : Elm.Expression
    , byteDecodePageData : Elm.Expression
    , encodeResponse : Elm.Expression
    , encodeAction : Elm.Expression
    , decodeResponse : Elm.Expression
    , globalHeadTags : Elm.Expression
    , cmdToEffect : Elm.Expression
    , perform : Elm.Expression
    , errorStatusCode : Elm.Expression
    , notFoundPage : Elm.Expression
    , internalError : Elm.Expression
    , errorPageToData : Elm.Expression
    , notFoundRoute : Elm.Expression
    }
    -> Elm.Expression
make_ programConfig_args =
    Elm.record
        [ Tuple.pair "init" programConfig_args.init
        , Tuple.pair "update" programConfig_args.update
        , Tuple.pair
            "subscriptions"
            programConfig_args.subscriptions
        , Tuple.pair "sharedData" programConfig_args.sharedData
        , Tuple.pair "data" programConfig_args.data
        , Tuple.pair "action" programConfig_args.action
        , Tuple.pair "onActionData" programConfig_args.onActionData
        , Tuple.pair "view" programConfig_args.view
        , Tuple.pair "handleRoute" programConfig_args.handleRoute
        , Tuple.pair
            "getStaticRoutes"
            programConfig_args.getStaticRoutes
        , Tuple.pair "urlToRoute" programConfig_args.urlToRoute
        , Tuple.pair "routeToPath" programConfig_args.routeToPath
        , Tuple.pair "site" programConfig_args.site
        , Tuple.pair "toJsPort" programConfig_args.toJsPort
        , Tuple.pair "fromJsPort" programConfig_args.fromJsPort
        , Tuple.pair "gotBatchSub" programConfig_args.gotBatchSub
        , Tuple.pair
            "hotReloadData"
            programConfig_args.hotReloadData
        , Tuple.pair "onPageChange" programConfig_args.onPageChange
        , Tuple.pair "apiRoutes" programConfig_args.apiRoutes
        , Tuple.pair "pathPatterns" programConfig_args.pathPatterns
        , Tuple.pair "basePath" programConfig_args.basePath
        , Tuple.pair "sendPageData" programConfig_args.sendPageData
        , Tuple.pair
            "byteEncodePageData"
            programConfig_args.byteEncodePageData
        , Tuple.pair
            "byteDecodePageData"
            programConfig_args.byteDecodePageData
        , Tuple.pair
            "encodeResponse"
            programConfig_args.encodeResponse
        , Tuple.pair "encodeAction" programConfig_args.encodeAction
        , Tuple.pair
            "decodeResponse"
            programConfig_args.decodeResponse
        , Tuple.pair
            "globalHeadTags"
            programConfig_args.globalHeadTags
        , Tuple.pair "cmdToEffect" programConfig_args.cmdToEffect
        , Tuple.pair "perform" programConfig_args.perform
        , Tuple.pair
            "errorStatusCode"
            programConfig_args.errorStatusCode
        , Tuple.pair "notFoundPage" programConfig_args.notFoundPage
        , Tuple.pair
            "internalError"
            programConfig_args.internalError
        , Tuple.pair
            "errorPageToData"
            programConfig_args.errorPageToData
        , Tuple.pair
            "notFoundRoute"
            programConfig_args.notFoundRoute
        ]
