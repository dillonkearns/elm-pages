module GenerateMain exposing (..)

import Elm exposing (File)
import Elm.Annotation as Type
import Elm.Case
import Elm.CodeGen
import Elm.Declare
import Elm.Extra exposing (expose, fnIgnore, topLevelValue)
import Elm.Op
import Elm.Pretty
import Gen.ApiRoute
import Gen.Basics
import Gen.Bytes
import Gen.Bytes.Decode
import Gen.Bytes.Encode
import Gen.CodeGen.Generate exposing (Error)
import Gen.DataSource
import Gen.Head
import Gen.Html
import Gen.Html.Attributes
import Gen.HtmlPrinter
import Gen.Json.Decode
import Gen.Json.Encode
import Gen.List
import Gen.Maybe
import Gen.Pages.Internal.NotFoundReason
import Gen.Pages.Internal.Platform
import Gen.Pages.Internal.RoutePattern
import Gen.Pages.ProgramConfig
import Gen.Path
import Gen.Platform.Sub
import Gen.Server.Response
import Gen.String
import Gen.Tuple
import Gen.Url
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import Pretty
import Regex exposing (Regex)


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

        config :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        config =
            { init = todo
            , update = todo
            , subscriptions = todo
            , sharedData =
                Elm.value { name = "template", importFrom = [ "Shared" ], annotation = Nothing }
                    |> Elm.get "data"
            , data = todo
            , action = todo
            , onActionData = todo
            , view = todo
            , handleRoute = Elm.val "handleRoute"
            , getStaticRoutes =
                case phase of
                    Browser ->
                        Gen.DataSource.succeed (Elm.list [])

                    Cli ->
                        getStaticRoutes.reference
                            |> Gen.DataSource.map (Gen.List.call_.map (Elm.val "Just"))
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
                        Elm.just
                            (Elm.value
                                { name = "config"
                                , annotation = Nothing
                                , importFrom = [ "Site" ]
                                }
                            )
            , toJsPort = Elm.val "toJsPort"
            , fromJsPort = applyIdentityTo (Elm.val "fromJsPort")
            , gotBatchSub =
                case phase of
                    Browser ->
                        Gen.Platform.Sub.none

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
                                            (Elm.apply (Elm.value { name = "routes", importFrom = [ "Api" ], annotation = Nothing })
                                                [ getStaticRoutes.reference
                                                , htmlToString
                                                ]
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
            , byteEncodePageData = todo
            , byteDecodePageData = todo
            , encodeResponse = encodeResponse.reference
            , encodeAction = todo
            , decodeResponse = decodeResponse.reference
            , globalHeadTags =
                case phase of
                    Browser ->
                        Elm.nothing

                    Cli ->
                        Elm.just globalHeadTags.reference
            , cmdToEffect =
                Elm.value
                    { annotation = Nothing
                    , name = "fromCmd"
                    , importFrom = [ "Effect" ]
                    }
            , perform =
                Elm.value
                    { annotation = Nothing
                    , name = "perform"
                    , importFrom = [ "Effect" ]
                    }
            , errorStatusCode =
                Elm.value
                    { annotation = Nothing
                    , name = "statusCode"
                    , importFrom = [ "ErrorPage" ]
                    }
            , notFoundPage =
                Elm.value
                    { annotation = Nothing
                    , name = "notFound"
                    , importFrom = [ "ErrorPage" ]
                    }
            , internalError =
                Elm.value
                    { annotation = Nothing
                    , name = "internalError"
                    , importFrom = [ "ErrorPage" ]
                    }
            , errorPageToData = Elm.val "DataErrorPage____"
            , notFoundRoute = Elm.nothing
            }
                |> Gen.Pages.ProgramConfig.make_.programConfig
                |> Elm.withType
                    (Gen.Pages.ProgramConfig.annotation_.programConfig
                        (Type.named [] "Msg")
                        (Type.named [] "Model")
                        (Type.maybe (Type.named [ "Route" ] "Route"))
                        (Type.named [] "PageData")
                        (Type.named [] "ActionData")
                        (Type.named [ "Shared" ] "Data")
                        (Type.namedWith [ "Effect" ] "Effect" [ Type.named [] "Msg" ])
                        (Type.var "mappedMsg")
                        (Type.named [ "ErrorPage" ] "ErrorPage")
                    )
                |> topLevelValue "config"

        pathPatterns :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        pathPatterns =
            topLevelValue "routePatterns3"
                (routes
                    |> List.map routePatternToSyntax
                    |> Elm.list
                )

        handleRoute :
            { declaration : Elm.Declaration
            , call : Elm.Expression -> Elm.Expression
            , callFrom : List String -> Elm.Expression -> Elm.Expression
            }
        handleRoute =
            Elm.Declare.fn "handleRoute"
                ( "maybeRoute", Type.maybe (Type.named [ "Route" ] "Route") |> Just )
                (\maybeRoute ->
                    Elm.Case.maybe maybeRoute
                        { nothing = Gen.DataSource.succeed Elm.nothing
                        , just =
                            ( "route"
                            , \justRoute ->
                                Elm.Case.custom justRoute
                                    Type.unit
                                    (routes
                                        |> List.map
                                            (\route ->
                                                let
                                                    params : List RoutePattern.RouteParam
                                                    params =
                                                        route |> RoutePattern.toVariantName |> .params

                                                    moduleName =
                                                        "Route." ++ (RoutePattern.toModuleName route |> String.join "__")

                                                    moduleThing2 =
                                                        ("Route" :: RoutePattern.toModuleName route) |> String.join "."

                                                    expression : Elm.Expression -> Elm.Expression
                                                    expression innerRecord =
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
                                                                  , routePatternToSyntax route
                                                                  )
                                                                ]
                                                            , Elm.fn ( "param", Nothing )
                                                                (\param ->
                                                                    Elm.list []
                                                                )
                                                            , innerRecord
                                                            ]
                                                in
                                                if RoutePattern.hasRouteParams route then
                                                    Elm.Case.branch1 moduleName
                                                        ( "routeParams", Type.unit )
                                                        (\routeParams ->
                                                            expression routeParams
                                                        )

                                                else
                                                    Elm.Case.branch0 moduleName
                                                        (expression (Elm.record []))
                                            )
                                    )
                            )
                        }
                        |> Elm.withType
                            (Gen.DataSource.annotation_.dataSource (Type.maybe Gen.Pages.Internal.NotFoundReason.annotation_.notFoundReason))
                )

        pathsToGenerateHandler :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        pathsToGenerateHandler =
            topLevelValue "pathsToGenerateHandler"
                (Gen.ApiRoute.succeed
                    (Gen.DataSource.map2
                        (\pageRoutes apiRoutes ->
                            Elm.Op.append pageRoutes
                                (apiRoutes
                                    |> Gen.List.call_.map (Elm.fn ( "api", Nothing ) (\api -> Elm.Op.append (Elm.string "/") api))
                                )
                                |> Gen.Json.Encode.call_.list Gen.Json.Encode.values_.string
                                |> Gen.Json.Encode.encode 0
                        )
                        (Gen.DataSource.map
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
                                            |> Gen.Path.toAbsolute
                                    )
                                )
                            )
                            getStaticRoutes.reference
                        )
                        (Elm.Op.cons routePatterns.reference
                            (Elm.Op.cons apiPatterns.reference
                                (Elm.apply (Elm.value { name = "routes", importFrom = [ "Api" ], annotation = Nothing })
                                    [ getStaticRoutes.reference
                                    , fnIgnore (Elm.string "")
                                    ]
                                )
                            )
                            |> Gen.List.call_.map Gen.ApiRoute.values_.getBuildTimeRoutes
                            |> Gen.DataSource.call_.combine
                            |> Gen.DataSource.call_.map Gen.List.values_.concat
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
                        (Elm.apply
                            (Elm.value { name = "routes", importFrom = [ "Api" ], annotation = Nothing })
                            [ getStaticRoutes.reference
                            , fnIgnore (Elm.string "")
                            ]
                            |> Gen.List.call_.map Gen.ApiRoute.values_.toJson
                        )
                        |> Gen.Json.Encode.encode 0
                        |> Gen.DataSource.succeed
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
                                                                        name

                                                                    RoutePattern.DynamicParam name ->
                                                                        ":" ++ name

                                                                    RoutePattern.OptionalParam2 name ->
                                                                        ":" ++ name

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
                        |> Gen.DataSource.succeed
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
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        globalHeadTags =
            topLevelValue "globalHeadTags"
                (Elm.Op.cons
                    (Elm.value
                        { importFrom = [ "Site" ]
                        , annotation = Nothing
                        , name = "config"
                        }
                        |> Elm.get "head"
                    )
                    (Elm.apply
                        (Elm.value
                            { importFrom = [ "Api" ]
                            , annotation = Nothing
                            , name = "routes"
                            }
                        )
                        [ getStaticRoutes.reference
                        , Gen.HtmlPrinter.values_.htmlToString
                        ]
                        |> Gen.List.call_.filterMap Gen.ApiRoute.values_.getGlobalHeadTagsDataSource
                    )
                    |> Gen.DataSource.call_.combine
                    |> Gen.DataSource.call_.map Gen.List.values_.concat
                    |> Elm.withType
                        (Gen.DataSource.annotation_.dataSource
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
                (Gen.DataSource.combine
                    (routes
                        |> List.map
                            (\route ->
                                Elm.value
                                    { name = "route"
                                    , annotation = Nothing
                                    , importFrom = "Route" :: (route |> RoutePattern.toModuleName)
                                    }
                                    |> Elm.get "staticRoutes"
                                    |> Gen.DataSource.map
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
                    |> Gen.DataSource.call_.map Gen.List.values_.concat
                    |> Elm.withType
                        (Gen.DataSource.annotation_.dataSource
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
                            [ ( "path", Type.named [ "Path" ] "Path" )
                            , ( "query", Type.named [ "Path" ] "Path" |> Type.maybe )
                            , ( "fragment", Type.string |> Type.maybe )
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
        , Gen.Pages.Internal.Platform.application config.reference
            |> Elm.declaration "main"
            |> expose
        , config.declaration
        , apiPatterns.declaration
        , routePatterns.declaration
        , pathsToGenerateHandler.declaration
        , getStaticRoutes.declaration
        , handleRoute.declaration
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


applyIdentityTo : Elm.Expression -> Elm.Expression
applyIdentityTo to =
    Elm.apply to [ Gen.Basics.values_.identity ]


todo : Elm.Expression
todo =
    Elm.apply (Elm.val "Debug.todo") [ Elm.string "" ]


pathType : Type.Annotation
pathType =
    Type.named [ "Path" ] "Path"


routePatternToSyntax : RoutePattern -> Elm.Expression
routePatternToSyntax route =
    Gen.Pages.Internal.RoutePattern.make_.routePattern
        { segments =
            route.segments
                |> List.map
                    (\segment ->
                        case segment of
                            RoutePattern.StaticSegment name ->
                                Gen.Pages.Internal.RoutePattern.make_.staticSegment (Elm.string name)

                            RoutePattern.DynamicSegment name ->
                                Gen.Pages.Internal.RoutePattern.make_.dynamicSegment (Elm.string name)
                    )
                |> Elm.list
        , ending =
            route.ending
                |> Maybe.map
                    (\ending ->
                        case ending of
                            RoutePattern.Optional name ->
                                Gen.Pages.Internal.RoutePattern.make_.optional (Elm.string name)

                            RoutePattern.RequiredSplat ->
                                Gen.Pages.Internal.RoutePattern.make_.requiredSplat

                            RoutePattern.OptionalSplat ->
                                Gen.Pages.Internal.RoutePattern.make_.optionalSplat
                    )
                |> Elm.maybe
        }
