module Pages.Internal.RoutePattern exposing (Ending(..), RoutePattern, Segment(..), codec, view)

{-| Exposed for internal use only (used in generated code).

@docs Ending, RoutePattern, Segment, codec, view

-}

import Codec exposing (Codec)
import Html exposing (Html)


{-| -}
type alias RoutePattern =
    { segments : List Segment
    , ending : Maybe Ending
    }


{-| -}
type Ending
    = Optional String
    | RequiredSplat
    | OptionalSplat


{-| -}
type Segment
    = StaticSegment String
    | DynamicSegment String


{-| -}
codec : Codec RoutePattern
codec =
    Codec.object RoutePattern
        |> Codec.field "segments" .segments (Codec.list segmentCodec)
        |> Codec.field "ending" .ending (Codec.maybe endingCodec)
        |> Codec.buildObject


segmentCodec : Codec Segment
segmentCodec =
    Codec.custom
        (\vStatic vDynamic value ->
            case value of
                StaticSegment string ->
                    vStatic string

                DynamicSegment string ->
                    vDynamic string
        )
        |> Codec.variant1 "StaticSegment" StaticSegment Codec.string
        |> Codec.variant1 "DynamicSegment" DynamicSegment Codec.string
        |> Codec.buildCustom


endingCodec : Codec Ending
endingCodec =
    Codec.custom
        (\vOptional vRequiredSplat vOptionalSplat value ->
            case value of
                Optional string ->
                    vOptional string

                RequiredSplat ->
                    vRequiredSplat

                OptionalSplat ->
                    vOptionalSplat
        )
        |> Codec.variant1 "Optional" Optional Codec.string
        |> Codec.variant0 "RequiredSplat" RequiredSplat
        |> Codec.variant0 "OptionalSplat" OptionalSplat
        |> Codec.buildCustom


segmentToString : Segment -> String
segmentToString segment =
    case segment of
        StaticSegment string ->
            string

        DynamicSegment name ->
            ":" ++ name


type alias ModuleContext =
    { moduleName : List String
    , routePattern : RoutePattern
    }


{-| -}
view : RoutePattern -> Html msg
view routePattern =
    Html.span []
        (case routePattern.ending of
            Nothing ->
                [ Html.code [] [ Html.text <| toString_ routePattern.segments ] ]

            Just (Optional optionalName) ->
                [ Html.code []
                    [ Html.text <| toString_ routePattern.segments ]
                , Html.text " or "
                , Html.code []
                    [ Html.text <|
                        toString_ routePattern.segments
                            ++ "/:"
                            ++ optionalName
                    ]
                ]

            Just RequiredSplat ->
                [ Html.code [] [ Html.text <| toString_ routePattern.segments ] ]

            Just OptionalSplat ->
                [ Html.code [] [ Html.text <| toString_ routePattern.segments ] ]
        )


toString_ : List Segment -> String
toString_ segments =
    "/"
        ++ (segments
                |> List.map segmentToString
                |> String.join "/"
           )
