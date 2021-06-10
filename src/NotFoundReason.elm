module NotFoundReason exposing (NotFoundReason(..), Payload, codec, document)

import Codec exposing (Codec)
import Html exposing (Html)
import Html.Attributes as Attr
import Path exposing (Path)
import RoutePattern exposing (RoutePattern)


type alias ModuleContext =
    { moduleName : List String
    , routePattern : RoutePattern
    }


type alias Payload =
    { path : Path
    , reason : NotFoundReason
    }


type alias Record =
    List ( String, String )


type NotFoundReason
    = NoMatchingRoute
    | NotPrerendered ModuleContext (List Record)
    | NotPrerenderedOrHandledByFallback ModuleContext (List Record)
    | UnhandledServerRoute ModuleContext


document :
    List RoutePattern
    -> Payload
    -> { title : String, body : Html msg }
document pathPatterns payload =
    { title = "Page not found"
    , body =
        Html.div
            [ Attr.id "not-found-reason"
            , Attr.style "padding" "30px"
            ]
            (case payload.reason of
                NoMatchingRoute ->
                    [ Html.text <| "No route found for "
                    , Html.code []
                        [ Html.text
                            (payload.path
                                |> Path.toAbsolute
                            )
                        ]
                    , Html.text " Did you mean to go to one of these routes:"
                    , Html.ul
                        [ Attr.style "padding-top" "30px"
                        ]
                        (pathPatterns
                            |> List.map
                                (\route ->
                                    Html.li
                                        [ Attr.style "list-style" "inside"
                                        ]
                                        [ route
                                            |> RoutePattern.view
                                        ]
                                )
                        )
                    ]

                NotPrerendered moduleContext routes ->
                    [ Html.h1 []
                        [ Html.text "Page Not Found"
                        ]
                    , Html.code []
                        [ Html.text
                            (payload.path
                                |> Path.toAbsolute
                            )
                        ]
                    , Html.text " successfully matched the route "
                    , Html.br [] []
                    , Html.br [] []
                    , Html.code []
                        [ RoutePattern.view moduleContext.routePattern
                        ]
                    , Html.br [] []
                    , Html.br [] []
                    , Html.text " from the Page Module "
                    , Html.br [] []
                    , Html.br [] []
                    , Html.code []
                        [ Html.text (moduleName moduleContext)
                        ]
                    , Html.br [] []
                    , Html.br [] []
                    , Html.text " but these RouteParams were not present "
                    , Html.br [] []
                    , Html.br [] []
                    , Html.code
                        [ Attr.style "border-bottom" "dotted 2px"
                        , Attr.style "font-weight" "bold"
                        ]
                        [ Html.text """{ slug = "asdfqwer" }"""
                        ]
                    , Html.br [] []
                    , Html.br [] []
                    , Html.text "The following RouteParams are pre-rendered:"
                    , Html.ul
                        [ Attr.style "padding-top" "30px"
                        ]
                        (routes
                            |> List.map
                                (\record ->
                                    Html.li
                                        [ Attr.style "list-style" "inside"
                                        ]
                                        [ Html.a
                                            [ Attr.href "/blog/extensible-markdown-parsing-in-elm"
                                            ]
                                            [ Html.code
                                                []
                                                [ Html.text (recordToString record)
                                                ]
                                            ]
                                        ]
                                )
                        )
                    , Html.br [] []
                    , Html.br [] []
                    , Html.p []
                        [ Html.text "Try changing "
                        , Html.code [] [ Html.text "routes" ]
                        , Html.text " in "
                        , Html.code [] [ Html.text (moduleName moduleContext) ]
                        , Html.text " to make sure it includes these "
                        , Html.code [] [ Html.text "RouteParams" ]
                        , Html.text "."
                        ]
                    ]

                _ ->
                    [ Html.text "Page not found"
                    , Html.text <| "TODO"
                    ]
            )
    }


codec : Codec Payload
codec =
    Codec.object Payload
        |> Codec.field "path"
            .path
            (Codec.list Codec.string
                |> Codec.map Path.join Path.toSegments
            )
        |> Codec.field "reason" .reason reasonCodec
        |> Codec.buildObject


reasonCodec : Codec NotFoundReason
reasonCodec =
    Codec.custom
        (\vNoMatchingRoute vNotPrerendered vNotPrerenderedOrHandledByFallback vUnhandledServerRoute value ->
            case value of
                NoMatchingRoute ->
                    vNoMatchingRoute

                NotPrerendered moduleContext prerenderedRoutes ->
                    vNotPrerendered moduleContext prerenderedRoutes

                NotPrerenderedOrHandledByFallback moduleContext prerenderedRoutes ->
                    vNotPrerenderedOrHandledByFallback moduleContext prerenderedRoutes

                UnhandledServerRoute moduleContext ->
                    vUnhandledServerRoute moduleContext
        )
        |> Codec.variant0 "NoMatchingRoute" NoMatchingRoute
        |> Codec.variant2 "NotPrerendered" NotPrerendered moduleContextCodec (Codec.list recordCodec)
        |> Codec.variant2 "NotPrerenderedOrHandledByFallback" NotPrerenderedOrHandledByFallback moduleContextCodec (Codec.list recordCodec)
        |> Codec.variant1 "UnhandledServerRoute" UnhandledServerRoute moduleContextCodec
        |> Codec.buildCustom


moduleContextCodec : Codec ModuleContext
moduleContextCodec =
    Codec.object ModuleContext
        |> Codec.field "moduleName" .moduleName (Codec.list Codec.string)
        |> Codec.field "routePattern" .routePattern RoutePattern.codec
        |> Codec.buildObject


recordCodec : Codec (List ( String, String ))
recordCodec =
    Codec.list (Codec.tuple Codec.string Codec.string)


recordToString : List ( String, String ) -> String
recordToString fields =
    "{ "
        ++ (fields
                |> List.map
                    (\( key, value ) ->
                        key ++ " = " ++ value
                    )
                |> String.join ", "
           )
        ++ " }"


moduleName : ModuleContext -> String
moduleName moduleContext =
    ("src" :: moduleContext.moduleName |> String.join "/") ++ ".elm"
