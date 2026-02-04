module Pages.Review.PersistentFieldTracking exposing
    ( AppDataClassification
    , CaseOnAppDataResult(..)
    , CasePatternResult(..)
    , FieldAccessResult(..)
    , HelperAnalysis
    , HelperCallResult(..)
    , InlineLambdaResult(..)
    , PendingHelperAction(..)
    , PendingHelperCall
    , SharedFieldTrackingState
    , analyzeCaseOnAppData
    , analyzeFieldAccessesOnParam
    , analyzeHelperCallInClientContext
    , analyzeHelperFunction
    , analyzeInlineLambda
    , analyzePipedHelperCall
    , applyHelperCallResult
    , classifyAppDataArguments
    , computeEphemeralFields
    , computeEphemeralFieldsWithCorrection
    , containsAppDataExpression
    , determinePendingHelperAction
    , emptySharedState
    , extractAppDataAccessorApplicationField
    , extractAppDataFieldName
    , extractAppDataBindingsFromLet
    , extractCasePatternFields
    , extractCaseVariablePatternBindings
    , extractDataTypeRanges
    , extractFieldAccess
    , extractFieldNames
    , extractLetBoundHelperFunctions
    , extractPatternName
    , extractPatternNames
    , extractRecordPatternFields
    , extractPipeAccessorField
    , extractAccessorFieldFromApplication
    , extractAppDataPipeAccessorField
    , isAppDataAccess
    , isExitingFreezeCall
    , isRecordAccessFunction
    , isRouteModule
    , isViewFreezeCall
    , markAllFieldsAsPersistent
    , resolvePendingHelperCalls
    , trackFieldAccessShared
    , typeAnnotationToString
    , updateOnFieldAccess
    , updateOnFreezeEnter
    , updateOnFreezeExit
    , updateOnHeadEnter
    , updateOnHeadExit
    , updateOnHelperCall
    )

{-| Shared utilities for persistent field tracking in elm-review rules.

Both StaticViewTransform (client) and ServerDataTransform (server) need to agree
on which fields are ephemeral. This module provides the shared analysis functions
to ensure consistency.

@docs AppDataClassification
@docs CaseOnAppDataResult, CasePatternResult
@docs FieldAccessResult
@docs HelperAnalysis
@docs analyzeCaseOnAppData, analyzeHelperFunction
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
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on a parameter.
-}
type alias HelperAnalysis =
    { paramIndex : Int -- Which parameter position (0-indexed)
    , paramName : String -- Parameter name
    , accessedFields : Set String -- Fields accessed on this param (e.g., param.field)
    , isTrackable : Bool -- False if param is used in ways we can't track
    , aliasTarget : Maybe String -- If this is an alias to another function (e.g., myRender = renderContent)
    , delegations : List HelperDelegation -- Functions this helper delegates to with the param (e.g., innerHelper data)
    }


{-| A delegation to another helper function with the parameter.
This tracks patterns like `wrapperHelper data = innerHelper data`.
-}
type alias HelperDelegation =
    { funcName : String
    , argIndex : Int
    }


{-| Shared state for field tracking that both transforms embed.

This type contains the common fields needed for persistent field tracking:

  - `clientUsedFields`: Fields accessed in CLIENT contexts (outside freeze/head).
    These MUST be kept in the Data type for wire transmission.
  - `inFreezeCall`: True when inside a View.freeze call (ephemeral context)
  - `inHeadFunction`: True when inside the head function (ephemeral context)
  - `appDataBindings`: Variables bound to app.data (e.g., via `let d = app.data`)
  - `appParamName`: The parameter name from view/init/update function (e.g., "app")
  - `helperFunctions`: Analyzed helper functions and their field usage
  - `pendingHelperCalls`: Helper calls to resolve in finalEvaluation
  - `dataTypeFields`: Fields from the Data type definition
  - `markAllFieldsAsUsed`: Safe fallback flag when tracking is impossible

Both StaticViewTransform and ServerDataTransform embed this state and use the
shared update functions to ensure identical ephemeral field computation.

-}
type alias SharedFieldTrackingState =
    { clientUsedFields : Set String
    , inFreezeCall : Bool
    , inHeadFunction : Bool
    , appDataBindings : Set String
    , appParamName : Maybe String
    , helperFunctions : Dict String (List HelperAnalysis)
    , pendingHelperCalls : List (Maybe PendingHelperCall)
    , dataTypeFields : List ( String, Node TypeAnnotation )
    , markAllFieldsAsUsed : Bool
    }


{-| Create an empty SharedFieldTrackingState with default values.
-}
emptySharedState : SharedFieldTrackingState
emptySharedState =
    { clientUsedFields = Set.empty
    , inFreezeCall = False
    , inHeadFunction = False
    , appDataBindings = Set.empty
    , appParamName = Nothing
    , helperFunctions = Dict.empty
    , pendingHelperCalls = []
    , dataTypeFields = []
    , markAllFieldsAsUsed = False
    }


{-| Update state when a field is accessed on app.data.

In CLIENT context (not in freeze or head): adds field to clientUsedFields.
In EPHEMERAL context (in freeze or head): no change (field can be removed).

-}
updateOnFieldAccess : String -> SharedFieldTrackingState -> SharedFieldTrackingState
updateOnFieldAccess fieldName state =
    if state.inFreezeCall || state.inHeadFunction then
        -- In ephemeral context - don't track (field can potentially be removed)
        state

    else
        -- In client context - field MUST be kept
        { state | clientUsedFields = Set.insert fieldName state.clientUsedFields }


{-| Update state when entering a View.freeze call.
-}
updateOnFreezeEnter : SharedFieldTrackingState -> SharedFieldTrackingState
updateOnFreezeEnter state =
    { state | inFreezeCall = True }


{-| Update state when exiting a View.freeze call.
-}
updateOnFreezeExit : SharedFieldTrackingState -> SharedFieldTrackingState
updateOnFreezeExit state =
    { state | inFreezeCall = False }


{-| Update state when entering the head function.
-}
updateOnHeadEnter : SharedFieldTrackingState -> SharedFieldTrackingState
updateOnHeadEnter state =
    { state | inHeadFunction = True }


