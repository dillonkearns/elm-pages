module Pages.Review.PersistentFieldTracking exposing
    ( AppDataClassification
    , CasePatternResult(..)
    , FieldAccessResult(..)
    , HelperAnalysis
    , PendingHelperAction(..)
    , analyzeHelperFunction
    , classifyAppDataArguments
    , computeEphemeralFields
    , containsAppDataExpression
    , determinePendingHelperAction
    , extractAppDataAccessorApplicationField
    , extractAppDataFieldName
    , extractAppDataBindingsFromLet
    , extractCasePatternFields
    , extractDataTypeRanges
    , extractFieldAccess
    , extractFieldNames
    , extractPatternName
    , extractPatternNames
    , extractRecordPatternFields
    , extractPipeAccessorField
    , extractAccessorFieldFromApplication
    , extractAppDataPipeAccessorField
    , isAppDataAccess
    , isExitingFreezeCall
    , isViewFreezeCall
    , resolvePendingHelperCalls
    , typeAnnotationToString
    )

{-| Shared utilities for persistent field tracking in elm-review rules.

Both StaticViewTransform (client) and ServerDataTransform (server) need to agree
on which fields are ephemeral. This module provides the shared analysis functions
to ensure consistency.

@docs AppDataClassification
@docs CasePatternResult
@docs FieldAccessResult
@docs HelperAnalysis
@docs analyzeHelperFunction
@docs classifyAppDataArguments, computeEphemeralFields, containsAppDataExpression
@docs extractCasePatternFields
@docs extractFieldAccess, extractFieldNames
@docs extractPatternName, extractPatternNames, extractRecordPatternFields
@docs extractPipeAccessorField, extractAccessorFieldFromApplication
@docs extractAppDataAccessorApplicationField, extractAppDataFieldName, extractAppDataPipeAccessorField
@docs isAppDataAccess, isViewFreezeCall, resolvePendingHelperCalls
@docs typeAnnotationToString

-}

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    { paramName : String -- First parameter name
    , accessedFields : Set String -- Fields accessed on first param (e.g., param.field)
    , isTrackable : Bool -- False if param is used in ways we can't track
    , aliasTarget : Maybe String -- If this is an alias to another function (e.g., myRender = renderContent)
    }


{-| Analyze a helper function to determine which fields it accesses on its first parameter.

This enables tracking field usage when app.data is passed to a helper function.
Also handles record destructuring patterns like `renderContent { title, body } = ...`
where we know EXACTLY which fields are used.

Also detects function aliases like `myRender = renderContent` where the function
has no parameters and its body is just a reference to another function.

-}
analyzeHelperFunction : Expression.Function -> Maybe HelperAnalysis
analyzeHelperFunction function =
    let
        declaration =
            Node.value function.declaration

        arguments =
            declaration.arguments

        body =
            declaration.expression
    in
    case arguments of
        firstArg :: _ ->
            case extractPatternName firstArg of
                Just paramName ->
                    -- Regular variable pattern: analyze body for field accesses
                    let
                        ( accessedFields, isTrackable ) =
                            analyzeFieldAccessesOnParam paramName body
                    in
                    Just
                        { paramName = paramName
                        , accessedFields = accessedFields
                        , isTrackable = isTrackable
                        , aliasTarget = Nothing
                        }

                Nothing ->
                    -- First param is a pattern - check if it's a record pattern
                    case extractRecordPatternFields firstArg of
                        Just fields ->
                            -- Record pattern like { title, body }
                            -- We know EXACTLY which fields are accessed - no body analysis needed!
                            Just
                                { paramName = "_record_pattern_"
                                , accessedFields = fields
                                , isTrackable = True
                                , aliasTarget = Nothing
                                }

                        Nothing ->
                            -- Other pattern (tuple, constructor, etc.) - can't track safely
                            Nothing

        [] ->
            -- No parameters - check if this is a function alias like `myRender = renderContent`
            case extractSimpleFunctionReference body of
                Just targetFuncName ->
                    -- This is an alias to another function
                    Just
                        { paramName = "_alias_"
                        , accessedFields = Set.empty
                        , isTrackable = True
                        , aliasTarget = Just targetFuncName
                        }

                Nothing ->
                    -- Not a simple function reference, can't track
                    Nothing


{-| Extract a simple local function reference from an expression.

Returns Just funcName if the expression is a simple reference to a local function
(e.g., `renderContent` not `Module.renderContent`).

-}
extractSimpleFunctionReference : Node Expression -> Maybe String
extractSimpleFunctionReference node =
    case Node.value node of
        Expression.FunctionOrValue [] funcName ->
            -- Local function reference (not qualified)
            -- Make sure it's not a constructor (starts with uppercase)
            if Char.isLower (String.uncons funcName |> Maybe.map Tuple.first |> Maybe.withDefault 'A') then
                Just funcName

            else
                Nothing

        Expression.ParenthesizedExpression inner ->
            extractSimpleFunctionReference inner

        _ ->
            Nothing


