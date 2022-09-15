module Pages.Review.NoContractViolations exposing (rule)

{-|

@docs rule

-}

import Dict exposing (Dict)
import Elm.Annotation
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Module as Module exposing (Module)
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Elm.ToString
import Pages.Internal.RoutePattern as RoutePattern exposing (Param(..))
import Review.Rule as Rule exposing (Direction, Error, Rule)
import Set exposing (Set)


{-| Reports... REPLACEME

    config =
        [ Pages.Review.NoContractViolations.rule
        ]


## Fail

    a =
        "REPLACEME example to replace"


## Success

    a =
        "REPLACEME example to replace"


## When (not) to enable this rule

This rule is useful when REPLACEME.
This rule is not useful when REPLACEME.


## Try it out

You can try this rule out by running the following command:

```bash
elm-review --template dillonkearns/elm-review-elm-pages/example --rules Pages.Review.NoContractViolations
```

-}
rule : Rule
rule =
    Rule.newProjectRuleSchema "Pages.Review.NoContractViolations"
        { visitedCoreModules = Set.empty
        }
        |> Rule.withModuleVisitor
            (Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
                >> Rule.withDeclarationVisitor declarationVisitor
            )
        |> Rule.withModuleContext
            { foldProjectContexts = \a b -> { visitedCoreModules = Set.union a.visitedCoreModules b.visitedCoreModules }
            , fromModuleToProject = \_ moduleName _ -> { visitedCoreModules = Set.singleton (Node.value moduleName) }
            , fromProjectToModule =
                \_ moduleName _ ->
                    { moduleName = Node.value moduleName
                    , isRouteModule =
                        if (Node.value moduleName |> List.take 1) == [ "Route" ] && ((Node.value moduleName |> List.length) > 1) then
                            Just RouteModule

                        else
                            coreModulesAndExports
                                |> Dict.get (Node.value moduleName)
                                |> Maybe.map
                                    (\requiredExposes ->
                                        CoreModule { requiredExposes = requiredExposes }
                                    )
                    }
            }
        |> Rule.withFinalProjectEvaluation
            (\context ->
                let
                    missingCoreModules : Set (List String)
                    missingCoreModules =
                        context.visitedCoreModules
                            |> Set.diff coreModules
                in
                if missingCoreModules |> Set.isEmpty then
                    []

                else
                    [ Rule.globalError
                        { message = "Missing core modules"
                        , details =
                            missingCoreModules
                                |> Set.toList
                                |> List.map (String.join ".")
                        }
                    ]
            )
        |> Rule.fromProjectRuleSchema


type SpecialModule
    = RouteModule
    | CoreModule { requiredExposes : List String }


coreModules : Set (List String)
coreModules =
    Set.fromList
        [ [ "Api" ]
        , [ "Effect" ]
        , [ "ErrorPage" ]
        , [ "Shared" ]
        , [ "Site" ]
        , [ "View" ]
        ]


coreModulesAndExports : Dict (List String) (List String)
coreModulesAndExports =
    Dict.fromList
        [ ( [ "Api" ], [ "routes" ] )
        , ( [ "Effect" ], [ "Effect", "batch", "fromCmd", "map", "none", "perform" ] )
        , ( [ "ErrorPage" ], [ "ErrorPage", "notFound", "internalError", "view", "statusCode", "head" ] )
        , ( [ "Shared" ], [ "Data", "Model", "Msg", "template" ] )
        , ( [ "Site" ], [ "config" ] )
        , ( [ "View" ], [ "View", "map" ] )
        ]


type alias Context =
    { moduleName : List String
    , isRouteModule : Maybe SpecialModule
    }


moduleDefinitionVisitor : Node Module -> Context -> ( List (Error {}), Context )
moduleDefinitionVisitor node context =
    case Node.value node |> Module.exposingList of
        Exposing.All _ ->
            ( [], context )

        Exposing.Explicit exposedValues ->
            case context.isRouteModule of
                Just RouteModule ->
                    case Set.diff (Set.fromList [ "ActionData", "Data", "Msg", "Model", "route" ]) (exposedNames exposedValues) |> Set.toList of
                        [] ->
                            ( [], context )

                        nonEmpty ->
                            ( [ Rule.error
                                    { message = "Unexposed Declaration in Route Module"
                                    , details =
                                        [ """Route Modules need to expose the following values:

- route
- Data
- ActionData
- Model
- Msg

But it is not exposing: """
                                            ++ (nonEmpty |> String.join ", ")
                                        ]
                                    }
                                    (Node.range (exposingListNode (Node.value node)))
                              ]
                            , context
                            )

                Just (CoreModule { requiredExposes }) ->
                    case Set.diff (Set.fromList requiredExposes) (exposedNames exposedValues) |> Set.toList of
                        [] ->
                            ( [], context )

                        nonEmpty ->
                            ( [ Rule.error
                                    { message = "A core elm-pages module needs to expose something"
                                    , details =
                                        [ "The "
                                            ++ (context.moduleName |> String.join ".")
                                            ++ " module must expose "
                                            ++ (nonEmpty
                                                    |> List.map (\value -> "`" ++ value ++ "`")
                                                    |> String.join ", "
                                               )
                                        ]
                                    }
                                    (Node.range (exposingListNode (Node.value node)))
                              ]
                            , context
                            )

                _ ->
                    ( [], context )