{-| Update state when exiting the head function.
-}
updateOnHeadExit : SharedFieldTrackingState -> SharedFieldTrackingState
updateOnHeadExit state =
    { state | inHeadFunction = False }


{-| Update state when a helper is called with app.data.

Takes a HelperCallResult and applies it to the shared state.
Both checkAppDataPassedToHelper and checkAppDataPassedToHelperViaPipe use this.

-}
updateOnHelperCall : HelperCallResult -> SharedFieldTrackingState -> SharedFieldTrackingState
updateOnHelperCall result state =
    case result of
        HelperCallKnown helperCall ->
            { state | pendingHelperCalls = Just helperCall :: state.pendingHelperCalls }

        HelperCallLambdaFields accessedFields ->
            Set.foldl updateOnFieldAccess state accessedFields

        HelperCallUntrackable ->
            { state | pendingHelperCalls = Nothing :: state.pendingHelperCalls }

        HelperCallNoAction ->
            state


{-| Apply a HelperCallResult to the shared state.

This is an alias for updateOnHelperCall for clearer API.
Interprets the shared analysis result and updates the state accordingly.

-}
applyHelperCallResult : HelperCallResult -> SharedFieldTrackingState -> SharedFieldTrackingState
applyHelperCallResult =
    updateOnHelperCall


{-| Track field access on app.data using shared state.

This function consolidates the common field tracking logic from both
StaticViewTransform and ServerDataTransform. It handles:

  - RecordAccess: `app.data.field`
  - OperatorApplication: `app.data |> .field` or `.field <| app.data`
  - Application: `.field app.data`
  - RecordUpdateExpression: `{ d | field = value }` where `d = app.data`
  - LetExpression: extracts app.data bindings and let-bound helper functions
  - CaseExpression: handles `case app.data of ...` patterns

Returns an updated SharedFieldTrackingState.

-}
trackFieldAccessShared : Node Expression -> SharedFieldTrackingState -> ModuleNameLookupTable -> SharedFieldTrackingState
trackFieldAccessShared node state lookupTable =
    -- Use shared extractFieldAccess for common patterns
    case extractFieldAccess node state.appParamName state.appDataBindings of
        FieldAccessed fieldName ->
            updateOnFieldAccess fieldName state

        MarkAllFieldsUsed ->
            if state.inFreezeCall || state.inHeadFunction then
                -- In ephemeral context, we don't care
                state

            else
                markAllFieldsAsPersistent state

        NoFieldAccess ->
            -- Handle patterns that need context-specific logic
            case Node.value node of
                -- Case expression on app.data: use shared analysis
                Expression.CaseExpression _ ->
                    if state.inFreezeCall || state.inHeadFunction then
                        -- In ephemeral context, we don't care
                        state

                    else
                        -- Use unified case analysis from shared module
                        case analyzeCaseOnAppData node state.appParamName state.appDataBindings of
                            CaseTrackedFields fields ->
                                Set.foldl updateOnFieldAccess state fields

                            CaseAddBindings bindings ->
                                { state | appDataBindings = Set.union state.appDataBindings bindings }

                            CaseMarkAllFieldsUsed ->
                                markAllFieldsAsPersistent state

                            CaseNotOnAppData ->
                                state

                -- Let expressions can bind app.data to a variable
                -- They can also define local helper functions that should be analyzed
                Expression.LetExpression letBlock ->
                    let
                        -- Extract app.data bindings (let d = app.data)
                        newBindings =
                            extractAppDataBindingsFromLet
                                letBlock.declarations
                                state.appParamName
                                state.appDataBindings
                                (\expr -> isAppDataAccess expr state.appParamName state.appDataBindings)

                        -- Extract let-bound helper functions using shared logic
                        newHelperFunctions =
                            extractLetBoundHelperFunctions
                                letBlock.declarations
                                state.helperFunctions
                    in
                    { state
                        | appDataBindings = newBindings
                        , helperFunctions = newHelperFunctions
                    }

                _ ->
                    state