{-| Analyze an expression to find all field accesses on a given parameter name.

Returns (accessedFields, isTrackable) where:

  - accessedFields: Set of field names accessed like `param.fieldName`
  - isTrackable: False if the parameter is used in ways we can't track
    (passed to another function, used in case expression, etc.)

-}
analyzeFieldAccessesOnParam : String -> Node Expression -> ( Set String, Bool )
analyzeFieldAccessesOnParam paramName expr =
    -- Start with just the parameter name as the only "alias" we track
    analyzeFieldAccessesWithAliases (Set.singleton paramName) expr ( Set.empty, True )


{-| Check if a variable name is the parameter or an alias of the parameter.
-}
isParamOrAlias : Set String -> String -> Bool
isParamOrAlias paramAliases varName =
    Set.member varName paramAliases


{-| Analyze field accesses with support for let-bound aliases of the parameter.

The paramAliases set contains the original parameter name and any variables
that are simple aliases (e.g., `let d = data in ...`).

-}
analyzeFieldAccessesWithAliases : Set String -> Node Expression -> ( Set String, Bool ) -> ( Set String, Bool )
analyzeFieldAccessesWithAliases paramAliases node ( fields, trackable ) =
    if not trackable then
        ( fields, False )

    else
        case Node.value node of
            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                case Node.value innerExpr of
                    Expression.FunctionOrValue [] varName ->
                        if isParamOrAlias paramAliases varName then
                            ( Set.insert fieldName fields, trackable )

                        else
                            ( fields, trackable )

                    _ ->
                        analyzeFieldAccessesWithAliases paramAliases innerExpr ( fields, trackable )

            Expression.FunctionOrValue [] varName ->
                if isParamOrAlias paramAliases varName then
                    -- Bare usage of param or alias - can't track
                    ( fields, False )

                else
                    ( fields, trackable )

            -- Function application - check for accessor function pattern .field param
            Expression.Application exprs ->
                case extractAccessorFieldFromApplicationWithAliases exprs paramAliases of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable )

                    Nothing ->
                        List.foldl
                            (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
                            ( fields, trackable )
                            exprs

            Expression.LetExpression letBlock ->
                let
                    -- Extract any new aliases from this let block
                    -- An alias is a simple binding like `let d = param` where param is already an alias
                    newAliases =
                        extractAliasesFromLetDeclarations paramAliases letBlock.declarations

                    -- Combined aliases for analyzing the let body
                    allAliases =
                        Set.union paramAliases newAliases

                    -- Analyze declarations, but don't recurse into alias bindings
                    -- (they're just creating aliases, not using fields)
                    ( declFields, declTrackable ) =
                        List.foldl
                            (\declNode acc ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        let
                                            fnDecl =
                                                Node.value letFn.declaration

                                            bindingName =
                                                Node.value fnDecl.name

                                            isAlias =
                                                Set.member bindingName newAliases
                                        in
                                        if isAlias then
                                            -- Skip analyzing alias bindings - they're just aliases
                                            acc

                                        else
                                            analyzeFieldAccessesWithAliases allAliases fnDecl.expression acc

                                    Expression.LetDestructuring _ letExpr ->
                                        analyzeFieldAccessesWithAliases allAliases letExpr acc
                            )
                            ( fields, trackable )
                            letBlock.declarations
                in
                analyzeFieldAccessesWithAliases allAliases letBlock.expression ( declFields, declTrackable )

            Expression.IfBlock cond then_ else_ ->
                let
                    ( condFields, condTrackable ) =
                        analyzeFieldAccessesWithAliases paramAliases cond ( fields, trackable )

                    ( thenFields, thenTrackable ) =
                        analyzeFieldAccessesWithAliases paramAliases then_ ( condFields, condTrackable )
                in
                analyzeFieldAccessesWithAliases paramAliases else_ ( thenFields, thenTrackable )

            Expression.CaseExpression caseBlock ->
                let
                    caseOnParamOrAlias =
                        case Node.value caseBlock.expression of
                            Expression.FunctionOrValue [] varName ->
                                isParamOrAlias paramAliases varName

                            _ ->
                                False

                    ( exprFields, exprTrackable ) =
                        if caseOnParamOrAlias then
                            ( fields, False )

                        else
                            analyzeFieldAccessesWithAliases paramAliases caseBlock.expression ( fields, trackable )
                in
                List.foldl
                    (\( _, caseExpr ) acc -> analyzeFieldAccessesWithAliases paramAliases caseExpr acc)
                    ( exprFields, exprTrackable )
                    caseBlock.cases

            Expression.LambdaExpression lambda ->
                let
                    -- Check if any lambda arg shadows a param alias
                    shadowsAlias =
                        lambda.args
                            |> List.any
                                (\arg ->
                                    case extractPatternName arg of
                                        Just name ->
                                            isParamOrAlias paramAliases name

                                        Nothing ->
                                            False
                                )
                in
                if shadowsAlias then
                    ( fields, trackable )

                else
                    analyzeFieldAccessesWithAliases paramAliases lambda.expression ( fields, trackable )

            -- Pipe operators with accessor: param |> .field or .field <| param
            -- Also handles other operators by recursing into both sides
            Expression.OperatorApplication op _ leftExpr rightExpr ->
                case extractPipeAccessorFieldWithAliases op paramAliases leftExpr rightExpr of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable )

                    Nothing ->
                        let
                            ( leftFields, leftTrackable ) =
                                analyzeFieldAccessesWithAliases paramAliases leftExpr ( fields, trackable )
                        in
                        analyzeFieldAccessesWithAliases paramAliases rightExpr ( leftFields, leftTrackable )

            Expression.ParenthesizedExpression inner ->
                analyzeFieldAccessesWithAliases paramAliases inner ( fields, trackable )

            Expression.TupledExpression exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
                    ( fields, trackable )
                    exprs

            Expression.ListExpr exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
                    ( fields, trackable )
                    exprs

            Expression.RecordExpr recordSetters ->
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesWithAliases paramAliases valueExpr acc
                    )
                    ( fields, trackable )
                    recordSetters

            Expression.RecordUpdateExpression (Node _ varName) recordSetters ->
                let
                    ( updateFields, updateTrackable ) =
                        if isParamOrAlias paramAliases varName then
                            ( fields, False )

                        else
                            ( fields, trackable )
                in
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesWithAliases paramAliases valueExpr acc
                    )
                    ( updateFields, updateTrackable )
                    recordSetters

            Expression.Negation inner ->
                analyzeFieldAccessesWithAliases paramAliases inner ( fields, trackable )

            _ ->
                ( fields, trackable )


