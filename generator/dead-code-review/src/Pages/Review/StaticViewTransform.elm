module Pages.Review.StaticViewTransform exposing (rule)

{-| This rule transforms static region render calls into adopt calls in the client
bundle. This enables dead-code elimination of the static rendering dependencies
(markdown parsers, syntax highlighters, etc.) while preserving the pre-rendered
HTML for adoption by the virtual-dom.

## Transformations

    -- View.freeze (single argument, new API):
    View.freeze (heavyRender data)
    -- becomes:
    View.Static.adopt "0" |> Html.Styled.fromUnstyled |> Html.Styled.map never

    -- View.Static.static (plain Html):
    View.Static.static (heavyRender data)
    -- becomes:
    View.Static.adopt "0"

## Data Type Transformation

This rule also analyzes field access patterns on `app.data` and transforms the
`Data` type alias to remove ephemeral fields (those only used inside `freeze`
calls or in the `head` function).

Fields are classified as:
- **Ephemeral**: Used only inside `View.freeze` calls and/or `head` function
- **Persistent**: Used outside `freeze` (or both inside and outside)

Ephemeral fields are removed from the `Data` type alias in the client bundle,
enabling DCE to eliminate the field accessors and any rendering code that
depends on them.

Note: This rule always uses View.Static.adopt from the elm-pages package,
not from the user's View module. If View.Static is not imported, the rule
adds the import automatically.

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
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
    , viewStaticImport : ViewStaticImport
    , htmlStyledAlias : Maybe ModuleName
    , lastImportRow : Int
    , staticIndex : Int

    -- Field tracking
    , fieldsInFreeze : Set String
    , fieldsInHead : Set String
    , fieldsOutsideFreeze : Set String
    , inFreezeCall : Bool
    , inHeadFunction : Bool

    -- app.data binding tracking
    , appDataBindings : Set String

    -- Track if app.data is used as a whole (not field-accessed)
    -- If true, we can't safely determine ephemeral fields
    , appDataUsedAsWhole : Bool

    -- Data type location for transformation
    , dataTypeRange : Maybe Range
    , dataTypeFields : List ( String, Node TypeAnnotation )
    }


type ViewStaticImport
    = NotImported
    | ImportedAs ModuleName


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.StaticViewTransform" initialContext
        |> Rule.providesFixesForModuleRule
        |> Rule.withImportVisitor importVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withFinalModuleEvaluation finalEvaluation
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable () ->
            { lookupTable = lookupTable
            , viewStaticImport = NotImported
            , htmlStyledAlias = Nothing
            , lastImportRow = 2
            , staticIndex = 0
            , fieldsInFreeze = Set.empty
            , fieldsInHead = Set.empty
            , fieldsOutsideFreeze = Set.empty
            , inFreezeCall = False
            , inHeadFunction = False
            , appDataBindings = Set.empty
            , appDataUsedAsWhole = False
            , dataTypeRange = Nothing
            , dataTypeFields = []
            }
        )
        |> Rule.withModuleNameLookupTable


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        import_ =
            Node.value node

        moduleName =
            Node.value import_.moduleName

        importEndRow =
            (Node.range node).end.row
    in
    if moduleName == [ "View", "Static" ] then
        ( []
        , { context
            | viewStaticImport =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "View", "Static" ]
                    |> ImportedAs
            , lastImportRow = max context.lastImportRow importEndRow
          }
        )

    else if moduleName == [ "Html", "Styled" ] then
        ( []
        , { context
            | htmlStyledAlias =
                import_.moduleAlias
                    |> Maybe.map Node.value
                    |> Maybe.withDefault [ "Html", "Styled" ]
                    |> Just
            , lastImportRow = max context.lastImportRow importEndRow
          }
        )

    else
        ( []
        , { context | lastImportRow = max context.lastImportRow importEndRow }
        )


declarationEnterVisitor : Node Declaration -> Context -> ( List (Rule.Error {}), Context )
declarationEnterVisitor node context =
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
                ( [], { context | inHeadFunction = True } )

            else
                ( [], context )

        Declaration.AliasDeclaration typeAlias ->
            let
                typeName =
                    Node.value typeAlias.name
            in
            if typeName == "Data" then
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
                        in
                        ( []
                        , { context
                            | dataTypeRange = Just (Node.range typeAlias.typeAnnotation)
                            , dataTypeFields = fields
                          }
                        )

                    _ ->
                        ( [], context )

            else
                ( [], context )

        _ ->
            ( [], context )