{-| Mark all fields as persistent (safe fallback when we can't track field usage).
-}
markAllFieldsAsPersistent : SharedFieldTrackingState -> SharedFieldTrackingState
markAllFieldsAsPersistent state =
    { state | markAllFieldsAsUsed = True }


{-| Analyze a helper function to determine which fields it accesses on each parameter.

This enables tracking field usage when app.data is passed to a helper function,
including when app.data is passed in any parameter position (not just the first).

Also handles record destructuring patterns like `renderContent { title, body } = ...`
where we know EXACTLY which fields are used.

Also detects function aliases like `myRender = renderContent` where the function
has no parameters and its body is just a reference to another function.

Returns a list of analyses, one per trackable parameter.

-}
analyzeHelperFunction : Expression.Function -> List HelperAnalysis
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
        [] ->
            -- No parameters - check if this is a function alias like `myRender = renderContent`
            case extractSimpleFunctionReference body of
                Just targetFuncName ->
                    -- This is an alias to another function
                    [ { paramIndex = 0
                      , paramName = "_alias_"
                      , accessedFields = Set.empty
                      , isTrackable = True
                      , aliasTarget = Just targetFuncName
                      , delegations = []
                      }
                    ]

                Nothing ->
                    -- Not a simple function reference, can't track
                    []

        _ ->
            -- Analyze each parameter
            arguments
                |> List.indexedMap
                    (\index arg ->
                        analyzeParameter index arg body
                    )
                |> List.filterMap identity


{-| Analyze a single parameter of a helper function.
-}
analyzeParameter : Int -> Node Pattern -> Node Expression -> Maybe HelperAnalysis
analyzeParameter index arg body =
    case extractPatternName arg of
        Just paramName ->
            -- Regular variable pattern: analyze body for field accesses
            let
                ( accessedFields, isTrackable, delegations ) =
                    analyzeFieldAccessesOnParam paramName body
            in
            Just
                { paramIndex = index
                , paramName = paramName
                , accessedFields = accessedFields
                , isTrackable = isTrackable
                , aliasTarget = Nothing
                , delegations = delegations
                }

        Nothing ->
            -- Param is a pattern - check if it's a record pattern
            case extractRecordPatternFields arg of
                Just fields ->
                    -- Record pattern like { title, body }
                    -- We know EXACTLY which fields are accessed - no body analysis needed!
                    Just
                        { paramIndex = index
                        , paramName = "_record_pattern_"
                        , accessedFields = fields
                        , isTrackable = True
                        , aliasTarget = Nothing
                        , delegations = []
                        }

                Nothing ->
                    -- Other pattern (tuple, constructor, etc.) - can't track safely
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


{-| Result of analyzing an inline lambda for field accesses.
-}
type InlineLambdaResult
    = LambdaTrackable (Set String) -- Lambda is trackable, here are the fields accessed
    | LambdaUntrackable -- Lambda uses parameter in untrackable ways
    | NotALambda -- Expression is not a lambda


{-| Analyze an inline lambda expression for field accesses on a specific parameter.

When app.data is passed to an inline lambda like `(\d -> d.title) app.data`,
this function analyzes the lambda to determine which fields are accessed.

The argIndex indicates which argument of the lambda receives app.data (0-indexed).

-}
analyzeInlineLambda : Node Expression -> Int -> InlineLambdaResult
analyzeInlineLambda funcExpr argIndex =
    case Node.value funcExpr of
        Expression.LambdaExpression lambda ->
            case List.drop argIndex lambda.args of
                paramPattern :: _ ->
                    -- Found the parameter at the given index
                    case extractPatternName paramPattern of
                        Just paramName ->
                            -- Regular variable pattern: analyze body for field accesses
                            let
                                ( accessedFields, isTrackable, delegations ) =
                                    analyzeFieldAccessesOnParam paramName lambda.expression
                            in
                            -- For inline lambdas, we can't resolve delegations (no helper context)
                            -- So if there are delegations, treat as untrackable
                            if isTrackable && List.isEmpty delegations then
                                LambdaTrackable accessedFields

                            else
                                LambdaUntrackable

                        Nothing ->
                            -- Check for record pattern like { title, body }
                            case extractRecordPatternFields paramPattern of
                                Just fields ->
                                    -- Record pattern - we know exactly which fields are used
                                    LambdaTrackable fields

                                Nothing ->
                                    -- Other pattern (tuple, constructor, etc.) - can't track
                                    LambdaUntrackable

                [] ->
                    -- Lambda doesn't have enough parameters for the given index
                    LambdaUntrackable

        Expression.ParenthesizedExpression inner ->
            -- Handle parenthesized lambdas: ((\d -> d.title))
            analyzeInlineLambda inner argIndex

        _ ->
            NotALambda


{-| Analyze an expression to find all field accesses on a given parameter name.

Returns (accessedFields, isTrackable, delegations) where:

  - accessedFields: Set of field names accessed like `param.fieldName`
  - isTrackable: False if the parameter is used in ways we can't track
    (passed to a qualified/unknown function, wrapped in a data structure, etc.)
  - delegations: List of local helper functions the parameter is delegated to
    (e.g., `innerHelper data` results in a delegation to "innerHelper")

-}
analyzeFieldAccessesOnParam : String -> Node Expression -> ( Set String, Bool, List HelperDelegation )
analyzeFieldAccessesOnParam paramName expr =
    -- Start with just the parameter name as the only "alias" we track
    analyzeFieldAccessesWithAliases (Set.singleton paramName) expr ( Set.empty, True, [] )


{-| Check if a variable name is the parameter or an alias of the parameter.
-}
isParamOrAlias : Set String -> String -> Bool
isParamOrAlias paramAliases varName =
    Set.member varName paramAliases


{-| Analyze field accesses with support for let-bound aliases of the parameter.

The paramAliases set contains the original parameter name and any variables
that are simple aliases (e.g., `let d = data in ...`).

The third element of the accumulator and return value is a list of delegations -
local functions the parameter is passed to (e.g., `innerHelper data`).

-}
analyzeFieldAccessesWithAliases : Set String -> Node Expression -> ( Set String, Bool, List HelperDelegation ) -> ( Set String, Bool, List HelperDelegation )
analyzeFieldAccessesWithAliases paramAliases node ( fields, trackable, delegations ) =
    if not trackable then
        ( fields, False, delegations )

    else
        case Node.value node of
            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                case Node.value innerExpr of
                    Expression.FunctionOrValue [] varName ->
                        if isParamOrAlias paramAliases varName then
                            ( Set.insert fieldName fields, trackable, delegations )

                        else
                            ( fields, trackable, delegations )

                    _ ->
                        analyzeFieldAccessesWithAliases paramAliases innerExpr ( fields, trackable, delegations )

            Expression.FunctionOrValue [] varName ->
                if isParamOrAlias paramAliases varName then
                    -- Bare usage of param or alias - can't track
                    ( fields, False, delegations )

                else
                    ( fields, trackable, delegations )

            -- Function application - check for accessor function pattern .field param
            -- Also check for delegation pattern: localHelper param
            Expression.Application exprs ->
                case extractAccessorFieldFromApplicationWithAliases exprs paramAliases of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable, delegations )

                    Nothing ->
                        -- Check if this is a delegation to a local helper
                        case extractHelperDelegation exprs paramAliases of
                            Just delegation ->
                                -- Found a delegation like `innerHelper data` - record it
                                ( fields, trackable, delegation :: delegations )

                            Nothing ->
                                -- Not a simple delegation - analyze all expressions
                                -- But check if param is passed in untrackable ways
                                analyzeApplicationExprs paramAliases exprs ( fields, trackable, delegations )

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
                    ( declFields, declTrackable, declDelegations ) =
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
                            ( fields, trackable, delegations )
                            letBlock.declarations
                in
                analyzeFieldAccessesWithAliases allAliases letBlock.expression ( declFields, declTrackable, declDelegations )

            Expression.IfBlock cond then_ else_ ->
                let
                    ( condFields, condTrackable, condDelegations ) =
                        analyzeFieldAccessesWithAliases paramAliases cond ( fields, trackable, delegations )

                    ( thenFields, thenTrackable, thenDelegations ) =
                        analyzeFieldAccessesWithAliases paramAliases then_ ( condFields, condTrackable, condDelegations )
                in
                analyzeFieldAccessesWithAliases paramAliases else_ ( thenFields, thenTrackable, thenDelegations )

            Expression.CaseExpression caseBlock ->
                let
                    caseOnParamOrAlias =
                        case Node.value caseBlock.expression of
                            Expression.FunctionOrValue [] varName ->
                                isParamOrAlias paramAliases varName

                            _ ->
                                False

                    ( exprFields, exprTrackable, exprDelegations ) =
                        if caseOnParamOrAlias then
                            -- Case is on the parameter - check if all patterns are record patterns
                            case extractCasePatternFields caseBlock.cases of
                                TrackableFields patternFields ->
                                    -- All patterns are record patterns, we can track the specific fields
                                    ( Set.union fields patternFields, trackable, delegations )

                                UntrackablePattern ->
                                    -- At least one pattern captures the whole record
                                    -- But we can still track field accesses on variable bindings!
                                    -- Will be handled in case body analysis below
                                    ( fields, trackable, delegations )

                        else
                            analyzeFieldAccessesWithAliases paramAliases caseBlock.expression ( fields, trackable, delegations )
                in
                List.foldl
                    (\( patternNode, caseExpr ) acc ->
                        -- If the case is on a param/alias and the pattern is a variable,
                        -- add that variable as an alias for analyzing the case body
                        let
                            branchAliases =
                                if caseOnParamOrAlias then
                                    case extractPatternName patternNode of
                                        Just varName ->
                                            -- Variable pattern like `d` - treat as alias for the param
                                            Set.insert varName paramAliases

                                        Nothing ->
                                            -- Record pattern or other - no new alias, but that's fine
                                            -- (record patterns are already handled by extractCasePatternFields)
                                            paramAliases

                                else
                                    paramAliases
                        in
                        analyzeFieldAccessesWithAliases branchAliases caseExpr acc
                    )
                    ( exprFields, exprTrackable, exprDelegations )
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
                    ( fields, trackable, delegations )

                else
                    analyzeFieldAccessesWithAliases paramAliases lambda.expression ( fields, trackable, delegations )

            -- Pipe operators with accessor: param |> .field or .field <| param
            -- Also handles other operators by recursing into both sides
            Expression.OperatorApplication op _ leftExpr rightExpr ->
                case extractPipeAccessorFieldWithAliases op paramAliases leftExpr rightExpr of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable, delegations )

                    Nothing ->
                        let
                            ( leftFields, leftTrackable, leftDelegations ) =
                                analyzeFieldAccessesWithAliases paramAliases leftExpr ( fields, trackable, delegations )
                        in
                        analyzeFieldAccessesWithAliases paramAliases rightExpr ( leftFields, leftTrackable, leftDelegations )

            Expression.ParenthesizedExpression inner ->
                analyzeFieldAccessesWithAliases paramAliases inner ( fields, trackable, delegations )

            Expression.TupledExpression exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
                    ( fields, trackable, delegations )
                    exprs

            Expression.ListExpr exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
                    ( fields, trackable, delegations )
                    exprs

            Expression.RecordExpr recordSetters ->
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesWithAliases paramAliases valueExpr acc
                    )
                    ( fields, trackable, delegations )
                    recordSetters

            Expression.RecordUpdateExpression (Node _ varName) recordSetters ->
                let
                    ( updateFields, updateTrackable, updateDelegations ) =
                        if isParamOrAlias paramAliases varName then
                            ( fields, False, delegations )

                        else
                            ( fields, trackable, delegations )
                in
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesWithAliases paramAliases valueExpr acc
                    )
                    ( updateFields, updateTrackable, updateDelegations )
                    recordSetters

            Expression.Negation inner ->
                analyzeFieldAccessesWithAliases paramAliases inner ( fields, trackable, delegations )

            _ ->
                ( fields, trackable, delegations )