{-| Extract aliases from let declarations.

A simple alias is a binding like `let d = paramName` where paramName is an existing alias.
Returns the set of new alias names.

-}
extractAliasesFromLetDeclarations : Set String -> List (Node Expression.LetDeclaration) -> Set String
extractAliasesFromLetDeclarations paramAliases declarations =
    declarations
        |> List.filterMap
            (\declNode ->
                case Node.value declNode of
                    Expression.LetFunction letFn ->
                        let
                            fnDecl =
                                Node.value letFn.declaration
                        in
                        -- Only simple bindings with no arguments
                        if List.isEmpty fnDecl.arguments then
                            case Node.value fnDecl.expression of
                                Expression.FunctionOrValue [] varName ->
                                    if isParamOrAlias paramAliases varName then
                                        -- This is an alias: `let newName = existingAlias`
                                        Just (Node.value fnDecl.name)

                                    else
                                        Nothing

                                _ ->
                                    Nothing

                        else
                            Nothing

                    Expression.LetDestructuring _ _ ->
                        -- Destructuring patterns are not simple aliases
                        Nothing
            )
        |> Set.fromList


{-| Extract field name from accessor function application with alias support.
-}
extractAccessorFieldFromApplicationWithAliases : List (Node Expression) -> Set String -> Maybe String
extractAccessorFieldFromApplicationWithAliases exprs paramAliases =
    case exprs of
        [ functionNode, argNode ] ->
            case ( Node.value functionNode, Node.value argNode ) of
                ( Expression.RecordAccessFunction accessorName, Expression.FunctionOrValue [] varName ) ->
                    if isParamOrAlias paramAliases varName then
                        Just (String.dropLeft 1 accessorName)

                    else
                        Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


{-| Extract field name from pipe operator with accessor pattern, with alias support.
-}
extractPipeAccessorFieldWithAliases : String -> Set String -> Node Expression -> Node Expression -> Maybe String
extractPipeAccessorFieldWithAliases op paramAliases leftExpr rightExpr =
    let
        ( varExpr, accessorExpr ) =
            case op of
                "|>" ->
                    ( leftExpr, rightExpr )

                "<|" ->
                    ( rightExpr, leftExpr )

                _ ->
                    ( leftExpr, rightExpr )
    in
    case ( Node.value varExpr, Node.value accessorExpr ) of
        ( Expression.FunctionOrValue [] varName, Expression.RecordAccessFunction accessorName ) ->
            if isParamOrAlias paramAliases varName then
                Just (String.dropLeft 1 accessorName)

            else
                Nothing

        _ ->
            Nothing