declarationExitVisitor : Node Declaration -> Context -> ( List (Rule.Error {}), Context )
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
        -- Track entering freeze calls and check if app.data is used as a whole
        contextWithFreezeTracking =
            case Node.value node of
                Expression.Application (functionNode :: args) ->
                    case ModuleNameLookupTable.moduleNameFor context.lookupTable functionNode of
                        Just [ "View" ] ->
                            case Node.value functionNode of
                                Expression.FunctionOrValue _ "freeze" ->
                                    -- Check if any argument contains app.data passed to a function
                                    -- (not just field-accessed)
                                    let
                                        appDataPassedToFunction =
                                            args
                                                |> List.any
                                                    (\arg ->
                                                        case Node.value arg of
                                                            -- Direct app.data.field access is OK
                                                            Expression.RecordAccess innerExpr _ ->
                                                                False

                                                            -- If the arg is a function call that contains app.data,
                                                            -- we can't track field access
                                                            Expression.Application innerArgs ->
                                                                List.any (\a -> containsAppDataExpression a context) innerArgs

                                                            -- Direct app.data is being used as a whole
                                                            _ ->
                                                                isAppDataExpression arg context
                                                    )
                                    in
                                    { context
                                        | inFreezeCall = True
                                        , appDataUsedAsWhole = context.appDataUsedAsWhole || appDataPassedToFunction
                                    }

                                _ ->
                                    context

                        _ ->
                            context

                _ ->
                    context

        -- Track field access patterns
        contextWithFieldTracking =
            trackFieldAccess node contextWithFreezeTracking
    in
    -- Handle the transformations
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions of
                -- Single-argument application: View.freeze expr, View.Static.static expr
                functionNode :: _ :: [] ->
                    case ModuleNameLookupTable.moduleNameFor contextWithFieldTracking.lookupTable functionNode of
                        Just [ "View" ] ->
                            handleViewModuleCall functionNode node contextWithFieldTracking

                        Just [ "View", "Static" ] ->
                            handleViewStaticModuleCall functionNode node contextWithFieldTracking

                        _ ->
                            ( [], contextWithFieldTracking )

                _ ->
                    ( [], contextWithFieldTracking )

        _ ->
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


{-| Track field access on app.data and variables bound to app.data.
Also detects when app.data is used as a whole (not field-accessed).
-}
trackFieldAccess : Node Expression -> Context -> Context
trackFieldAccess node context =
    case Node.value node of
        -- Direct field access: app.data.fieldName
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isAppDataAccess innerExpr context then
                addFieldAccess fieldName context

            else
                -- Check for app.data.something.field (nested) - track top-level field
                case Node.value innerExpr of
                    Expression.RecordAccess innerInner (Node _ topLevelField) ->
                        if isAppDataAccess innerInner context then
                            addFieldAccess topLevelField context

                        else
                            context

                    _ ->
                        context

        -- Let expressions can bind app.data to a variable
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
                                                -- No arguments, could be binding app.data
                                                if isAppDataExpression fnDecl.expression context then
                                                    Set.insert (Node.value fnDecl.name) acc

                                                else
                                                    acc

                                            _ ->
                                                acc

                                    Expression.LetDestructuring pattern expr ->
                                        -- Handle: let { field1, field2 } = app.data in ...
                                        -- For now, conservatively mark all destructured fields
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


{-| Check if an expression is `app.data`
-}
isAppDataAccess : Node Expression -> Context -> Bool
isAppDataAccess node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "app" ->
                    True

                _ ->
                    False

        -- Also check for bound variables
        Expression.FunctionOrValue [] varName ->
            Set.member varName context.appDataBindings

        _ ->
            False


{-| Check if an expression represents app.data (for let binding detection)
-}
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


{-| Check if an expression contains app.data anywhere (recursive search).
This is used to detect when app.data is passed as an argument to a function.
-}
containsAppDataExpression : Node Expression -> Context -> Bool
containsAppDataExpression node context =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] "app" ->
                    True

                _ ->
                    containsAppDataExpression innerExpr context

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


{-| Extract variable names from a pattern (for destructuring)
-}
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


{-| Add a field access to the appropriate tracking set
-}
addFieldAccess : String -> Context -> Context
addFieldAccess fieldName context =
    if context.inFreezeCall then
        { context | fieldsInFreeze = Set.insert fieldName context.fieldsInFreeze }

    else if context.inHeadFunction then
        { context | fieldsInHead = Set.insert fieldName context.fieldsInHead }

    else
        { context | fieldsOutsideFreeze = Set.insert fieldName context.fieldsOutsideFreeze }


handleViewModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "freeze" ->
            let
                replacement =
                    viewStaticAdoptCallStyled context

                fixes =
                    [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                        ++ viewStaticImportFix context
            in
            ( [ createTransformErrorWithFixes "View.freeze" "View.Static.adopt" node fixes ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        Expression.FunctionOrValue _ "static" ->
            let
                replacement =
                    viewStaticAdoptCallStyled context

                fixes =
                    [ Review.Fix.replaceRangeBy (Node.range node) replacement ]
                        ++ viewStaticImportFix context
            in
            ( [ createTransformErrorWithFixes "View.static" "View.Static.adopt" node fixes ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        _ ->
            ( [], context )


handleViewStaticModuleCall : Node Expression -> Node Expression -> Context -> ( List (Error {}), Context )
handleViewStaticModuleCall functionNode node context =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "static" ->
            let
                replacement =
                    viewStaticAdoptCallPlain context
            in
            ( [ createTransformError "View.Static.static" "View.Static.adopt" node replacement ]
            , { context | staticIndex = context.staticIndex + 1 }
            )

        _ ->
            ( [], context )


createTransformError : String -> String -> Node Expression -> String -> Error {}
createTransformError fromFn toFn node replacement =
    Rule.errorWithFix
        { message = "Static region codemod: transform " ++ fromFn ++ " to " ++ toFn
        , details = [ "Transforms " ++ fromFn ++ " to " ++ toFn ++ " for client-side adoption and DCE" ]
        }
        (Node.range node)
        [ Review.Fix.replaceRangeBy (Node.range node) replacement
        ]


createTransformErrorWithFixes : String -> String -> Node Expression -> List Review.Fix.Fix -> Error {}
createTransformErrorWithFixes fromFn toFn node fixes =
    Rule.errorWithFix
        { message = "Static region codemod: transform " ++ fromFn ++ " to " ++ toFn
        , details = [ "Transforms " ++ fromFn ++ " to " ++ toFn ++ " for client-side adoption and DCE" ]
        }
        (Node.range node)
        fixes


{-| Generate a fix to add `import View.Static` if it's not already imported.
-}
viewStaticImportFix : Context -> List Review.Fix.Fix
viewStaticImportFix context =
    case context.viewStaticImport of
        ImportedAs _ ->
            -- Already imported, no fix needed
            []

        NotImported ->
            -- Add the import after the last import
            [ Review.Fix.insertAt
                { row = context.lastImportRow + 1, column = 1 }
                "import View.Static\n"
            ]


{-| Generate View.Static.adopt "index" for View module calls (View.freeze).

Wraps with Html.Styled conversion since the user's View module works with Html.Styled types.
Uses the correct Html.Styled alias if one is defined.
-}
viewStaticAdoptCallStyled : Context -> String
viewStaticAdoptCallStyled context =
    let
        viewStaticPrefix =
            case context.viewStaticImport of
                ImportedAs alias ->
                    String.join "." alias

                NotImported ->
                    "View.Static"

        htmlStyledPrefix =
            context.htmlStyledAlias
                |> Maybe.withDefault [ "Html", "Styled" ]
                |> String.join "."

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    -- Wrap with Html.Styled conversion to match the original View.freeze return type
    "(" ++ viewStaticPrefix ++ ".adopt " ++ idStr ++ " |> " ++ htmlStyledPrefix ++ ".fromUnstyled |> " ++ htmlStyledPrefix ++ ".map never)"


{-| Generate View.Static.adopt "index" for View.Static module calls.

No wrapper needed since View.Static functions work with plain Html.
-}
viewStaticAdoptCallPlain : Context -> String
viewStaticAdoptCallPlain context =
    let
        modulePrefix =
            case context.viewStaticImport of
                ImportedAs alias ->
                    String.join "." alias

                NotImported ->
                    "View.Static"

        idStr =
            "\"" ++ String.fromInt context.staticIndex ++ "\""
    in
    modulePrefix ++ ".adopt " ++ idStr


{-| Final evaluation - emit Data type transformation if there are ephemeral fields
-}
finalEvaluation : Context -> List (Error {})
finalEvaluation context =
    -- TODO: Re-enable Data type transformation when field tracking is more robust
    -- Currently disabled because tracking app.data usage is complex
    -- The freeze→adopt transformation still works and provides DCE benefits
    if True then
        []

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

                    -- Persistent fields: used outside freeze (or not used at all - conservative)
                    persistentFieldDefs =
                        context.dataTypeFields
                            |> List.filter (\( name, _ ) -> not (Set.member name ephemeralFields))
                in
                if Set.isEmpty ephemeralFields then
                    -- No ephemeral fields, nothing to transform
                    []

                else
                    -- Generate fix to rewrite Data type alias
                    -- Use single-line format for simplicity and to avoid indentation issues
                    let
                        newTypeAnnotation =
                            if List.isEmpty persistentFieldDefs then
                                "{}"

                            else
                                "{ "
                                    ++ (persistentFieldDefs
                                            |> List.map (\( name, typeNode ) -> name ++ " : " ++ typeAnnotationToString (Node.value typeNode))
                                            |> String.join ", "
                                       )
                                    ++ " }"
                    in
                    [ Rule.errorWithFix
                        { message = "Data type codemod: remove ephemeral fields"
                        , details =
                            [ "Removing ephemeral fields from Data type: " ++ String.join ", " (Set.toList ephemeralFields)
                            , "These fields are only used inside View.freeze calls and/or the head function, so they can be eliminated from the client bundle."
                            ]
                        }
                        range
                        [ Review.Fix.replaceRangeBy range newTypeAnnotation
                        ]
                    ]


{-| Convert a TypeAnnotation back to string representation.
This is a simplified version - may need enhancement for complex types.
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

                -- Wrap function types on the left in parens
                leftWrapped =
                    case left of
                        TypeAnnotation.FunctionTypeAnnotation _ _ ->
                            "(" ++ leftStr ++ ")"

                        _ ->
                            leftStr
            in
            leftWrapped ++ " -> " ++ rightStr