{-| Extract a helper delegation from a function application.

Detects patterns like `innerHelper data` where:

  - The function is a local (unqualified) function reference
  - One of the arguments is the parameter or an alias of it

Returns Just the delegation if found, Nothing otherwise.

-}
extractHelperDelegation : List (Node Expression) -> Set String -> Maybe HelperDelegation
extractHelperDelegation exprs paramAliases =
    case exprs of
        (Node _ (Expression.FunctionOrValue [] funcName)) :: args ->
            -- Local function call - check if any arg is our param
            -- Make sure it's not a constructor (starts with uppercase)
            if Char.isLower (String.uncons funcName |> Maybe.map Tuple.first |> Maybe.withDefault 'A') then
                args
                    |> List.indexedMap
                        (\index arg ->
                            case Node.value arg of
                                Expression.FunctionOrValue [] varName ->
                                    if isParamOrAlias paramAliases varName then
                                        Just { funcName = funcName, argIndex = index }

                                    else
                                        Nothing

                                _ ->
                                    Nothing
                        )
                    |> List.filterMap identity
                    |> List.head

            else
                Nothing

        _ ->
            Nothing


{-| Analyze expressions in a function application, checking for untrackable param usage.

This is called when the application is NOT a simple delegation (like `innerHelper data`).
If the param is passed in ways we can't track (nested in a complex expression, passed to
a qualified function, etc.), we mark as untrackable.