{-| Extract variable names from a pattern (for destructuring).
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


{-| Try to extract field names from a record pattern.
Returns Just (Set String) if the pattern is a record pattern (or variation),
Nothing if it's a variable pattern or other untrackable pattern.

Trackable patterns:

  - `{ title, body }` -> Just {"title", "body"}
  - `({ title })` -> Just {"title"} (parenthesized)
  - `{ title } as data` -> Just {"title"} (as pattern wrapping record)
  - `_` -> Just {} (wildcard - no fields used)

Untrackable patterns:

  - `data` -> Nothing (variable captures whole record)
  - `Data title body` -> Nothing (constructor pattern)

-}
extractRecordPatternFields : Node Pattern -> Maybe (Set String)
extractRecordPatternFields node =
    case Node.value node of
        Pattern.RecordPattern fields ->
            Just (fields |> List.map Node.value |> Set.fromList)

        Pattern.ParenthesizedPattern inner ->
            extractRecordPatternFields inner

        Pattern.AsPattern inner _ ->
            -- { title } as data - we can track the record fields
            extractRecordPatternFields inner

        Pattern.AllPattern ->
            -- Wildcard `_` matches but uses no fields
            Just Set.empty

        Pattern.VarPattern _ ->
            -- Variable pattern captures the whole record - can't track
            Nothing

        _ ->
            -- Constructor patterns, tuples, etc. - can't track
            Nothing


{-| Result of extracting fields from case expression patterns.
-}
type CasePatternResult
    = TrackableFields (Set String) -- All patterns were record patterns, these fields are used
    | UntrackablePattern -- At least one pattern captures the whole record (variable, etc.)


{-| Extract fields from all case expression patterns on app.data.

This is the common logic used by both StaticViewTransform and ServerDataTransform
when handling `case app.data of ...` expressions.

Returns:

  - `TrackableFields fields` if all patterns are record patterns (including wildcards)
  - `UntrackablePattern` if any pattern captures the whole record

-}
extractCasePatternFields : List ( Node Pattern, Node expression ) -> CasePatternResult
extractCasePatternFields cases =
    let
        maybeFieldSets =
            cases
                |> List.map (\( pattern, _ ) -> extractRecordPatternFields pattern)

        allTrackable =
            List.all (\m -> m /= Nothing) maybeFieldSets
    in
    if allTrackable then
        let
            allFields =
                maybeFieldSets
                    |> List.filterMap identity
                    |> List.foldl Set.union Set.empty
        in
        TrackableFields allFields

    else
        UntrackablePattern


{-| Result of extracting field access from an expression.

This is a unified type for field tracking that both client and server transforms
can use to handle different expression patterns uniformly.

-}
type FieldAccessResult
    = FieldAccessed String -- A specific field was accessed
    | MarkAllFieldsUsed -- Can't track - mark all fields as client-used (e.g., record update on app.data)
    | NoFieldAccess -- No app.data field access in this expression


{-| Extract field access from an expression.

This unifies the common field tracking logic used by both StaticViewTransform
and ServerDataTransform. It handles:

  - RecordAccess: `app.data.field`
  - OperatorApplication: `app.data |> .field` or `.field <| app.data`
  - Application: `.field app.data`
  - CaseExpression: `case app.data of {...}`
  - RecordUpdateExpression: `{ d | field = value }` where `d = app.data`

Returns a FieldAccessResult indicating what was found.

Note: LetExpression binding extraction is handled separately as it needs to
update context state (appDataBindings), not just report field accesses.

-}
extractFieldAccess : Node Expression -> Maybe String -> Set String -> FieldAccessResult
extractFieldAccess node appParamName appDataBindings =
    case Node.value node of
        -- Field access: app.data.fieldName
        Expression.RecordAccess _ _ ->
            case extractAppDataFieldName node appParamName appDataBindings of
                Just fieldName ->
                    FieldAccessed fieldName

                Nothing ->
                    NoFieldAccess

        -- Pipe operators with accessor: app.data |> .field or .field <| app.data
        Expression.OperatorApplication op _ leftExpr rightExpr ->
            case extractAppDataPipeAccessorField op leftExpr rightExpr appParamName appDataBindings of
                Just fieldName ->
                    FieldAccessed fieldName

                Nothing ->
                    NoFieldAccess

        -- Accessor function application: .field app.data
        Expression.Application [ functionNode, argNode ] ->
            case extractAppDataAccessorApplicationField functionNode argNode appParamName appDataBindings of
                Just fieldName ->
                    FieldAccessed fieldName

                Nothing ->
                    NoFieldAccess

        -- Record update on app.data binding: { d | field = value } where d = app.data
        -- All fields from app.data are used (copied) in the update, so we can't track
        Expression.RecordUpdateExpression (Node _ varName) _ ->
            if Set.member varName appDataBindings then
                MarkAllFieldsUsed

            else
                NoFieldAccess

        _ ->
            NoFieldAccess


{-| Extract a single name from a pattern (for function parameter names).
-}
extractPatternName : Node Pattern -> Maybe String
extractPatternName node =
    case Node.value node of
        Pattern.VarPattern name ->
            Just name

        Pattern.ParenthesizedPattern inner ->
            extractPatternName inner

        Pattern.AsPattern _ (Node _ name) ->
            Just name

        _ ->
            Nothing


{-| Extract field name from pipe operator with accessor pattern.
Handles both `param |> .field` and `.field <| param`.
Returns Just fieldName if the pattern matches with the given paramName.
-}
extractPipeAccessorField : String -> String -> Node Expression -> Node Expression -> Maybe String
extractPipeAccessorField op paramName leftExpr rightExpr =
    let
        ( varExpr, accessorExpr ) =
            case op of
                "|>" ->
                    ( leftExpr, rightExpr )

                "<|" ->
                    ( rightExpr, leftExpr )

                _ ->
                    ( leftExpr, rightExpr )
    in
    case ( Node.value varExpr, Node.value accessorExpr ) of
        ( Expression.FunctionOrValue [] varName, Expression.RecordAccessFunction accessorName ) ->
            if varName == paramName then
                Just (String.dropLeft 1 accessorName)

            else
                Nothing

        _ ->
            Nothing


{-| Extract field name from accessor function application: .field param
Returns Just fieldName if the pattern matches with the given paramName.
-}
extractAccessorFieldFromApplication : List (Node Expression) -> String -> Maybe String
extractAccessorFieldFromApplication exprs paramName =
    case exprs of
        [ functionNode, argNode ] ->
            case ( Node.value functionNode, Node.value argNode ) of
                ( Expression.RecordAccessFunction accessorName, Expression.FunctionOrValue [] varName ) ->
                    if varName == paramName then
                        Just (String.dropLeft 1 accessorName)

                    else
                        Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


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


{-| Find all ranges where "Data" appears as a type in a type annotation.

This is used by both StaticViewTransform (to replace Data with Ephemeral in
freeze-only helper annotations) and ServerDataTransform (to update type
references from Data to Ephemeral).

Returns the ranges of the "Data" type references (unqualified only).

-}
extractDataTypeRanges : Node TypeAnnotation -> List Range
extractDataTypeRanges node =
    case Node.value node of
        TypeAnnotation.Typed (Node range ( [], "Data" )) args ->
            -- Found "Data" type! Return its range, plus check any type args
            range :: List.concatMap extractDataTypeRanges args

        TypeAnnotation.Typed _ args ->
            -- Not Data, but check type arguments
            List.concatMap extractDataTypeRanges args

        TypeAnnotation.FunctionTypeAnnotation left right ->
            extractDataTypeRanges left ++ extractDataTypeRanges right

        TypeAnnotation.Tupled nodes ->
            List.concatMap extractDataTypeRanges nodes

        TypeAnnotation.Record fields ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        extractDataTypeRanges typeNode
                    )

        TypeAnnotation.GenericRecord _ (Node _ fields) ->
            fields
                |> List.concatMap
                    (\(Node _ ( _, typeNode )) ->
                        extractDataTypeRanges typeNode
                    )

        _ ->
            []


