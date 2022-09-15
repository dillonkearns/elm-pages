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
import Gen.Pages.Internal.Platform
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
            , sharedData = todo
            , data = todo
            , action = todo
            , onActionData = todo
            , view = todo
            , handleRoute = todo
            , getStaticRoutes = todo
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
            , onPageChange = todo
            , apiRoutes = todo
            , pathPatterns = todo
            , basePath = todo
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
        , getStaticRoutes.declaration
        , Elm.portOutgoing "sendPageData"
            (Type.record
                [ ( "oldThing", Gen.Json.Encode.annotation_.value )
                , ( "binaryPageData", Gen.Bytes.annotation_.bytes )
                ]
            )
        , globalHeadTags.declaration
        , encodeResponse.declaration
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
