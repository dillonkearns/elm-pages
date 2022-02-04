module Pages.Internal.RoutePattern exposing (Ending(..), RoutePattern, Segment(..), view)

{-| Exposed for internal use only (used in generated code).

@docs Ending, RoutePattern, Segment, view

-}

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


segmentToString : Segment -> String
segmentToString segment =
    case segment of
        StaticSegment string ->
            string

        DynamicSegment name ->
            ":" ++ name


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