{-| Resolve pending helper calls against a dictionary of analyzed helper functions.

Returns (additionalFields, hasUnresolved) where:

  - additionalFields: Set of fields accessed by resolved helpers
  - hasUnresolved: True if any helper call couldn't be resolved (unknown function or untrackable)

Used by both client and server transforms to determine which fields are used when
app.data is passed to helper functions.

-}
resolvePendingHelperCalls : List (Maybe String) -> Dict String HelperAnalysis -> ( Set String, Bool )
resolvePendingHelperCalls pendingCalls helperFunctions =
    pendingCalls
        |> List.foldl
            (\pendingCall ( fields, unresolved ) ->
                case pendingCall of
                    Nothing ->
                        -- Qualified/complex function - can't track
                        ( fields, True )

                    Just funcName ->
                        -- Follow alias chain to get the final analysis
                        case resolveHelperWithAliases funcName helperFunctions Set.empty of
                            Just analysis ->
                                if analysis.isTrackable then
                                    -- Known helper with trackable field usage!
                                    ( Set.union fields analysis.accessedFields, unresolved )

                                else
                                    -- Helper uses param in untrackable ways
                                    ( fields, True )

                            Nothing ->
                                -- Unknown function or cycle detected - can't track
                                ( fields, True )
            )
            ( Set.empty, False )


{-| Resolve a helper function, following alias chains to find the actual implementation.

Takes a set of already-visited function names to detect cycles.
Returns Nothing if the function is unknown or if a cycle is detected.

-}
resolveHelperWithAliases : String -> Dict String HelperAnalysis -> Set String -> Maybe HelperAnalysis
resolveHelperWithAliases funcName helperFunctions visited =
    if Set.member funcName visited then
        -- Cycle detected - bail out
        Nothing

    else
        case Dict.get funcName helperFunctions of
            Just analysis ->
                case analysis.aliasTarget of
                    Just targetName ->
                        -- This is an alias, follow the chain
                        resolveHelperWithAliases targetName helperFunctions (Set.insert funcName visited)

                    Nothing ->
                        -- Not an alias, return the analysis
                        Just analysis

            Nothing ->
                -- Unknown function
                Nothing


{-| Extract all field names from a list of field definitions.

This is a common operation in both transforms when computing which fields
are ephemeral vs persistent.

-}
extractFieldNames : List ( String, a ) -> Set String
extractFieldNames fields =
    fields
        |> List.map Tuple.first
        |> Set.fromList


{-| Compute which fields are ephemeral given:

  - allFieldNames: All field names from the Data type
  - clientUsedFields: Fields directly accessed in client contexts
  - pendingHelperCalls: Helper calls to resolve
  - helperFunctions: Dictionary of analyzed helper functions

Returns (ephemeralFields, hasUnresolvedCalls) where:

  - ephemeralFields: Fields that can be removed from the client Data type
  - hasUnresolvedCalls: True if we had to bail out (mark all fields as persistent)

This encapsulates the core ephemeral/persistent field computation logic used
by both StaticViewTransform and ServerDataTransform.

-}
computeEphemeralFields :
    Set String
    -> Set String
    -> List (Maybe String)
    -> Dict String HelperAnalysis
    -> ( Set String, Bool )
computeEphemeralFields allFieldNames clientUsedFields pendingHelperCalls helperFunctions =
    let
        -- Resolve pending helper calls against the helper functions dict
        ( resolvedHelperFields, unresolvedHelperCalls ) =
            resolvePendingHelperCalls pendingHelperCalls helperFunctions

        -- Combine direct field accesses with helper-resolved fields
        effectiveClientUsedFields =
            if unresolvedHelperCalls then
                -- Can't track, so assume ALL fields are client-used (safe fallback)
                allFieldNames

            else
                Set.union clientUsedFields resolvedHelperFields

        -- Ephemeral fields: all fields that are NOT used in client contexts
        ephemeralFields =
            allFieldNames
                |> Set.filter (\f -> not (Set.member f effectiveClientUsedFields))
    in
    ( ephemeralFields, unresolvedHelperCalls )


