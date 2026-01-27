module Pages.Review.ServerDataTransform exposing (rule)

{-| This rule transforms Route modules for the server/CLI bundle.

It performs the following transformations:

1. Renames `type alias Data = {...}` to `type alias Ephemeral = {...}`
2. Creates new `type alias Data = {...}` with only persistent fields
3. Generates `ephemeralToData : Ephemeral -> Data` conversion function

This enables the server to:
- Render views using the full `Ephemeral` type (all fields available)
- Encode only `Data` for wire transmission (reduced payload)
- Use standard Wire3 encoders/decoders for `Data` on both server and client

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module as Module exposing (Module)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)
import Set exposing (Set)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , moduleName : ModuleName

    -- Field tracking (same as client-side)
    , fieldsInFreeze : Set String
    , fieldsInHead : Set String
    , fieldsOutsideFreeze : Set String
    , inFreezeCall : Bool
    , inHeadFunction : Bool

    -- app.data binding tracking
    , appDataBindings : Set String

    -- Track if app.data is used as a whole
    , appDataUsedAsWhole : Bool

    -- Track where Data is used as a record constructor (needs to become Ephemeral)
    , dataConstructorRanges : List Range

    -- Data type location and fields
    , dataTypeRange : Maybe Range
    , dataTypeFields : List ( String, Node TypeAnnotation )

    -- End of Data type declaration for inserting new types
    , dataTypeEndRow : Int

    -- Track data function signature for updating Data -> Ephemeral
    , dataFunctionSignatureRange : Maybe Range
    , dataFunctionSignature : Maybe String

    -- Track if Ephemeral type already exists (transformation already applied)
    , hasEphemeralType : Bool

    -- Track all type references to Data (need to become Ephemeral)
    , dataTypeReferenceRanges : List Range

    -- Track range after "Data" in exposing list for inserting ", Ephemeral"
    , dataExportRange : Maybe Range
    }


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.ServerDataTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withModuleDefinitionVisitor moduleDefinitionVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


{-| Visit module definition to find where "Data" is exported.
-}
moduleDefinitionVisitor : Node Module -> Context -> ( List (Error {}), Context )
moduleDefinitionVisitor node context =
    case Node.value node of
        Module.NormalModule { exposingList } ->
            case Node.value exposingList of
                Exposing.Explicit exposedItems ->
                    -- Find the "Data" export and check if "Ephemeral" is already exported
                    let
                        dataExportRange =
                            exposedItems
                                |> List.filterMap
                                    (\exposedItem ->
                                        case Node.value exposedItem of
                                            Exposing.TypeOrAliasExpose "Data" ->
                                                Just (Node.range exposedItem)

                                            _ ->
                                                Nothing
                                    )
                                |> List.head

                        ephemeralAlreadyExported =
                            exposedItems
                                |> List.any
                                    (\exposedItem ->
                                        case Node.value exposedItem of
                                            Exposing.TypeOrAliasExpose "Ephemeral" ->
                                                True

                                            _ ->
                                                False
                                    )
                    in
                    -- Only set dataExportRange if Ephemeral is NOT already exported
                    -- Note: Don't set hasEphemeralType here - that's only for detecting
                    -- if the actual `type alias Ephemeral` declaration exists
                    if ephemeralAlreadyExported then
                        ( [], context )

                    else
                        ( [], { context | dataExportRange = dataExportRange } )

                Exposing.All _ ->
                    -- Exposing everything, Ephemeral will be exposed automatically
                    ( [], context )

        _ ->
            ( [], context )


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable moduleName () ->
            { lookupTable = lookupTable
            , moduleName = moduleName
            , fieldsInFreeze = Set.empty
            , fieldsInHead = Set.empty
            , fieldsOutsideFreeze = Set.empty
            , inFreezeCall = False
            , inHeadFunction = False
            , appDataBindings = Set.empty
            , appDataUsedAsWhole = False
            , dataConstructorRanges = []
            , dataTypeRange = Nothing
            , dataTypeFields = []
            , dataTypeEndRow = 0
            , dataFunctionSignatureRange = Nothing
            , dataFunctionSignature = Nothing
            , hasEphemeralType = False
            , dataTypeReferenceRanges = []
            , dataExportRange = Nothing
            }
        )
        |> Rule.withModuleNameLookupTable
        |> Rule.withModuleName


declarationEnterVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationEnterVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value

                -- Collect Data type references from the function signature
                dataRefs =
                    case function.signature of
                        Just signatureNode ->
                            extractDataTypeReferences (Node.value signatureNode).typeAnnotation

                        Nothing ->
                            []

                contextWithDataRefs =
                    { context | dataTypeReferenceRanges = context.dataTypeReferenceRanges ++ dataRefs }
            in
            if functionName == "head" then
                ( [], { contextWithDataRefs | inHeadFunction = True } )

            else if functionName == "data" then
                -- Track the data function's type signature for updating Data -> Ephemeral
                case function.signature of
                    Just signatureNode ->
                        let
                            signature =
                                Node.value signatureNode

                            typeAnnotation =
                                signature.typeAnnotation

                            signatureStr =
                                typeAnnotationToString (Node.value typeAnnotation)
                        in
                        ( []
                        , { contextWithDataRefs
                            | dataFunctionSignatureRange = Just (Node.range typeAnnotation)
                            , dataFunctionSignature = Just signatureStr
                          }
                        )

                    Nothing ->
                        ( [], contextWithDataRefs )

            else
                ( [], contextWithDataRefs )

        Declaration.AliasDeclaration typeAlias ->
            let
                typeName =
                    Node.value typeAlias.name
            in
            if typeName == "Ephemeral" then
                -- Ephemeral type already exists - transformation was already applied
                ( [], { context | hasEphemeralType = True } )

            else if typeName == "Data" then
                case Node.value typeAlias.typeAnnotation of
                    TypeAnnotation.Record recordFields ->
                        let
                            fields =
                                recordFields
                                    |> List.map
                                        (\fieldNode ->
                                            let
                                                ( nameNode, typeNode ) =
                                                    Node.value fieldNode
                                            in
                                            ( Node.value nameNode, typeNode )
                                        )

                            endRow =
                                (Node.range node).end.row
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range node)
                            , dataTypeFields = fields
                            , dataTypeEndRow = endRow
                          }
                        )

                    _ ->
                        ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )


declarationExitVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationExitVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration function ->
            let
                functionName =
                    function.declaration
                        |> Node.value
                        |> .name
                        |> Node.value
            in
            if functionName == "head" then
                ( [], { context | inHeadFunction = False } )

            else
                ( [], context )

        _ ->
            ( [], context )


expressionEnterVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionEnterVisitor node context =
    let
        -- Track where Data is used as a record constructor (needs to become Ephemeral)
        contextWithDataConstructorCheck =
            case Node.value node of
                Expression.FunctionOrValue [] "Data" ->
                    { context | dataConstructorRanges = Node.range node :: context.dataConstructorRanges }

                _ ->
                    context

        -- Track entering freeze calls
        contextWithFreezeTracking =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor contextWithDataConstructorCheck.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    let
                                        appDataPassedToFunction =
                                            args
                                                |> List.any
                                                    (\arg ->
                                                        case Node.value arg of
                                                            Expression.RecordAccess _ _ ->
                                                                False

                                                            Expression.Application innerArgs ->
                                                                List.any (\a -> containsAppDataExpression a contextWithDataConstructorCheck) innerArgs

                                                            _ ->
                                                                isAppDataExpression arg contextWithDataConstructorCheck
                                                    )
                                    in
                                    { contextWithDataConstructorCheck
                                        | inFreezeCall = True
                                        , appDataUsedAsWhole = contextWithDataConstructorCheck.appDataUsedAsWhole || appDataPassedToFunction
                                    }

                                _ ->
                                    contextWithDataConstructorCheck

                        _ ->
                            contextWithDataConstructorCheck

                _ ->
                    contextWithDataConstructorCheck

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking
    in
    ( [], contextWithFieldTracking )


expressionExitVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionExitVisitor node context =
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                Just [ "View" ] ->
                    case Node.value functionNode of
                        Expression.FunctionOrValue _ "freeze" ->
                            ( [], { context | inFreezeCall = False } )

                        _ ->
                            ( [], context )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


