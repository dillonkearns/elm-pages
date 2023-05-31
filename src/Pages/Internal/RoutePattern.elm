module Pages.Internal.RoutePattern exposing
    ( Ending(..), RoutePattern, Segment(..), view, toVariant, routeToBranch
    , Param(..), RouteParam(..), fromModuleName, hasRouteParams, repeatWithoutOptionalEnding, toModuleName, toRouteParamTypes, toRouteParamsRecord, toVariantName
    )

{-| Exposed for internal use only (used in generated code).

@docs Ending, RoutePattern, Segment, view, toVariant, routeToBranch

@docs Param, RouteParam, fromModuleName, hasRouteParams, repeatWithoutOptionalEnding, toModuleName, toRouteParamTypes, toRouteParamsRecord, toVariantName

-}

import Elm
import Elm.Annotation exposing (Annotation)
import Elm.CodeGen
import Html exposing (Html)
import Regex exposing (Regex)


{-| -}
type alias RoutePattern =
    { segments : List Segment
    , ending : Maybe Ending
    }


{-| -}
toModuleName : RoutePattern -> List String
toModuleName route =
    let
        segmentsAsModuleParts : List String
        segmentsAsModuleParts =
            route.segments
                |> List.foldl
                    (\segment soFar ->
                        case segment of
                            StaticSegment name ->
                                soFar ++ [ name ]

                            DynamicSegment name ->
                                soFar ++ [ name ++ "_" ]
                    )
                    []
    in
    case route.ending of
        Nothing ->
            segmentsAsModuleParts

        Just ending ->
            segmentsAsModuleParts ++ [ endingToVariantName ending |> Tuple.first ]


{-| -}
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


{-| -}
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


{-| -}
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


{-| -}
routeToBranch : RoutePattern -> List ( Elm.CodeGen.Pattern, Elm.CodeGen.Expression )
routeToBranch route =
    case route.segments of
        [ StaticSegment "Index" ] ->
            [ ( Elm.CodeGen.listPattern [], Elm.CodeGen.val "Index" ) ]

        _ ->
            case route.ending of
                Just ending ->
                    [ ( (case ending of
                            Optional _ ->
                                Elm.CodeGen.listPattern

                            _ ->
                                unconsPattern
                        )
                            ((route.segments
                                |> List.map
                                    (\segment ->
                                        case segment of
                                            StaticSegment name ->
                                                Elm.CodeGen.stringPattern (toKebab name)

                                            DynamicSegment name ->
                                                Elm.CodeGen.varPattern (decapitalize name)
                                    )
                             )
                                ++ (case ending of
                                        Optional name ->
                                            [ Elm.CodeGen.varPattern (decapitalize name) ]

                                        RequiredSplat ->
                                            [ Elm.CodeGen.varPattern "splatFirst"
                                            , Elm.CodeGen.varPattern "splatRest"
                                            ]

                                        OptionalSplat ->
                                            [ Elm.CodeGen.varPattern "splat" ]
                                   )
                            )
                      , toRecordVariant False route
                      )
                    ]
                        ++ (case ending of
                                Optional _ ->
                                    [ ( Elm.CodeGen.listPattern
                                            (route.segments
                                                |> List.map
                                                    (\segment ->
                                                        case segment of
                                                            StaticSegment name ->
                                                                Elm.CodeGen.stringPattern (toKebab name)

                                                            DynamicSegment name ->
                                                                Elm.CodeGen.varPattern (decapitalize name)
                                                    )
                                            )
                                      , toRecordVariant True route
                                      )
                                    ]

                                _ ->
                                    []
                           )

                Nothing ->
                    [ ( Elm.CodeGen.listPattern
                            (route.segments
                                |> List.map
                                    (\segment ->
                                        case segment of
                                            StaticSegment name ->
                                                Elm.CodeGen.stringPattern (toKebab name)

                                            DynamicSegment name ->
                                                Elm.CodeGen.varPattern (decapitalize name)
                                    )
                            )
                      , toRecordVariant False route
                      )
                    ]


{-| -}
type RouteParam
    = StaticParam String
    | DynamicParam String
    | OptionalParam2 String
    | RequiredSplatParam2
    | OptionalSplatParam2


{-| -}
hasRouteParams : RoutePattern -> Bool
hasRouteParams route =
    route
        |> toVariantName
        |> .params
        |> List.any (not << isStatic)


{-| -}
isStatic : RouteParam -> Bool
isStatic routeParam =
    case routeParam of
        StaticParam _ ->
            True

        _ ->
            False


{-| -}
repeatWithoutOptionalEnding : List RouteParam -> Maybe (List RouteParam)
repeatWithoutOptionalEnding routeParams =
    case routeParams |> List.reverse of
        (OptionalParam2 _) :: reverseRest ->
            List.reverse reverseRest |> Just

        OptionalSplatParam2 :: reverseRest ->
            List.reverse reverseRest |> Just

        _ ->
            Nothing