{-| Check if a function node is a call to View.freeze.
Uses the ModuleNameLookupTable to handle all import styles:

  - `View.freeze` (qualified)
  - `freeze` (if imported directly with `exposing (freeze)`)
  - `V.freeze` (if imported with alias `as V`)

-}
isViewFreezeCall : Node Expression -> ModuleNameLookupTable -> Bool
isViewFreezeCall functionNode lookupTable =
    case Node.value functionNode of
        Expression.FunctionOrValue _ "freeze" ->
            ModuleNameLookupTable.moduleNameFor lookupTable functionNode == Just [ "View" ]

        _ ->
            False


{-| Check if an expression node represents exiting a View.freeze call.

This is used by expressionExitVisitor in both StaticViewTransform and
ServerDataTransform to reset the inFreezeCall flag when exiting a freeze call.

Returns True if the expression is `View.freeze <arg>` (an Application with freeze).

-}
isExitingFreezeCall : Node Expression -> ModuleNameLookupTable -> Bool
isExitingFreezeCall node lookupTable =
    case Node.value node of
        Expression.Application (functionNode :: _) ->
            isViewFreezeCall functionNode lookupTable

        _ ->
            False


{-| Extract app.data bindings from let declarations.

This handles the common pattern of extracting variable bindings to app.data:
- `let d = app.data` → adds "d" to bindings
- `let { title, body } = app.data` → adds "title", "body" to bindings

Both StaticViewTransform and ServerDataTransform need this logic.
Returns the new set of app.data bindings (union of existing + new).

-}
extractAppDataBindingsFromLet :
    List (Node Expression.LetDeclaration)
    -> Maybe String
    -> Set String
    -> (Node Expression -> Bool)
    -> Set String
extractAppDataBindingsFromLet declarations appParamName existingBindings isAppData =
    declarations
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
                                -- No arguments - could be binding app.data
                                if isAppData fnDecl.expression then
                                    Set.insert (Node.value fnDecl.name) acc

                                else
                                    acc

                            _ ->
                                acc

                    Expression.LetDestructuring pattern expr ->
                        if isAppData expr then
                            extractPatternNames pattern
                                |> Set.union acc

                        else
                            acc
            )
            existingBindings


{-| Extract the field name being accessed from app.data.

Handles both direct access (`app.data.field`) and nested access (`app.data.nested.field`).
For nested access, returns the top-level field name (e.g., "nested" for `app.data.nested.field`).

Returns Just fieldName if the expression is a field access on app.data, Nothing otherwise.

-}
extractAppDataFieldName : Node Expression -> Maybe String -> Set String -> Maybe String
extractAppDataFieldName node appParamName appDataBindings =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ fieldName) ->
            if isAppDataAccess innerExpr appParamName appDataBindings then
                -- Direct app.data.field access
                Just fieldName

            else
                -- Check for nested access like app.data.something.field
                case Node.value innerExpr of
                    Expression.RecordAccess innerInner (Node _ topLevelField) ->
                        if isAppDataAccess innerInner appParamName appDataBindings then
                            Just topLevelField

                        else
                            Nothing

                    _ ->
                        Nothing

        _ ->
            Nothing


{-| Check if an expression is `app.data` (or `static.data`, etc. based on appParamName)
or a variable bound to app.data.

Takes the app parameter name (e.g., Just "app") and the set of variables bound to app.data.

-}
isAppDataAccess : Node Expression -> Maybe String -> Set String -> Bool
isAppDataAccess node appParamName appDataBindings =
    case Node.value node of
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    appParamName == Just varName

                _ ->
                    False

        Expression.FunctionOrValue [] varName ->
            Set.member varName appDataBindings

        _ ->
            False


{-| Extract field name from pipe operator with accessor pattern on app.data.
Handles `app.data |> .field` and `.field <| app.data`.
Returns Just fieldName if the pattern matches.
-}
extractAppDataPipeAccessorField : String -> Node Expression -> Node Expression -> Maybe String -> Set String -> Maybe String
extractAppDataPipeAccessorField op leftExpr rightExpr appParamName appDataBindings =
    let
        ( dataExpr, accessorExpr ) =
            case op of
                "|>" ->
                    ( leftExpr, rightExpr )

                "<|" ->
                    ( rightExpr, leftExpr )

                _ ->
                    ( leftExpr, rightExpr )
    in
    if isAppDataAccess dataExpr appParamName appDataBindings then
        case Node.value accessorExpr of
            Expression.RecordAccessFunction accessorName ->
                Just (String.dropLeft 1 accessorName)

            _ ->
                Nothing

    else
        Nothing