{-| Track field access on app.data
-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isAppDataAccess innerExpr context then
                addFieldAccess fieldName context

            else
                case Node.value innerExpr of
                    Expression.RecordAccess innerInner (Node _ topLevelField) ->
                        if isAppDataAccess innerInner context then
                            addFieldAccess topLevelField context

                        else
                            context

                    _ ->
                        context

        Expression.LetExpression letBlock ->
            let
                newBindings =
                    letBlock.declarations
                        |> List.foldl
                            (\declNode acc ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        let
                                            fnDecl =
                                                Node.value letFn.declaration
                                        in
                                        case fnDecl.arguments of
                                            [] ->
                                                if isAppDataExpression fnDecl.expression context then
                                                    Set.insert (Node.value fnDecl.name) acc

                                                else
                                                    acc

                                            _ ->
                                                acc

                                    Expression.LetDestructuring pattern expr ->
                                        if isAppDataExpression expr context then
                                            extractPatternNames pattern
                                                |> Set.union acc

                                        else
                                            acc
                            )
                            context.appDataBindings
            in
            { context | appDataBindings = newBindings }

        _ ->
            context


isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "app" ->
                    True

                _ ->
                    False

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


isAppDataExpression : Node Expression -> Context -> Bool
isAppDataExpression node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "app" ->
                    True

                _ ->
                    False

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


containsAppDataExpression : Node Expression -> Context -> Bool
containsAppDataExpression node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "app" ->
                    True

                _ ->
                    containsAppDataExpression innerExpr context

        Expression.RecordAccess _ _ ->
            False

        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        Expression.Application exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.ParenthesizedExpression inner ->
            containsAppDataExpression inner context

        Expression.TupledExpression exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.ListExpr exprs ->
            List.any (\e -> containsAppDataExpression e context) exprs

        Expression.IfBlock cond then_ else_ ->
            containsAppDataExpression cond context
                || containsAppDataExpression then_ context
                || containsAppDataExpression else_ context

        Expression.CaseExpression caseBlock ->
            containsAppDataExpression caseBlock.expression context
                || List.any (\( _, expr ) -> containsAppDataExpression expr context) caseBlock.cases

        Expression.LambdaExpression lambda ->
            containsAppDataExpression lambda.expression context

        Expression.LetExpression letBlock ->
            containsAppDataExpression letBlock.expression context

        Expression.OperatorApplication _ _ left right ->
            containsAppDataExpression left context
                || containsAppDataExpression right context

        _ ->
            False


extractPatternNames : Node Pattern -> Set String
extractPatternNames node =
    case Node.value node of
        Pattern.VarPattern name ->
            Set.singleton name

        Pattern.RecordPattern fields ->
            fields |> List.map Node.value |> Set.fromList

        Pattern.TuplePattern patterns ->
            patterns |> List.foldl (\p acc -> Set.union (extractPatternNames p) acc) Set.empty

        Pattern.ParenthesizedPattern inner ->
            extractPatternNames inner

        Pattern.AsPattern inner (Node _ name) ->
            Set.insert name (extractPatternNames inner)

        _ ->
            Set.empty


{-| Extract all ranges where "Data" appears as a type reference in a type annotation.
-}
extractDataTypeReferences : Node TypeAnnotation -> List Range
extractDataTypeReferences node =
    case Node.value node of
        TypeAnnotation.Typed (Node typeRange ( [], "Data" )) args ->
            -- Found a reference to "Data" (unqualified)
            typeRange :: List.concatMap extractDataTypeReferences args

        TypeAnnotation.Typed _ args ->
            -- Some other type, but check its arguments
            List.concatMap extractDataTypeReferences args

        TypeAnnotation.Tupled nodes ->
            List.concatMap extractDataTypeReferences nodes

        TypeAnnotation.Record fields ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, fieldType )) ->
                        extractDataTypeReferences fieldType
                    )

        TypeAnnotation.GenericRecord _ (Node _ fields) ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, fieldType )) ->
                        extractDataTypeReferences fieldType
                    )

        TypeAnnotation.FunctionTypeAnnotation left right ->
            extractDataTypeReferences left ++ extractDataTypeReferences right

        TypeAnnotation.GenericType _ ->
            []

        TypeAnnotation.Unit ->
            []


addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.inFreezeCall then
        { context | fieldsInFreeze = Set.insert fieldName context.fieldsInFreeze }

    else if context.inHeadFunction then
        { context | fieldsInHead = Set.insert fieldName context.fieldsInHead }

    else
        { context | fieldsOutsideFreeze = Set.insert fieldName context.fieldsOutsideFreeze }


