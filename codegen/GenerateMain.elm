module GenerateMain exposing (..)

import Elm exposing (File)
import Elm.Annotation as Type
import Elm.Case
import Elm.CodeGen
import Elm.Declare
import Elm.Extra exposing (expose, topLevelValue)
import Elm.Op
import Elm.Pretty
import Gen.Basics
import Gen.Bytes
import Gen.CodeGen.Generate exposing (Error)
import Gen.Html
import Gen.Html.Attributes
import Gen.Json.Decode
import Gen.Json.Encode
import Gen.List
import Gen.Pages.Internal.Platform
import Gen.Pages.ProgramConfig
import Gen.Path
import Gen.Server.Response
import Gen.String
import Gen.Tuple
import Gen.Url
import Pages.Internal.RoutePattern as RoutePattern exposing (RoutePattern)
import Pretty
import Regex exposing (Regex)


otherFile : List RoutePattern.RoutePattern -> File
otherFile routes =
    let
        config :
            { declaration : Elm.Declaration
            , reference : Elm.Expression
            , referenceFrom : List String -> Elm.Expression
            }
        config =
            topLevelValue "config" <|
                Gen.Pages.ProgramConfig.make_.programConfig
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
                    , urlToRoute = todo
                    , routeToPath = todo
                    , site = todo
                    , toJsPort = todo
                    , fromJsPort = todo
                    , gotBatchSub = todo
                    , hotReloadData = todo
                    , onPageChange = todo
                    , apiRoutes = todo
                    , pathPatterns = todo
                    , basePath = todo
                    , sendPageData = todo
                    , byteEncodePageData = todo
                    , byteDecodePageData = todo
                    , encodeResponse = todo
                    , encodeAction = todo
                    , decodeResponse = todo
                    , globalHeadTags = todo
                    , cmdToEffect = todo
                    , perform = todo
                    , errorStatusCode = todo
                    , notFoundPage = todo
                    , internalError = todo
                    , errorPageToData = todo
                    , notFoundRoute = todo
                    }
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
        , Elm.portOutgoing "sendPageData"
            (Type.record
                [ ( "oldThing", Gen.Json.Encode.annotation_.value )
                , ( "binaryPageData", Gen.Bytes.annotation_.bytes )
                ]
            )
        , Elm.portIncoming "hotReloadData"
            [ Gen.Bytes.annotation_.bytes ]
        , Elm.portIncoming "toJsPort"
            [ Gen.Json.Encode.annotation_.value ]
        , Elm.portIncoming "fromJsPort"
            [ Gen.Json.Decode.annotation_.value ]
        , Elm.portIncoming "gotBatchSub"
            [ Gen.Json.Decode.annotation_.value ]
        ]


todo : Elm.Expression
todo =
    Elm.apply (Elm.val "Debug.todo") [ Elm.string "" ]


pathType : Type.Annotation
pathType =
    Type.named [ "Path" ] "Path"