-}
analyzeApplicationExprs : Set String -> List (Node Expression) -> ( Set String, Bool, List HelperDelegation ) -> ( Set String, Bool, List HelperDelegation )
analyzeApplicationExprs paramAliases exprs ( fields, trackable, delegations ) =
    -- Check if param is used directly as an argument (untrackable unless it's a simple delegation)
    let
        paramUsedDirectly =
            exprs
                |> List.any
                    (\e ->
                        case Node.value e of
                            Expression.FunctionOrValue [] varName ->
                                isParamOrAlias paramAliases varName

                            _ ->
                                False
                    )
    in
    if paramUsedDirectly then
        -- Param is passed to something we can't track (qualified func, complex expr, etc.)
        ( fields, False, delegations )

    else
        -- No direct param usage, recurse to find nested usages
        List.foldl
            (\e acc -> analyzeFieldAccessesWithAliases paramAliases e acc)
            ( fields, trackable, delegations )
            exprs


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
Also handles function composition patterns:
  - `param |> (.field >> transform)` - extracts field from first operand of >>
  - `param |> (transform << .field)` - extracts field from second operand of <<
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
    case Node.value varExpr of
        Expression.FunctionOrValue [] varName ->
            if isParamOrAlias paramAliases varName then
                extractAccessorFromExpr accessorExpr

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


{-| Result of analyzing a case expression on app.data.

This type unifies the common case expression handling logic used by both
StaticViewTransform (client) and ServerDataTransform (server).

-}
type CaseOnAppDataResult
    = CaseTrackedFields (Set String) -- Specific fields were tracked from record patterns
    | CaseAddBindings (Set String) -- Variable patterns found - add to appDataBindings for further tracking
    | CaseMarkAllFieldsUsed -- Untrackable pattern (constructor, etc.) - mark all fields as used
    | CaseNotOnAppData -- Expression is not a case on app.data


{-| Analyze a case expression to determine how to track field usage.

This consolidates the common case expression handling logic from both
StaticViewTransform and ServerDataTransform. Both transforms had nearly
identical logic for:

1.  Checking if the case is on app.data
2.  Extracting fields from record patterns (trackable)
3.  Adding variable bindings for further tracking
4.  Bailing out for untrackable patterns

The caller must check if they're in ephemeral context (freeze/head) before
applying the result - if in ephemeral context, the result should be ignored.

-}
analyzeCaseOnAppData : Node Expression -> Maybe String -> Set String -> CaseOnAppDataResult
analyzeCaseOnAppData caseExpr appParamName appDataBindings =
    case Node.value caseExpr of
        Expression.CaseExpression caseBlock ->
            if isAppDataAccess caseBlock.expression appParamName appDataBindings then
                -- Case is on app.data - analyze patterns
                case extractCasePatternFields caseBlock.cases of
                    TrackableFields fields ->
                        CaseTrackedFields fields

                    UntrackablePattern ->
                        -- Check for variable patterns we can track
                        let
                            caseBindings =
                                extractCaseVariablePatternBindings caseBlock.cases
                        in
                        if Set.isEmpty caseBindings then
                            -- No variable patterns (constructor patterns, etc.)
                            CaseMarkAllFieldsUsed

                        else
                            -- Variable patterns found - caller should add to appDataBindings
                            CaseAddBindings caseBindings

            else
                CaseNotOnAppData

        _ ->
            CaseNotOnAppData


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
Also handles function composition patterns:
  - `param |> (.field >> transform)` - extracts field from first operand of >>
  - `param |> (transform << .field)` - extracts field from second operand of <<
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
    case Node.value varExpr of
        Expression.FunctionOrValue [] varName ->
            if varName == paramName then
                extractAccessorFromExpr accessorExpr

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

The helperFunctions dictionary maps function names to a list of HelperAnalysis,
one per parameter that could be tracked.

-}
resolvePendingHelperCalls : List (Maybe PendingHelperCall) -> Dict String (List HelperAnalysis) -> ( Set String, Bool )
resolvePendingHelperCalls pendingCalls helperFunctions =
    pendingCalls
        |> List.foldl
            (\pendingCall ( fields, unresolved ) ->
                case pendingCall of
                    Nothing ->
                        -- Qualified/complex function - can't track
                        ( fields, True )

                    Just { funcName, argIndex } ->
                        -- Follow alias chain to get the final analysis for this arg position
                        case resolveHelperWithAliases funcName argIndex helperFunctions Set.empty of
                            Just analysis ->
                                if analysis.isTrackable then
                                    -- Known helper with trackable field usage!
                                    ( Set.union fields analysis.accessedFields, unresolved )

                                else
                                    -- Helper uses param in untrackable ways
                                    ( fields, True )

                            Nothing ->
                                -- Unknown function, no matching param, or cycle detected - can't track
                                ( fields, True )
            )
            ( Set.empty, False )


{-| Resolve a helper function, following alias chains and resolving delegations.

Takes a set of already-visited function names to detect cycles.
Returns Nothing if the function is unknown, no matching param index, or if a cycle is detected.

The returned HelperAnalysis has accessedFields that includes all fields from:

  - Direct field accesses in the helper
  - Recursively resolved delegations to other helpers

-}
resolveHelperWithAliases : String -> Int -> Dict String (List HelperAnalysis) -> Set String -> Maybe HelperAnalysis
resolveHelperWithAliases funcName argIndex helperFunctions visited =
    if Set.member funcName visited then
        -- Cycle detected - bail out
        Nothing

    else
        case Dict.get funcName helperFunctions of
            Just analyses ->
                -- Find analysis for the matching parameter index
                case List.filter (\a -> a.paramIndex == argIndex) analyses of
                    [ analysis ] ->
                        case analysis.aliasTarget of
                            Just targetName ->
                                -- This is an alias, follow the chain
                                -- For aliases, the argIndex carries through to the target
                                resolveHelperWithAliases targetName argIndex helperFunctions (Set.insert funcName visited)

                            Nothing ->
                                -- Not an alias - resolve any delegations
                                resolveDelegations analysis helperFunctions (Set.insert funcName visited)

                    _ ->
                        -- No matching param index or multiple matches - can't track
                        Nothing

            Nothing ->
                -- Unknown function
                Nothing


{-| Resolve all delegations in a helper analysis.

Returns the analysis with accessedFields updated to include all fields from
resolved delegations. Returns Nothing if any delegation can't be resolved.

-}
resolveDelegations : HelperAnalysis -> Dict String (List HelperAnalysis) -> Set String -> Maybe HelperAnalysis
resolveDelegations analysis helperFunctions visited =
    if List.isEmpty analysis.delegations then
        -- No delegations, return as-is
        Just analysis

    else
        -- Resolve each delegation and combine fields
        let
            resolveOne delegation ( accFields, accTrackable ) =
                if not accTrackable then
                    ( accFields, False )

                else
                    case resolveHelperWithAliases delegation.funcName delegation.argIndex helperFunctions visited of
                        Just resolvedAnalysis ->
                            if resolvedAnalysis.isTrackable then
                                ( Set.union accFields resolvedAnalysis.accessedFields, True )

                            else
                                ( accFields, False )

                        Nothing ->
                            -- Couldn't resolve the delegation
                            ( accFields, False )

            ( delegatedFields, allResolved ) =
                List.foldl resolveOne ( Set.empty, True ) analysis.delegations
        in
        if allResolved then
            Just
                { analysis
                    | accessedFields = Set.union analysis.accessedFields delegatedFields
                    , delegations = [] -- Clear delegations since they're now resolved
                }

        else
            -- Some delegation couldn't be resolved - mark as untrackable
            Just { analysis | isTrackable = False }


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
    -> List (Maybe PendingHelperCall)
    -> Dict String (List HelperAnalysis)
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