{-| Final evaluation - generate Ephemeral/Data split and ephemeralToData function.
-}
finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    -- Skip if transformation was already applied (Ephemeral type exists)
    if context.hasEphemeralType then
        []

    -- Skip transformation if we can't safely analyze field usage
    -- (app.data passed as whole to a function)
    else if context.appDataUsedAsWhole then
        []

    else
        case context.dataTypeRange of
            Nothing ->
                []

            Just range ->
                let
                    -- Ephemeral fields: used only in freeze or head (not outside)
                    ephemeralFields =
                        Set.union context.fieldsInFreeze context.fieldsInHead
                            |> Set.filter (\f -> not (Set.member f context.fieldsOutsideFreeze))

                    -- Persistent fields for the new Data type
                    persistentFieldDefs =
                        context.dataTypeFields
                            |> List.filter (\( name, _ ) -> not (Set.member name ephemeralFields))
                in
                if Set.isEmpty ephemeralFields then
                    -- No ephemeral fields, nothing to transform
                    []

                else
                    -- Generate the transformation:
                    -- 1. Rename Data to Ephemeral
                    -- 2. Add new Data type with only persistent fields
                    -- 3. Add ephemeralToData function
                    let
                        -- Generate Ephemeral type alias (same as original Data)
                        ephemeralTypeAlias =
                            "type alias Ephemeral =\n    { "
                                ++ (context.dataTypeFields
                                        |> List.map
                                            (\( name, typeNode ) ->
                                                name ++ " : " ++ typeAnnotationToString (Node.value typeNode)
                                            )
                                        |> String.join "\n    , "
                                   )
                                ++ "\n    }"

                        -- Generate new Data type alias (persistent fields only)
                        newDataTypeAlias =
                            if List.isEmpty persistentFieldDefs then
                                "type alias Data =\n    {}"

                            else
                                "type alias Data =\n    { "
                                    ++ (persistentFieldDefs
                                            |> List.map
                                                (\( name, typeNode ) ->
                                                    name ++ " : " ++ typeAnnotationToString (Node.value typeNode)
                                                )
                                            |> String.join "\n    , "
                                       )
                                    ++ "\n    }"

                        -- Generate ephemeralToData function
                        ephemeralToDataFn =
                            if List.isEmpty persistentFieldDefs then
                                "ephemeralToData : Ephemeral -> Data\nephemeralToData _ =\n    {}"

                            else
                                "ephemeralToData : Ephemeral -> Data\nephemeralToData ephemeral =\n    { "
                                    ++ (persistentFieldDefs
                                            |> List.map (\( name, _ ) -> name ++ " = ephemeral." ++ name)
                                            |> String.join "\n    , "
                                       )
                                    ++ "\n    }"

                        -- Full replacement: Ephemeral + Data + ephemeralToData
                        fullReplacement =
                            ephemeralTypeAlias
                                ++ "\n\n\n"
                                ++ newDataTypeAlias
                                ++ "\n\n\n"
                                ++ ephemeralToDataFn

                        -- Update data function signature: Data -> Ephemeral
                        dataSignatureFix =
                            case ( context.dataFunctionSignatureRange, context.dataFunctionSignature ) of
                                ( Just sigRange, Just sigStr ) ->
                                    -- Replace "Data" with "Ephemeral" in the signature
                                    -- The data function returns BackendTask ... Data, we need it to return Ephemeral
                                    let
                                        updatedSig =
                                            String.replace " Data" " Ephemeral" sigStr
                                    in
                                    if updatedSig /= sigStr then
                                        [ Rule.errorWithFix
                                            { message = "Server codemod: update data function return type"
                                            , details =
                                                [ "Changing return type from Data to Ephemeral."
                                                , "The data function now returns Ephemeral (full type) for rendering."
                                                ]
                                            }
                                            sigRange
                                            [ Review.Fix.replaceRangeBy sigRange updatedSig ]
                                        ]

                                    else
                                        []

                                _ ->
                                    []

                        -- Fix Data constructor uses (e.g., map4 Data -> map4 Ephemeral)
                        dataConstructorFixes =
                            context.dataConstructorRanges
                                |> List.map
                                    (\constructorRange ->
                                        Rule.errorWithFix
                                            { message = "Server codemod: update Data constructor to Ephemeral"
                                            , details =
                                                [ "Changing Data to Ephemeral in record constructor usage."
                                                , "The full record type is now called Ephemeral."
                                                ]
                                            }
                                            constructorRange
                                            [ Review.Fix.replaceRangeBy constructorRange "Ephemeral" ]
                                    )

                        -- Fix Data type references in function signatures (e.g., App Data -> App Ephemeral)
                        dataTypeReferenceFixes =
                            context.dataTypeReferenceRanges
                                |> List.map
                                    (\refRange ->
                                        Rule.errorWithFix
                                            { message = "Server codemod: update Data type reference to Ephemeral"
                                            , details =
                                                [ "Changing Data to Ephemeral in type signature."
                                                , "The server uses Ephemeral (full type) for views."
                                                ]
                                            }
                                            refRange
                                            [ Review.Fix.replaceRangeBy refRange "Ephemeral" ]
                                    )

                        -- Fix module exports to include Ephemeral
                        exportFix =
                            case context.dataExportRange of
                                Just exportRange ->
                                    -- Insert ", Ephemeral" after "Data" in exports
                                    [ Rule.errorWithFix
                                        { message = "Server codemod: export Ephemeral type"
                                        , details =
                                            [ "Adding Ephemeral to module exports."
                                            , "The generated Main.elm needs to reference Route.*.Ephemeral."
                                            ]
                                        }
                                        exportRange
                                        [ Review.Fix.insertAt exportRange.end ", Ephemeral, ephemeralToData" ]
                                    ]

                                Nothing ->
                                    []
                    in
                    Rule.errorWithFix
                        { message = "Server codemod: split Data into Ephemeral and Data"
                        , details =
                            [ "Renaming Data to Ephemeral (full type) and creating new Data (persistent fields only)."
                            , "Ephemeral fields: " ++ String.join ", " (Set.toList ephemeralFields)
                            , "Generating ephemeralToData conversion function for wire encoding."
                            ]
                        }
                        range
                        [ Review.Fix.replaceRangeBy range fullReplacement
                        ]
                        :: dataSignatureFix
                        ++ dataConstructorFixes
                        ++ dataTypeReferenceFixes
                        ++ exportFix