{-| Extract field name from accessor function application pattern: `.field app.data`

Handles the common pattern where a record accessor function is applied to app.data.
This is semantically equivalent to `app.data |> .field`.

Returns Just fieldName if the expression is a single-argument application where:

  - The function is a RecordAccessFunction (e.g., `.field`)
  - The argument is `app.data` or a variable bound to app.data

-}
extractAppDataAccessorApplicationField : Node Expression -> Node Expression -> Maybe String -> Set String -> Maybe String
extractAppDataAccessorApplicationField functionNode argNode appParamName appDataBindings =
    case Node.value functionNode of
        Expression.RecordAccessFunction accessorName ->
            if isAppDataAccess argNode appParamName appDataBindings then
                Just (String.dropLeft 1 accessorName)

            else
                Nothing

        _ ->
            Nothing


{-| Result of classifying function arguments for app.data usage.
-}
type alias AppDataClassification =
    { hasDirectAppData : Bool -- app.data passed directly as argument
    , hasWrappedAppData : Bool -- app.data wrapped in list/tuple/etc.
    , isAccessorApplication : Bool -- .field app.data pattern (handled by trackFieldAccess)
    , maybeFuncName : Maybe String -- local function name if applicable
    }


{-| Classify function arguments for app.data usage patterns.

This extracts the common logic from checkAppDataPassedToHelper that both
StaticViewTransform and ServerDataTransform need.

Arguments:

  - functionNode: The function being called
  - args: The arguments to the function
  - appParamName: The app parameter name (e.g., Just "app")
  - appDataBindings: Set of variables bound to app.data
  - isFreezeCall: Callback to check if an expression is a View.freeze call
  - containsAppData: Callback to recursively check for app.data (allows context-specific logic)

-}
classifyAppDataArguments :
    Node Expression
    -> List (Node Expression)
    -> Maybe String
    -> Set String
    -> (Node Expression -> Bool)
    -> (Node Expression -> Bool)
    -> AppDataClassification
classifyAppDataArguments functionNode args appParamName appDataBindings isFreezeCall containsAppData =
    let
        -- Check for DIRECT app.data arguments (can potentially use helper analysis)
        -- vs WRAPPED app.data arguments (list, tuple, etc. - can't track)
        ( directAppDataArgs, wrappedAppDataArgs ) =
            args
                |> List.foldl
                    (\arg ( direct, wrapped ) ->
                        case Node.value arg of
                            -- Check if this is app.data directly (not app.data.field)
                            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                                if fieldName == "data" && isAppDataAccess arg appParamName appDataBindings then
                                    -- This IS app.data passed directly - potentially trackable
                                    ( arg :: direct, wrapped )

                                else if isAppDataAccess innerExpr appParamName appDataBindings then
                                    -- This is app.data.field - trackable via normal field tracking, skip
                                    ( direct, wrapped )

                                else if containsAppData innerExpr then
                                    -- app.data is nested inside - untrackable
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )

                            -- If the arg is a function call that contains app.data,
                            -- we can't track which fields are used - untrackable
                            Expression.Application innerArgs ->
                                if List.any containsAppData innerArgs then
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )

                            -- Variable bound to app.data passed directly
                            Expression.FunctionOrValue [] varName ->
                                if Set.member varName appDataBindings then
                                    ( arg :: direct, wrapped )

                                else
                                    ( direct, wrapped )

                            -- Lists, tuples, etc. containing app.data - untrackable
                            _ ->
                                if containsAppData arg then
                                    ( direct, arg :: wrapped )

                                else
                                    ( direct, wrapped )
                    )
                    ( [], [] )

        hasDirectAppData =
            not (List.isEmpty directAppDataArgs)

        hasWrappedAppData =
            not (List.isEmpty wrappedAppDataArgs)

        -- Check if this is a record accessor function application: .field app.data
        -- This is handled by trackFieldAccess, so we don't need to process it here
        isAccessorApplication =
            case Node.value functionNode of
                Expression.RecordAccessFunction _ ->
                    -- Single arg and it's app.data - this is .field app.data
                    -- which is tracked by trackFieldAccess, so skip here
                    List.length args == 1 && hasDirectAppData

                _ ->
                    False

        -- Extract function name if it's a local function
        maybeFuncName =
            case Node.value functionNode of
                Expression.FunctionOrValue [] funcName ->
                    Just funcName

                _ ->
                    Nothing
    in
    { hasDirectAppData = hasDirectAppData
    , hasWrappedAppData = hasWrappedAppData
    , isAccessorApplication = isAccessorApplication
    , maybeFuncName = maybeFuncName
    }


{-| Check if an expression contains app.data being passed as a WHOLE to a function.

This returns True ONLY for `app.data` itself, NOT for field accesses like `app.data.field`.
The reason: if someone writes `someFunction app.data.field`, we CAN track that field access.
But if they write `someFunction app.data`, we CANNOT know which fields that function uses.

Examples:

  - `app.data` → True (app.data passed as whole)
  - `app.data.title` → False (field access, we can track "title")
  - `someFunction app.data` → True (app.data passed to function)
  - `someFunction app.data.title` → False (just passing the value of title field)

Arguments:

  - node: The expression to check
  - appParamName: The app parameter name (e.g., Just "app")
  - appDataBindings: Set of variables bound to app.data
  - isFreezeCall: Callback to check if an expression is a View.freeze call

-}
containsAppDataExpression : Node Expression -> Maybe String -> Set String -> (Node Expression -> Bool) -> Bool
containsAppDataExpression node appParamName appDataBindings isFreezeCall =
    containsAppDataExpressionHelp node appParamName appDataBindings isFreezeCall