{-| -}
toVariantName : RoutePattern -> { variantName : String, params : List RouteParam }
toVariantName route =
    let
        something : List ( String, Maybe RouteParam )
        something =
            route.segments
                |> List.map
                    (\segment ->
                        case segment of
                            DynamicSegment name ->
                                ( name ++ "_"
                                , DynamicParam (decapitalize name)
                                    |> Just
                                )

                            StaticSegment name ->
                                ( name
                                , if name == "Index" then
                                    Nothing

                                  else
                                    Just (StaticParam (decapitalize name))
                                )
                    )

        something2 : List ( String, Maybe RouteParam )
        something2 =
            something
                ++ ([ Maybe.map
                        (\ending ->
                            case ending of
                                Optional name ->
                                    ( name ++ "__"
                                    , Just (OptionalParam2 (decapitalize name))
                                    )

                                RequiredSplat ->
                                    ( "SPLAT_"
                                    , RequiredSplatParam2
                                        |> Just
                                    )

                                OptionalSplat ->
                                    ( "SPLAT__"
                                    , OptionalSplatParam2
                                        |> Just
                                    )
                        )
                        route.ending
                    ]
                        |> List.filterMap identity
                   )
    in
    something2
        |> List.map Tuple.first
        |> String.join "__"
        |> (\name ->
                { variantName = name
                , params = something2 |> List.filterMap Tuple.second
                }
           )


{-| -}
toRecordVariant : Bool -> RoutePattern -> Elm.CodeGen.Expression
toRecordVariant nothingCase route =
    let
        constructorName : String
        constructorName =
            route |> toVariantName |> .variantName

        innerType : Maybe Elm.CodeGen.Expression
        innerType =
            case fieldThings of
                [] ->
                    Nothing

                nonEmpty ->
                    nonEmpty |> Elm.CodeGen.record |> Just

        fieldThings : List ( String, Elm.CodeGen.Expression )
        fieldThings =
            route
                |> toVariantName
                |> .params
                |> List.filterMap
                    (\param ->
                        case param of
                            OptionalParam2 name ->
                                Just
                                    ( decapitalize name
                                    , if nothingCase then
                                        Elm.CodeGen.val "Nothing"

                                      else
                                        [ Elm.CodeGen.val "Just", Elm.CodeGen.val (decapitalize name) ] |> Elm.CodeGen.apply
                                    )

                            StaticParam _ ->
                                Nothing

                            DynamicParam name ->
                                Just
                                    ( decapitalize name
                                    , Elm.CodeGen.val (decapitalize name)
                                    )

                            RequiredSplatParam2 ->
                                Just
                                    ( "splat"
                                    , Elm.CodeGen.tuple [ Elm.CodeGen.val "splatFirst", Elm.CodeGen.val "splatRest" ]
                                    )

                            OptionalSplatParam2 ->
                                Just ( "splat", Elm.CodeGen.val "splat" )
                    )
    in
    case innerType of
        Just innerRecord ->
            Elm.CodeGen.apply
                [ constructorName |> Elm.CodeGen.val
                , innerRecord
                ]

        Nothing ->
            constructorName |> Elm.CodeGen.val


{-| -}
toVariant : RoutePattern -> Elm.Variant
toVariant pattern =
    if List.isEmpty pattern.segments && pattern.ending == Nothing then
        Elm.variant "Index"

    else
        let
            allSegments : List ( String, Maybe ( String, Annotation ) )
            allSegments =
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
                allSegments
                    |> List.filterMap Tuple.second

            noArgsOrNonEmptyRecordArg : List Annotation
            noArgsOrNonEmptyRecordArg =
                case fieldThings of
                    [] ->
                        []

                    nonEmpty ->
                        nonEmpty |> Elm.Annotation.record |> List.singleton
        in
        Elm.variantWith
            (allSegments
                |> List.map Tuple.first
                |> String.join "__"
            )
            noArgsOrNonEmptyRecordArg


{-| -}
endingToVariantNameFields : Ending -> ( String, Maybe ( String, Elm.CodeGen.Expression ) )
endingToVariantNameFields ending =
    case ending of
        Optional name ->
            ( name ++ "__"
            , Just ( decapitalize name, [ Elm.CodeGen.val "Just", Elm.CodeGen.val (decapitalize name) ] |> Elm.CodeGen.apply )
            )

        RequiredSplat ->
            ( "SPLAT_"
            , Just
                ( "splat"
                , Elm.CodeGen.tuple
                    [ Elm.CodeGen.val "splatFirst"
                    , Elm.CodeGen.val "splatRest"
                    ]
                )
            )

        OptionalSplat ->
            ( "SPLAT__"
            , Just ( "splat", Elm.CodeGen.val "splat" )
            )


{-| -}
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


{-| -}
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


{-| -}
toString_ : List Segment -> String
toString_ segments =
    "/"
        ++ (segments
                |> List.map segmentToString
                |> String.join "/"
           )


{-| -}
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


{-| -}
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


{-| -}
type Param
    = RequiredParam
    | OptionalParam
    | RequiredSplatParam
    | OptionalSplatParam


{-| -}
unconsPattern : List Elm.CodeGen.Pattern -> Elm.CodeGen.Pattern
unconsPattern list =
    case list of
        [] ->
            Elm.CodeGen.listPattern []

        listFirst :: listRest ->
            List.foldl
                (\soFar item ->
                    soFar
                        |> Elm.CodeGen.unConsPattern item
                )
                listFirst
                listRest


{-| -}
toKebab : String -> String
toKebab string =
    string
        |> decapitalize
        |> String.trim
        |> Regex.replace (regexFromString "([A-Z])") (.match >> String.append "-")
        |> Regex.replace (regexFromString "[_-\\s]+") (always "-")
        |> String.toLower


{-| -}
regexFromString : String -> Regex
regexFromString =
    Regex.fromString >> Maybe.withDefault Regex.never