{-| Convert a TypeAnnotation back to string representation.
-}
typeAnnotationToString : TypeAnnotation -> String
typeAnnotationToString typeAnnotation =
    case typeAnnotation of
        TypeAnnotation.GenericType name ->
            name

        TypeAnnotation.Typed (Node _ ( moduleName, name )) args ->
            let
                qualified =
                    case moduleName of
                        [] ->
                            name

                        _ ->
                            String.join "." moduleName ++ "." ++ name

                argsStr =
                    args
                        |> List.map (\(Node _ arg) -> typeAnnotationToString arg)
                        |> List.map
                            (\s ->
                                if String.contains " " s && not (String.startsWith "(" s) then
                                    "(" ++ s ++ ")"

                                else
                                    s
                            )
                        |> String.join " "
            in
            if String.isEmpty argsStr then
                qualified

            else
                qualified ++ " " ++ argsStr

        TypeAnnotation.Unit ->
            "()"

        TypeAnnotation.Tupled nodes ->
            "( "
                ++ (nodes
                        |> List.map (\(Node _ t) -> typeAnnotationToString t)
                        |> String.join ", "
                   )
                ++ " )"

        TypeAnnotation.Record fields ->
            if List.isEmpty fields then
                "{}"

            else
                "{ "
                    ++ (fields
                            |> List.map
                                (\(Node _ ( Node _ fieldName, Node _ fieldType )) ->
                                    fieldName ++ " : " ++ typeAnnotationToString fieldType
                                )
                            |> String.join ", "
                       )
                    ++ " }"

        TypeAnnotation.GenericRecord (Node _ extName) (Node _ fields) ->
            "{ "
                ++ extName
                ++ " | "
                ++ (fields
                        |> List.map
                            (\(Node _ ( Node _ fieldName, Node _ fieldType )) ->
                                fieldName ++ " : " ++ typeAnnotationToString fieldType
                            )
                        |> String.join ", "
                   )
                ++ " }"

        TypeAnnotation.FunctionTypeAnnotation (Node _ left) (Node _ right) ->
            let
                leftStr =
                    typeAnnotationToString left

                rightStr =
                    typeAnnotationToString right

                leftWrapped =
                    case left of
                        TypeAnnotation.FunctionTypeAnnotation _ _ ->
                            "(" ++ leftStr ++ ")"

                        _ ->
                            leftStr
            in
            leftWrapped ++ " -> " ++ rightStr