containsAppDataExpressionHelp : Node Expression -> Maybe String -> Set String -> (Node Expression -> Bool) -> Bool
containsAppDataExpressionHelp node appParamName appDataBindings isFreezeCall =
    case Node.value node of
        -- app.data exactly (with field "data" on the app param)
        Expression.RecordAccess innerExpr (Node _ "data") ->
            case Node.value innerExpr of
                Expression.FunctionOrValue [] varName ->
                    -- Check if varName matches the App parameter name (e.g., "app", "static")
                    if appParamName == Just varName then
                        -- This IS app.data being used as a whole
                        True

                    else
                        -- Something else with .data field, recurse
                        containsAppDataExpressionHelp innerExpr appParamName appDataBindings isFreezeCall

                _ ->
                    -- Something else with .data field, recurse
                    containsAppDataExpressionHelp innerExpr appParamName appDataBindings isFreezeCall

        -- app.data.field - accessing a field OF app.data is fine, we can track that
        -- The field access is already tracked by trackFieldAccess
        Expression.RecordAccess _ _ ->
            -- Don't recurse here - we don't care if app.data is deep inside a field access chain
            -- because accessing app.data.foo.bar still tracks "foo" as the accessed field
            False

        Expression.FunctionOrValue [] varName ->
            -- Check if this variable is bound to app.data
            Set.member varName appDataBindings

        Expression.Application ((functionNode :: _) as exprs) ->
            -- Check if this is a View.freeze call
            -- View.freeze calls are ephemeral context - don't worry about app.data inside them
            if isFreezeCall functionNode then
                False

            else
                List.any (\e -> containsAppDataExpressionHelp e appParamName appDataBindings isFreezeCall) exprs

        Expression.ParenthesizedExpression inner ->
            containsAppDataExpressionHelp inner appParamName appDataBindings isFreezeCall

        Expression.TupledExpression exprs ->
            List.any (\e -> containsAppDataExpressionHelp e appParamName appDataBindings isFreezeCall) exprs

        Expression.ListExpr exprs ->
            List.any (\e -> containsAppDataExpressionHelp e appParamName appDataBindings isFreezeCall) exprs

        Expression.IfBlock cond then_ else_ ->
            containsAppDataExpressionHelp cond appParamName appDataBindings isFreezeCall
                || containsAppDataExpressionHelp then_ appParamName appDataBindings isFreezeCall
                || containsAppDataExpressionHelp else_ appParamName appDataBindings isFreezeCall

        Expression.CaseExpression caseBlock ->
            containsAppDataExpressionHelp caseBlock.expression appParamName appDataBindings isFreezeCall
                || List.any (\( _, expr ) -> containsAppDataExpressionHelp expr appParamName appDataBindings isFreezeCall) caseBlock.cases

        Expression.LambdaExpression lambda ->
            containsAppDataExpressionHelp lambda.expression appParamName appDataBindings isFreezeCall

        Expression.LetExpression letBlock ->
            containsAppDataExpressionHelp letBlock.expression appParamName appDataBindings isFreezeCall

        Expression.OperatorApplication _ _ left right ->
            containsAppDataExpressionHelp left appParamName appDataBindings isFreezeCall
                || containsAppDataExpressionHelp right appParamName appDataBindings isFreezeCall

        -- Record update: { varName | field = value }
        -- In Elm, record update uses a variable name, not an expression.
        -- If the variable is bound to app.data (via let d = app.data),
        -- then we're using app.data as a whole.
        Expression.RecordUpdateExpression (Node _ varName) _ ->
            Set.member varName appDataBindings

        _ ->
            False


{-| Actions to take for pending helper call tracking.

Used by both client and server transforms to determine what to do with
the pendingHelperCalls list based on the AppDataClassification.

-}
type PendingHelperAction
    = AddKnownHelper String -- Local function with known name
    | AddUnknownHelper -- Untrackable (wrapped or unknown function)
    | NoHelperAction -- Skip (accessor application or no app.data involved)


{-| Determine what action to take for pending helper calls based on classification.

This extracts the common client-context logic from checkAppDataPassedToHelper
that both StaticViewTransform and ServerDataTransform use.

Returns a PendingHelperAction that the transform can apply to its context.

-}
determinePendingHelperAction : AppDataClassification -> PendingHelperAction
determinePendingHelperAction classification =
    -- Skip if this is an accessor function application like .field app.data
    -- which is already handled by trackFieldAccess
    if classification.isAccessorApplication then
        NoHelperAction

    else if classification.hasWrappedAppData then
        -- app.data is wrapped in list/tuple/etc. - can't track, bail out
        AddUnknownHelper

    else if classification.hasDirectAppData then
        -- app.data passed directly - may be able to track via helper analysis
        case classification.maybeFuncName of
            Just funcName ->
                -- Local function - store name for lookup in finalEvaluation
                AddKnownHelper funcName

            Nothing ->
                -- Qualified or complex function expression - can't look up
                AddUnknownHelper

    else
        NoHelperAction
