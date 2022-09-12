module Pages.Internal.RoutePattern exposing
    ( Ending(..), RoutePattern, Segment(..), view, toVariant, routeToBranch
    , Param(..), fromModuleName, toRouteParamTypes, toRouteParamsRecord
    )

{-| Exposed for internal use only (used in generated code).

@docs Ending, RoutePattern, Segment, view, toVariant, routeToBranch

-}

import Elm
import Elm.Annotation exposing (Annotation)
import Elm.Case
import Elm.CodeGen
import Html exposing (Html)


{-| -}
type alias RoutePattern =
    { segments : List Segment
    , ending : Maybe Ending
    }


fromModuleName : List String -> Maybe RoutePattern
fromModuleName moduleNameSegments =
    case moduleNameSegments |> List.reverse of
        lastSegment :: firstSegmentsInReverse ->
            case tryAsEnding lastSegment of
                Just ending ->
                    { segments =
                        firstSegmentsInReverse
                            |> List.reverse
                            |> List.map segmentToParam
                    , ending = Just ending
                    }
                        |> Just

                Nothing ->
                    { segments =
                        moduleNameSegments
                            |> List.map segmentToParam
                    , ending = Nothing
                    }
                        |> Just

        [] ->
            Just { segments = [], ending = Nothing }


toRouteParamsRecord : RoutePattern -> List ( String, Annotation )
toRouteParamsRecord pattern =
    (pattern.segments
        |> List.concatMap
            (\segment ->
                case segment of
                    StaticSegment _ ->
                        []

                    DynamicSegment name ->
                        [ ( name |> decapitalize, Elm.Annotation.string ) ]
            )
    )
        ++ (case pattern.ending of
                Nothing ->
                    []

                Just OptionalSplat ->
                    [ ( "splat"
                      , Elm.Annotation.list Elm.Annotation.string
                      )
                    ]

                Just RequiredSplat ->
                    [ ( "splat"
                      , Elm.Annotation.tuple
                            Elm.Annotation.string
                            (Elm.Annotation.list Elm.Annotation.string)
                      )
                    ]

                Just (Optional name) ->
                    [ ( name |> decapitalize
                      , Elm.Annotation.maybe Elm.Annotation.string
                      )
                    ]
           )


toRouteParamTypes : RoutePattern -> List ( String, Param )
toRouteParamTypes pattern =
    (pattern.segments
        |> List.concatMap
            (\segment ->
                case segment of
                    StaticSegment _ ->
                        []

                    DynamicSegment name ->
                        [ ( name |> decapitalize, RequiredParam ) ]
            )
    )
        ++ (case pattern.ending of
                Nothing ->
                    []

                Just OptionalSplat ->
                    [ ( "splat"
                      , OptionalSplatParam
                      )
                    ]

                Just RequiredSplat ->
                    [ ( "splat"
                      , RequiredSplatParam
                      )
                    ]

                Just (Optional name) ->
                    [ ( name |> decapitalize
                      , OptionalParam
                      )
                    ]
           )


routeToBranch : RoutePattern -> ( Elm.CodeGen.Pattern, Elm.CodeGen.Expression )
routeToBranch route =
    case route.segments of
        [] ->
            ( Elm.CodeGen.listPattern [], Elm.CodeGen.val "TODO" )

        _ ->
            ( Elm.CodeGen.listPattern
                [ Elm.CodeGen.stringPattern "user"
                , Elm.CodeGen.varPattern "id"
                ]
            , Elm.CodeGen.val "TODO"
            )


{-| -}
toVariant : RoutePattern -> Elm.Variant
toVariant pattern =
    if List.isEmpty pattern.segments && pattern.ending == Nothing then
        Elm.variant "Index"

    else
        let
            something =
                (pattern.segments
                    |> List.map
                        (\segment ->
                            case segment of
                                DynamicSegment name ->
                                    ( name ++ "_", Just ( decapitalize name, Elm.Annotation.string ) )

                                StaticSegment name ->
                                    ( name, Nothing )
                        )
                )
                    ++ ([ Maybe.map endingToVariantName pattern.ending
                        ]
                            |> List.filterMap identity
                       )

            fieldThings : List ( String, Annotation )
            fieldThings =
                something
                    |> List.filterMap Tuple.second

            innerType =
                case fieldThings of
                    [] ->
                        []

                    nonEmpty ->
                        nonEmpty |> Elm.Annotation.record |> List.singleton
        in
        Elm.variantWith
            (something
                |> List.map Tuple.first
                |> String.join "__"
            )
            innerType


endingToVariantName : Ending -> ( String, Maybe ( String, Annotation ) )
endingToVariantName ending =
    case ending of
        Optional name ->
            ( name ++ "__", Just ( decapitalize name, Elm.Annotation.maybe Elm.Annotation.string ) )

        RequiredSplat ->
            ( "SPLAT_"
            , Just
                ( "splat"
                , Elm.Annotation.tuple
                    Elm.Annotation.string
                    (Elm.Annotation.list Elm.Annotation.string)
                )
            )

        OptionalSplat ->
            ( "SPLAT__"
            , Just
                ( "splat"
                , Elm.Annotation.list Elm.Annotation.string
                )
            )


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


tryAsEnding : String -> Maybe Ending
tryAsEnding segment =
    if segment == "SPLAT__" then
        OptionalSplat
            |> Just

    else if segment == "SPLAT_" then
        RequiredSplat
            |> Just

    else if segment |> String.endsWith "__" then
        (segment
            |> String.dropRight 2
            |> Optional
        )
            |> Just

    else
        Nothing


segmentToParam : String -> Segment
segmentToParam segment =
    if segment |> String.endsWith "_" then
        segment
            |> String.dropRight 1
            |> DynamicSegment

    else
        segment
            |> StaticSegment


{-| Decapitalize the first letter of a string.
decapitalize "This is a phrase" == "this is a phrase"
decapitalize "Hello, World" == "hello, World"
-}
decapitalize : String -> String
decapitalize word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    changeCase Char.toLower word


{-| Change the case of the first letter of a string to either uppercase or
lowercase, depending of the value of `wantedCase`. This is an internal
function for use in `toSentenceCase` and `decapitalize`.
-}
changeCase : (Char -> Char) -> String -> String
changeCase mutator word =
    -- Source: https://github.com/elm-community/string-extra/blob/4.0.1/src/String/Extra.elm
    String.uncons word
        |> Maybe.map (\( head, tail ) -> String.cons (mutator head) tail)
        |> Maybe.withDefault ""


type Param
    = RequiredParam
    | OptionalParam
    | RequiredSplatParam
    | OptionalSplatParam
