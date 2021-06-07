module NotFoundReason exposing (NotFoundReason(..), Payload, Route(..), codec, document)

import Codec exposing (Codec)
import Html exposing (Html)
import Html.Attributes as Attr
import Path exposing (Path)
import RoutePattern exposing (RoutePattern)


type alias Payload =
    { path : Path
    , reason : NotFoundReason
    }


type NotFoundReason
    = NoMatchingRoute
    | NotPrerendered (List Route)
    | NotPrerenderedOrHandledByFallback (List Route)
    | UnhandledServerRoute (List Route)


type Route
    = Route


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

                _ ->
                    [ Html.text "Page not found"
                    , Html.text <| Debug.toString payload
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


routeCodec : Codec Route
routeCodec =
    Codec.succeed Route


reasonCodec : Codec NotFoundReason
reasonCodec =
    Codec.custom
        (\vNoMatchingRoute vNotPrerendered vNotPrerenderedOrHandledByFallback vUnhandledServerRoute value ->
            case value of
                NoMatchingRoute ->
                    vNoMatchingRoute

                NotPrerendered prerenderedRoutes ->
                    vNotPrerendered prerenderedRoutes

                NotPrerenderedOrHandledByFallback prerenderedRoutes ->
                    vNotPrerenderedOrHandledByFallback prerenderedRoutes

                UnhandledServerRoute prerenderedRoutes ->
                    vUnhandledServerRoute prerenderedRoutes
        )
        |> Codec.variant0 "NoMatchingRoute" NoMatchingRoute
        |> Codec.variant1 "NotPrerendered" NotPrerendered (Codec.list routeCodec)
        |> Codec.variant1 "NotPrerenderedOrHandledByFallback" NotPrerenderedOrHandledByFallback (Codec.fail "")
        |> Codec.variant1 "UnhandledServerRoute" UnhandledServerRoute (Codec.fail "")
        |> Codec.buildCustom