routeParamsMatchesNameOrError : Node TypeAnnotation -> List String -> List (Error {})
routeParamsMatchesNameOrError annotation moduleName =
    case stringFields annotation of
        Err error ->
            [ error ]

        Ok actualStringFields ->
            let
                expectedFields : Dict String Param
                expectedFields =
                    expectedRouteParamsFromModuleName moduleName
            in
            if actualStringFields == (expectedFields |> Dict.map (\_ value -> Ok value)) then
                []

            else
                [ Rule.error
                    { message = "RouteParams don't match Route Module name"
                    , details =
                        [ """Expected

"""
                            ++ expectedFieldsToRecordString moduleName
                            ++ "\n"
                        ]
                    }
                    (Node.range annotation)
                ]


expectedFieldsToRecordString : List String -> String
expectedFieldsToRecordString moduleName =
    "type alias RouteParams = "
        ++ (moduleName
                |> RoutePattern.fromModuleName
                |> Maybe.map (RoutePattern.toRouteParamsRecord >> Elm.Annotation.record >> Elm.ToString.annotation >> .signature)
                |> Maybe.withDefault "ERROR"
           )


expectedRouteParamsFromModuleName : List String -> Dict String Param
expectedRouteParamsFromModuleName moduleSegments =
    case moduleSegments of
        "Route" :: segments ->
            segments
                --|> List.filterMap segmentToParam
                |> RoutePattern.fromModuleName
                |> Maybe.map RoutePattern.toRouteParamTypes
                |> Maybe.withDefault []
                |> Dict.fromList

        _ ->
            Dict.empty


stringFields :
    Node TypeAnnotation
    -> Result (Error {}) (Dict String (Result (Node TypeAnnotation) Param))
stringFields typeAnnotation =
    case Node.value typeAnnotation of
        TypeAnnotation.Record recordDefinition ->
            let
                fields : Dict String (Result (Node TypeAnnotation) Param)
                fields =
                    recordDefinition
                        |> List.map Node.value
                        |> List.map
                            (\( name, annotation ) ->
                                ( Node.value name, paramType annotation )
                            )
                        |> Dict.fromList
            in
            Ok fields

        _ ->
            Err
                (Rule.error
                    { message = "RouteParams must be a record type alias."
                    , details =
                        [ """Expected a record type alias."""
                        ]
                    }
                    (Node.range typeAnnotation)
                )


paramType : Node TypeAnnotation -> Result (Node TypeAnnotation) Param
paramType typeAnnotation =
    case Node.value typeAnnotation of
        TypeAnnotation.Tupled [ first, second ] ->
            case ( Node.value first, Node.value second ) of
                ( TypeAnnotation.Typed firstType [], TypeAnnotation.Typed secondType [ listType ] ) ->
                    if
                        (Node.value firstType == ( [], "String" ))
                            && (Node.value secondType == ( [], "List" ))
                            && (Node.value listType |> isString)
                    then
                        Ok RequiredSplatParam

                    else
                        Err typeAnnotation

                _ ->
                    Err typeAnnotation

        TypeAnnotation.Typed moduleContext innerType ->
            -- TODO need to use module lookup table to handle Basics or aliases?
            case ( Node.value moduleContext, innerType ) of
                ( ( [], "String" ), [] ) ->
                    Ok RoutePattern.RequiredParam

                ( ( [], "Maybe" ), [ maybeOf ] ) ->
                    if isString (Node.value maybeOf) then
                        Ok RoutePattern.OptionalParam

                    else
                        Err typeAnnotation

                ( ( [], "List" ), [ listOf ] ) ->
                    if isString (Node.value listOf) then
                        Ok RoutePattern.OptionalSplatParam

                    else
                        Err typeAnnotation

                _ ->
                    Ok RoutePattern.OptionalParam

        _ ->
            Err typeAnnotation


isString : TypeAnnotation -> Bool
isString typeAnnotation =
    case typeAnnotation of
        TypeAnnotation.Typed moduleContext [] ->
            -- TODO need to use module lookup table to handle Basics or aliases?
            Node.value moduleContext == ( [], "String" )

        _ ->
            False


declarationVisitor : Node Declaration -> Direction -> Context -> ( List (Error {}), Context )
declarationVisitor node direction context =
    case ( direction, Node.value node ) of
        ( Rule.OnEnter, Declaration.AliasDeclaration { name, typeAnnotation } ) ->
            -- TODO check that generics is empty
            if context.isRouteModule == Just RouteModule && Node.value name == "RouteParams" then
                ( routeParamsMatchesNameOrError typeAnnotation context.moduleName
                , context
                )

            else
                ( [], context )

        _ ->
            ( [], context )


exposedNames : List (Node Exposing.TopLevelExpose) -> Set String
exposedNames exposedValues =
    exposedValues
        |> List.filterMap (Node.value >> getExposedName)
        |> Set.fromList


getExposedName : Exposing.TopLevelExpose -> Maybe String
getExposedName exposedValue =
    case exposedValue of
        Exposing.FunctionExpose name ->
            Just name

        Exposing.InfixExpose _ ->
            Nothing

        Exposing.TypeOrAliasExpose name ->
            Just name

        Exposing.TypeExpose exposedType ->
            Just exposedType.name


exposingListNode : Module -> Node Exposing
exposingListNode m =
    case m of
        Module.NormalModule x ->
            x.exposingList

        Module.PortModule x ->
            x.exposingList

        Module.EffectModule x ->
            x.exposingList