{-| Compute ephemeral fields with optional head-function correction.

This is the same as `computeEphemeralFields` but allows subtracting fields that
were accessed in the head function. This handles the case in StaticViewTransform
where non-conventional head function naming (e.g., `{ head = seoTags }`) causes
field accesses to be initially tracked as client-used.

The `headFunctionFields` are subtracted from the combined client-used fields
before computing ephemeral fields.

Returns (ephemeralFields, hasUnresolvedCalls, skipReason) where:

  - ephemeralFields: Fields that can be removed from the client Data type
  - hasUnresolvedCalls: True if we had to bail out due to unresolved helper calls
  - skipReason: A string explaining why optimization was skipped, or Nothing

-}
computeEphemeralFieldsWithCorrection :
    { allFieldNames : Set String
    , clientUsedFields : Set String
    , pendingHelperCalls : List (Maybe PendingHelperCall)
    , helperFunctions : Dict String (List HelperAnalysis)
    , headFunctionFields : Set String
    , markAllFieldsAsUsed : Bool
    }
    -> { ephemeralFields : Set String, hasUnresolvedCalls : Bool, skipReason : Maybe String }
computeEphemeralFieldsWithCorrection config =
    let
        -- Resolve pending helper calls against the helper functions dict
        ( resolvedHelperFields, unresolvedHelperCalls ) =
            resolvePendingHelperCalls config.pendingHelperCalls config.helperFunctions

        -- Combine direct field accesses with helper-resolved fields
        combinedClientUsedFields =
            Set.union config.clientUsedFields resolvedHelperFields

        -- Subtract fields accessed by the head function (for non-conventional naming)
        -- When head = seoTags and seoTags is defined before RouteBuilder,
        -- its field accesses were initially tracked as client-used. Now we correct that.
        correctedClientUsedFields =
            Set.diff combinedClientUsedFields config.headFunctionFields

        -- Determine skip reason (for diagnostics)
        skipReason =
            if config.markAllFieldsAsUsed then
                Just "app.data used in untrackable pattern (passed to unknown function, used in case expression, pipe with accessor, or record update)"

            else if unresolvedHelperCalls then
                Just "app.data passed to function that couldn't be analyzed (unknown function or untrackable helper)"

            else
                Nothing

        -- Apply safe fallback: if we can't track field usage, mark ALL as client-used
        effectiveClientUsedFields =
            if config.markAllFieldsAsUsed || unresolvedHelperCalls then
                -- Can't track, so assume ALL fields are client-used (safe fallback)
                config.allFieldNames

            else
                correctedClientUsedFields

        -- Ephemeral fields: all fields that are NOT used in client contexts
        ephemeralFields =
            config.allFieldNames
                |> Set.filter (\f -> not (Set.member f effectiveClientUsedFields))
    in
    { ephemeralFields = ephemeralFields
    , hasUnresolvedCalls = unresolvedHelperCalls
    , skipReason = skipReason
    }


{-| Check if a module is a Route module (e.g., Route.Index, Route.Blog.Slug\_).

Both StaticViewTransform and ServerDataTransform must agree on this check to
ensure server/client agreement. Only Route modules get their Data types transformed.

This returns True for modules like:

  - Route.Index
  - Route.Blog
  - Route.Blog.Slug\_

This returns False for:

  - Site
  - Shared
  - Route (the Route module itself, not a route)

-}
isRouteModule : ModuleName -> Bool
isRouteModule moduleName =
    case moduleName of
        "Route" :: _ :: _ ->
            True

        _ ->
            False


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


{-| Extract helper functions from let declarations.

This identifies let-bound functions with parameters that can be analyzed
for field usage when app.data is passed to them. The returned dictionary
maps function names to their helper analysis.

Both StaticViewTransform and ServerDataTransform need this exact same logic
when processing LetExpression nodes.

-}
extractLetBoundHelperFunctions :
    List (Node Expression.LetDeclaration)
    -> Dict String (List HelperAnalysis)
    -> Dict String (List HelperAnalysis)
extractLetBoundHelperFunctions declarations existingHelpers =
    declarations
        |> List.foldl
            (\declNode helpers ->
                case Node.value declNode of
                    Expression.LetFunction letFn ->
                        let
                            fnDecl =
                                Node.value letFn.declaration

                            fnName =
                                Node.value fnDecl.name
                        in
                        case fnDecl.arguments of
                            [] ->
                                -- No arguments, not a helper function
                                helpers

                            _ ->
                                -- Has arguments - analyze as a helper function
                                let
                                    helperAnalysis =
                                        analyzeHelperFunction letFn
                                in
                                if List.isEmpty helperAnalysis then
                                    helpers

                                else
                                    Dict.insert fnName helperAnalysis helpers

                    Expression.LetDestructuring _ _ ->
                        helpers
            )
            existingHelpers


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


{-| Check if app.data is passed directly to an inner function call.

This is used when we have a nested application like `outer (inner app.data)`.
We check if app.data is passed directly to `inner` (not wrapped in list/tuple/etc).
If so, the inner call will be tracked separately when the visitor reaches it,
so we don't need to bail out for the outer call.

Examples:

  - `extractTitle app.data` -> True (app.data passed directly)
  - `helper [ app.data ]` -> False (app.data wrapped in list)
  - `transform (inner app.data)` -> False (nested application)

-}
isAppDataPassedDirectlyToInnerCall : List (Node Expression) -> Maybe String -> Set String -> Bool
isAppDataPassedDirectlyToInnerCall innerArgs appParamName appDataBindings =
    List.any
        (\arg ->
            case Node.value arg of
                -- app.data passed directly
                Expression.RecordAccess innerExpr (Node _ "data") ->
                    case Node.value innerExpr of
                        Expression.FunctionOrValue [] varName ->
                            appParamName == Just varName

                        _ ->
                            False

                -- Variable bound to app.data passed directly
                Expression.FunctionOrValue [] varName ->
                    Set.member varName appDataBindings

                _ ->
                    False
        )
        innerArgs


