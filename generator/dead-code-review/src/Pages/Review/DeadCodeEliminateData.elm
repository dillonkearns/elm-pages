module Pages.Review.DeadCodeEliminateData exposing (rule)

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.Range exposing (Range)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , importContext : Dict (List String) ImportContext
    , firstImport : Maybe Range
    }


type ImportReference
    = QualifiedReference
    | UnqualifiedReference (List String)


type alias ImportContext =
    { moduleName : ModuleName
    , moduleAlias : Maybe ModuleName
    , exposedFunctions : Exposed

    --Maybe Exposing
    }


type Exposed
    = AllExposed
    | SomeExposed (List String)


toImportContext : Import -> ( List String, ImportContext )
toImportContext import_ =
    ( import_.moduleName |> Node.value
    , { moduleName = import_.moduleName |> Node.value
      , moduleAlias = import_.moduleAlias |> Maybe.map Node.value
      , exposedFunctions =
            import_.exposingList
                |> Maybe.map Node.value
                |> Maybe.map
                    (\exposingList ->
                        case exposingList of
                            Elm.Syntax.Exposing.All _ ->
                                AllExposed

                            Elm.Syntax.Exposing.Explicit nodes ->
                                AllExposed
                    )
                |> Maybe.withDefault (SomeExposed [])
      }
    )


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.DeadCodeEliminateData" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.withDeclarationEnterVisitor declarationVisitor
        |> Rule.withImportVisitor importVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


finalEvaluation : Context -> List (Rule.Error {})
finalEvaluation context =
    case Dict.get [ "FatalError" ] context.importContext of
        Nothing ->
            let
                importAddRange : { start : { row : Int, column : Int }, end : { row : Int, column : Int } }
                importAddRange =
                    context.firstImport |> Maybe.withDefault { start = { row = 0, column = 0 }, end = { row = 0, column = 0 } }
            in
            [ Rule.errorWithFix
                { message = "Codemod"
                , details = [ "" ]
                }
                importAddRange
                [ Review.Fix.insertAt importAddRange.end "\nimport FatalError\n"
                ]
            ]

        _ ->
            []


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable () ->
            { lookupTable = lookupTable
            , importContext = Dict.empty
            , firstImport = Nothing
            }
        )
        |> Rule.withModuleNameLookupTable


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        ( key, value ) =
            Node.value node
                |> toImportContext
    in
    ( []
    , { context
        | importContext =
            context.importContext |> Dict.insert key value
        , firstImport = context.firstImport |> Maybe.withDefault (Node.range node) |> Just
      }
    )


declarationVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationVisitor node context =
    let
        exceptionFromString : String
        exceptionFromString =
            "("
                ++ referenceFunction context.importContext ( [ "FatalError" ], "fromString" )
                ++ " \"\")"
    in
    case Node.value node of
        Declaration.FunctionDeclaration { declaration } ->
            case Node.value declaration of
                { name, expression } ->
                    case ( Node.value name, Node.value expression ) of
                        ( "template", Expression.RecordExpr setters ) ->
                            let
                                dataFieldValue : Maybe (Node ( Node String, Node Expression ))
                                dataFieldValue =
                                    setters
                                        |> List.filterMap
                                            (\recordSetter ->
                                                case Node.value recordSetter of
                                                    ( keyNode, valueNode ) ->
                                                        if Node.value keyNode == "data" || Node.value keyNode == "action" then
                                                            if isAlreadyApplied context.lookupTable (Node.value valueNode) then
                                                                Nothing

                                                            else
                                                                recordSetter |> Just

                                                        else
                                                            Nothing
                                            )
                                        |> List.head
                            in
                            dataFieldValue
                                |> Maybe.map
                                    (\dataValue ->
                                        ( [ Rule.errorWithFix
                                                { message = "Codemod"
                                                , details = [ "" ]
                                                }
                                                (Node.range dataValue)
                                                -- TODO need to replace `action` as well
                                                [ ("data = "
                                                    ++ referenceFunction context.importContext ( [ "BackendTask" ], "fail" )
                                                    -- TODO add `import FatalError` if not present (and use alias if present)
                                                    ++ " "
                                                    ++ exceptionFromString
                                                    ++ "\n    "
                                                  )
                                                    |> Review.Fix.replaceRangeBy (Node.range dataValue)
                                                ]
                                          ]
                                        , context
                                        )
                                    )
                                |> Maybe.withDefault
                                    ( [], context )

                        _ ->
                            ( [], context )

        _ ->
            ( [], context )


expressionVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions |> List.map (\applicationNode -> ( ModuleNameLookupTable.moduleNameFor context.lookupTable applicationNode, Node.value applicationNode )) of
                [ ( Just [ "RouteBuilder" ], Expression.FunctionOrValue _ pageBuilderName ), ( _, Expression.RecordExpr fields ) ] ->
                    let
                        dataFieldValue : List ( String, Node ( Node String, Node Expression ) )
                        dataFieldValue =
                            fields
                                |> List.filterMap
                                    (\recordSetter ->
                                        case Node.value recordSetter of
                                            ( keyNode, valueNode ) ->
                                                if Node.value keyNode == "data" || Node.value keyNode == "action" then
                                                    if isAlreadyApplied context.lookupTable (Node.value valueNode) then
                                                        Nothing

                                                    else
                                                        ( Node.value keyNode, recordSetter ) |> Just

                                                else
                                                    Nothing
                                    )
                    in
                    ( dataFieldValue
                        |> List.concatMap
                            (\( key, dataValue ) ->
                                let
                                    exceptionFromString : String
                                    exceptionFromString =
                                        "("
                                            ++ referenceFunction context.importContext ( [ "FatalError" ], "fromString" )
                                            ++ " \"\")"
                                in
                                [ Rule.errorWithFix
                                    { message = "Codemod"
                                    , details = [ "" ]
                                    }
                                    (Node.range dataValue)
                                    [ Review.Fix.replaceRangeBy (Node.range dataValue)
                                        (key
                                            ++ " = "
                                            ++ (case pageBuilderName of
                                                    "preRender" ->
                                                        "\\_ -> "
                                                            ++ referenceFunction context.importContext ( [ "BackendTask" ], "fail" )
                                                            ++ " "
                                                            ++ exceptionFromString

                                                    "preRenderWithFallback" ->
                                                        "\\_ -> "
                                                            ++ referenceFunction context.importContext ( [ "BackendTask" ], "fail" )
                                                            ++ " "
                                                            ++ exceptionFromString

                                                    "serverRender" ->
                                                        "\\_ -> "
                                                            ++ referenceFunction context.importContext ( [ "Server", "Request" ], "oneOf" )
                                                            ++ " []\n        "

                                                    "single" ->
                                                        referenceFunction context.importContext ( [ "BackendTask" ], "fail" )
                                                            ++ " "
                                                            ++ exceptionFromString
                                                            ++ "\n       "

                                                    _ ->
                                                        "data"
                                               )
                                        )
                                    ]
                                ]
                            )
                    , context
                    )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


referenceFunction : Dict (List String) ImportContext -> ( List String, String ) -> String
referenceFunction dict ( rawModuleName, rawFunctionName ) =
    let
        ( moduleName, functionName ) =
            case dict |> Dict.get rawModuleName of
                Just import_ ->
                    ( import_.moduleAlias |> Maybe.withDefault rawModuleName
                    , rawFunctionName
                    )

                Nothing ->
                    ( rawModuleName, rawFunctionName )
    in
    moduleName ++ [ functionName ] |> String.join "."


isAlreadyApplied : ModuleNameLookupTable -> Expression -> Bool
isAlreadyApplied lookupTable expression =
    case expression of
        Expression.LambdaExpression info ->
            case Node.value info.expression of
                Expression.Application applicationNodes ->
                    case applicationNodes |> List.map Node.value of
                        (Expression.FunctionOrValue _ "fail") :: _ ->
                            let
                                resolvedModuleName : ModuleName
                                resolvedModuleName =
                                    applicationNodes
                                        |> List.head
                                        |> Maybe.andThen
                                            (\functionNode ->
                                                ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                            )
                                        |> Maybe.withDefault []
                            in
                            resolvedModuleName == [ "BackendTask" ]

                        (Expression.FunctionOrValue _ "oneOf") :: (Expression.ListExpr []) :: _ ->
                            let
                                resolvedModuleName : ModuleName
                                resolvedModuleName =
                                    applicationNodes
                                        |> List.head
                                        |> Maybe.andThen
                                            (\functionNode ->
                                                ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                            )
                                        |> Maybe.withDefault []
                            in
                            resolvedModuleName == [ "Server", "Request" ]

                        _ ->
                            False

                _ ->
                    False

        Expression.Application applicationNodes ->
            case applicationNodes |> List.map Node.value of
                (Expression.FunctionOrValue _ "fail") :: _ ->
                    let
                        resolvedModuleName : ModuleName
                        resolvedModuleName =
                            applicationNodes
                                |> List.head
                                |> Maybe.andThen
                                    (\functionNode ->
                                        ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                    )
                                |> Maybe.withDefault []
                    in
                    resolvedModuleName == [ "BackendTask" ]

                _ ->
                    False

        _ ->
            False