{-| Extract field name from pipe operator with accessor pattern on app.data.
Handles `app.data |> .field` and `.field <| app.data`.
Also handles function composition patterns:
  - `app.data |> (.field >> transform)` - extracts field from first operand of >>
  - `app.data |> (transform << .field)` - extracts field from second operand of <<
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
        extractAccessorFromExpr accessorExpr

    else
        Nothing


{-| Extract field name from an expression that should be an accessor.
Handles:
  - Direct accessor: `.field`
  - Function composition: `.field >> transform` or `transform << .field`
  - Parenthesized forms of the above
-}
extractAccessorFromExpr : Node Expression -> Maybe String
extractAccessorFromExpr accessorExpr =
    case Node.value accessorExpr of
        Expression.RecordAccessFunction accessorName ->
            Just (String.dropLeft 1 accessorName)

        -- Handle parenthesized expressions like (.title >> String.toUpper)
        Expression.ParenthesizedExpression inner ->
            extractAccessorFromExpr inner

        -- Handle function composition: .field >> transform or transform << .field
        Expression.OperatorApplication composeOp _ composeLeft composeRight ->
            case composeOp of
                ">>" ->
                    -- .field >> transform: accessor is on the left
                    extractAccessorFromExpr composeLeft

                "<<" ->
                    -- transform << .field: accessor is on the right
                    extractAccessorFromExpr composeRight

                _ ->
                    Nothing

        _ ->
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
    , appDataArgIndex : Maybe Int -- which argument position has app.data (0-indexed)
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
        -- Also track the index of the first direct app.data argument
        ( directAppDataIndices, wrappedAppDataArgs ) =
            args
                |> List.indexedMap Tuple.pair
                |> List.foldl
                    (\( index, arg ) ( directIndices, wrapped ) ->
                        case Node.value arg of
                            -- Check if this is app.data directly (not app.data.field)
                            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                                if fieldName == "data" && isAppDataAccess arg appParamName appDataBindings then
                                    -- This IS app.data passed directly - potentially trackable
                                    ( index :: directIndices, wrapped )

                                else if isAppDataAccess innerExpr appParamName appDataBindings then
                                    -- This is app.data.field - trackable via normal field tracking, skip
                                    ( directIndices, wrapped )

                                else if containsAppData innerExpr then
                                    -- app.data is nested inside - untrackable
                                    ( directIndices, arg :: wrapped )

                                else
                                    ( directIndices, wrapped )

                            -- If the arg is a function call that contains app.data,
                            -- check if it's a trackable local function call
                            Expression.Application innerArgs ->
                                case innerArgs of
                                    (Node _ (Expression.FunctionOrValue [] _)) :: restArgs ->
                                        -- Inner call is to a local function like `localFn app.data`
                                        -- Check if app.data is passed directly to this local function
                                        -- (not wrapped in list/tuple/nested call)
                                        if isAppDataPassedDirectlyToInnerCall restArgs appParamName appDataBindings then
                                            -- Don't mark as wrapped - the inner call will be tracked separately
                                            -- when the visitor reaches it
                                            ( directIndices, wrapped )

                                        else if List.any containsAppData innerArgs then
                                            ( directIndices, arg :: wrapped )

                                        else
                                            ( directIndices, wrapped )

                                    _ ->
                                        -- Qualified function or complex expression - can't track
                                        if List.any containsAppData innerArgs then
                                            ( directIndices, arg :: wrapped )

                                        else
                                            ( directIndices, wrapped )

                            -- Parenthesized expression - unwrap and check inner
                            Expression.ParenthesizedExpression innerNode ->
                                case Node.value innerNode of
                                    Expression.Application innerArgs ->
                                        case innerArgs of
                                            (Node _ (Expression.FunctionOrValue [] _)) :: restArgs ->
                                                -- Inner call is to a local function like `(localFn app.data)`
                                                if isAppDataPassedDirectlyToInnerCall restArgs appParamName appDataBindings then
                                                    ( directIndices, wrapped )

                                                else if List.any containsAppData innerArgs then
                                                    ( directIndices, arg :: wrapped )

                                                else
                                                    ( directIndices, wrapped )

                                            _ ->
                                                if List.any containsAppData innerArgs then
                                                    ( directIndices, arg :: wrapped )

                                                else
                                                    ( directIndices, wrapped )

                                    _ ->
                                        if containsAppData innerNode then
                                            ( directIndices, arg :: wrapped )

                                        else
                                            ( directIndices, wrapped )

                            -- Variable bound to app.data passed directly
                            Expression.FunctionOrValue [] varName ->
                                if Set.member varName appDataBindings then
                                    ( index :: directIndices, wrapped )

                                else
                                    ( directIndices, wrapped )

                            -- Lists, tuples, etc. containing app.data - untrackable
                            _ ->
                                if containsAppData arg then
                                    ( directIndices, arg :: wrapped )

                                else
                                    ( directIndices, wrapped )
                    )
                    ( [], [] )

        hasDirectAppData =
            not (List.isEmpty directAppDataIndices)

        hasWrappedAppData =
            not (List.isEmpty wrappedAppDataArgs)

        -- Get the first (lowest) index where app.data was passed directly
        -- We reverse because indices were prepended during fold
        appDataArgIndex =
            directAppDataIndices
                |> List.reverse
                |> List.head

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
    , appDataArgIndex = appDataArgIndex
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


{-| A pending helper call with function name and the argument index where app.data was passed.
-}
type alias PendingHelperCall =
    { funcName : String
    , argIndex : Int
    }


{-| Check if an expression is a record access function like `.field`.

These are handled separately by trackFieldAccess and shouldn't be treated
as function calls in the pipe operator handler.

Also handles function composition patterns:

  - `.field >> transform` - accessor is on the left of >>
  - `transform << .field` - accessor is on the right of <<

-}
isRecordAccessFunction : Node Expression -> Bool
isRecordAccessFunction node =
    case Node.value node of
        Expression.RecordAccessFunction _ ->
            True

        Expression.ParenthesizedExpression inner ->
            isRecordAccessFunction inner

        -- Handle function composition: .field >> transform or transform << .field
        -- These should be treated as field accessors because they extract a field first
        Expression.OperatorApplication ">>" _ leftExpr _ ->
            -- .field >> transform: accessor is on the left
            isRecordAccessFunction leftExpr

        Expression.OperatorApplication "<<" _ _ rightExpr ->
            -- transform << .field: accessor is on the right
            isRecordAccessFunction rightExpr

        _ ->
            False


{-| Extract variable names from case expression patterns.

For patterns like `case app.data of d -> ...`, extracts "d" so it can be
added to appDataBindings and field accesses like `d.title` can be tracked.

Returns empty set for non-variable patterns (constructor patterns, etc.).

-}
extractCaseVariablePatternBindings : List ( Node Pattern, Node expression ) -> Set String
extractCaseVariablePatternBindings cases =
    cases
        |> List.filterMap
            (\( patternNode, _ ) ->
                extractPatternName patternNode
            )
        |> Set.fromList


{-| Actions to take for pending helper call tracking.

Used by both client and server transforms to determine what to do with
the pendingHelperCalls list based on the AppDataClassification.

-}
type PendingHelperAction
    = AddKnownHelper PendingHelperCall -- Local function with known name and arg position
    | AddUnknownHelper -- Untrackable (wrapped or unknown function)
    | NoHelperAction -- Skip (accessor application or no app.data involved)


{-| Result of analyzing an app.data helper call in client context.

This type consolidates both the pending helper action determination AND the
inline lambda fallback analysis into a single result. Both client and server
transforms can use this to update their context appropriately.

-}
type HelperCallResult
    = HelperCallKnown PendingHelperCall -- Local function to track for later resolution
    | HelperCallLambdaFields (Set String) -- Inline lambda with specific fields to mark as client-used
    | HelperCallUntrackable -- Untrackable (wrapped, unknown function, or untrackable lambda)
    | HelperCallNoAction -- No app.data involvement, nothing to do


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
        case ( classification.maybeFuncName, classification.appDataArgIndex ) of
            ( Just funcName, Just argIndex ) ->
                -- Local function with known arg position - store for lookup in finalEvaluation
                AddKnownHelper { funcName = funcName, argIndex = argIndex }

            _ ->
                -- Qualified or complex function expression, or missing arg index - can't look up
                AddUnknownHelper

    else
        NoHelperAction


{-| Analyze an app.data helper call for client context, including inline lambda fallback.

This consolidates the common logic from checkAppDataPassedToHelper in both
StaticViewTransform and ServerDataTransform. It combines:

1. Classification of arguments via classifyAppDataArguments
2. Initial action determination via determinePendingHelperAction
3. Inline lambda fallback analysis when the initial action is AddUnknownHelper

Both transforms can use this single function and just interpret the result.

-}
analyzeHelperCallInClientContext :
    Node Expression
    -> AppDataClassification
    -> HelperCallResult
analyzeHelperCallInClientContext functionNode classification =
    case determinePendingHelperAction classification of
        AddKnownHelper helperCall ->
            HelperCallKnown helperCall

        AddUnknownHelper ->
            -- Before giving up, check if this is an inline lambda we can analyze
            case classification.appDataArgIndex of
                Just argIndex ->
                    case analyzeInlineLambda functionNode argIndex of
                        LambdaTrackable accessedFields ->
                            -- Lambda is trackable - return specific fields
                            HelperCallLambdaFields accessedFields

                        LambdaUntrackable ->
                            -- Lambda uses parameter in untrackable ways - bail out
                            HelperCallUntrackable

                        NotALambda ->
                            -- Not a lambda - original behavior (unknown helper)
                            HelperCallUntrackable

                Nothing ->
                    -- No arg index - can't analyze
                    HelperCallUntrackable

        NoHelperAction ->
            HelperCallNoAction


{-| Analyze a piped app.data call for client context.

This handles `app.data |> fn` and `fn <| app.data` patterns.
Consolidates the common logic from checkAppDataPassedToHelperViaPipe in both
StaticViewTransform and ServerDataTransform.

Returns a HelperCallResult that both transforms can interpret.

-}
analyzePipedHelperCall : Node Expression -> HelperCallResult
analyzePipedHelperCall functionNode =
    case Node.value functionNode of
        Expression.FunctionOrValue [] funcName ->
            -- Local named function - track as pending helper call (arg index is 0 for pipe)
            HelperCallKnown { funcName = funcName, argIndex = 0 }

        Expression.FunctionOrValue _ _ ->
            -- Qualified function (e.g., Module.fn) - can't analyze, bail out
            HelperCallUntrackable

        Expression.Application (firstExpr :: appliedArgs) ->
            -- Partial application: `formatHelper "prefix"` where app.data will be the next arg
            -- The piped value goes to position = number of already-applied args
            case Node.value firstExpr of
                Expression.FunctionOrValue [] funcName ->
                    -- Local function with some args already applied
                    -- app.data becomes the next argument position
                    HelperCallKnown { funcName = funcName, argIndex = List.length appliedArgs }

                Expression.FunctionOrValue _ _ ->
                    -- Qualified function - can't analyze
                    HelperCallUntrackable

                _ ->
                    -- Complex expression (e.g., (fn) arg) - try lambda analysis
                    analyzeLambdaForPipe functionNode

        _ ->
            -- Could be an inline lambda - try to analyze it
            analyzeLambdaForPipe functionNode


{-| Try to analyze a function node as an inline lambda for pipe patterns.
Returns a HelperCallResult.
-}
analyzeLambdaForPipe : Node Expression -> HelperCallResult
analyzeLambdaForPipe functionNode =
    case analyzeInlineLambda functionNode 0 of
        LambdaTrackable accessedFields ->
            -- Lambda is trackable - return specific fields
            HelperCallLambdaFields accessedFields

        LambdaUntrackable ->
            -- Lambda uses parameter in untrackable ways - bail out
            HelperCallUntrackable

        NotALambda ->
            -- Not a lambda and not a simple function - bail out
            HelperCallUntrackable
