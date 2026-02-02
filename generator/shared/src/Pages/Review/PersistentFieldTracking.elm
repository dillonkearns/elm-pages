module Pages.Review.PersistentFieldTracking exposing
    ( HelperAnalysis
    , analyzeHelperFunction
    , extractPatternName
    , extractPatternNames
    , extractRecordPatternFields
    , extractPipeAccessorField
    , extractAccessorFieldFromApplication
    , extractAppDataPipeAccessorField
    , isAppDataAccess
    , isViewFreezeCall
    , resolvePendingHelperCalls
    , typeAnnotationToString
    )

{-| Shared utilities for persistent field tracking in elm-review rules.

Both StaticViewTransform (client) and ServerDataTransform (server) need to agree
on which fields are ephemeral. This module provides the shared analysis functions
to ensure consistency.

@docs HelperAnalysis
@docs analyzeHelperFunction
@docs extractPatternName, extractPatternNames, extractRecordPatternFields
@docs extractPipeAccessorField, extractAccessorFieldFromApplication, extractAppDataPipeAccessorField
@docs isAppDataAccess, isViewFreezeCall, resolvePendingHelperCalls
@docs typeAnnotationToString

-}

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Set exposing (Set)


{-| Analysis of a helper function's field usage on its first parameter.
-}
type alias HelperAnalysis =
    { paramName : String -- First parameter name
    , accessedFields : Set String -- Fields accessed on first param (e.g., param.field)
    , isTrackable : Bool -- False if param is used in ways we can't track
    }


{-| Analyze a helper function to determine which fields it accesses on its first parameter.

This enables tracking field usage when app.data is passed to a helper function.
Also handles record destructuring patterns like `renderContent { title, body } = ...`
where we know EXACTLY which fields are used.

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
                                }

                        Nothing ->
                            -- Other pattern (tuple, constructor, etc.) - can't track safely
                            Nothing

        [] ->
            -- No parameters, not a helper that takes data
            Nothing


{-| Analyze an expression to find all field accesses on a given parameter name.

Returns (accessedFields, isTrackable) where:

  - accessedFields: Set of field names accessed like `param.fieldName`
  - isTrackable: False if the parameter is used in ways we can't track
    (passed to another function, used in case expression, etc.)

-}
analyzeFieldAccessesOnParam : String -> Node Expression -> ( Set String, Bool )
analyzeFieldAccessesOnParam paramName expr =
    analyzeFieldAccessesHelper paramName expr ( Set.empty, True )


analyzeFieldAccessesHelper : String -> Node Expression -> ( Set String, Bool ) -> ( Set String, Bool )
analyzeFieldAccessesHelper paramName node ( fields, trackable ) =
    if not trackable then
        ( fields, False )

    else
        case Node.value node of
            Expression.RecordAccess innerExpr (Node _ fieldName) ->
                case Node.value innerExpr of
                    Expression.FunctionOrValue [] varName ->
                        if varName == paramName then
                            ( Set.insert fieldName fields, trackable )

                        else
                            ( fields, trackable )

                    _ ->
                        analyzeFieldAccessesHelper paramName innerExpr ( fields, trackable )

            Expression.FunctionOrValue [] varName ->
                if varName == paramName then
                    ( fields, False )

                else
                    ( fields, trackable )

            -- Function application - check for accessor function pattern .field param
            Expression.Application exprs ->
                case extractAccessorFieldFromApplication exprs paramName of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable )

                    Nothing ->
                        List.foldl
                            (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                            ( fields, trackable )
                            exprs

            Expression.LetExpression letBlock ->
                let
                    ( declFields, declTrackable ) =
                        List.foldl
                            (\declNode acc ->
                                case Node.value declNode of
                                    Expression.LetFunction letFn ->
                                        analyzeFieldAccessesHelper paramName (Node.value letFn.declaration).expression acc

                                    Expression.LetDestructuring _ letExpr ->
                                        analyzeFieldAccessesHelper paramName letExpr acc
                            )
                            ( fields, trackable )
                            letBlock.declarations
                in
                analyzeFieldAccessesHelper paramName letBlock.expression ( declFields, declTrackable )

            Expression.IfBlock cond then_ else_ ->
                let
                    ( condFields, condTrackable ) =
                        analyzeFieldAccessesHelper paramName cond ( fields, trackable )

                    ( thenFields, thenTrackable ) =
                        analyzeFieldAccessesHelper paramName then_ ( condFields, condTrackable )
                in
                analyzeFieldAccessesHelper paramName else_ ( thenFields, thenTrackable )

            Expression.CaseExpression caseBlock ->
                let
                    caseOnParam =
                        case Node.value caseBlock.expression of
                            Expression.FunctionOrValue [] varName ->
                                varName == paramName

                            _ ->
                                False

                    ( exprFields, exprTrackable ) =
                        if caseOnParam then
                            ( fields, False )

                        else
                            analyzeFieldAccessesHelper paramName caseBlock.expression ( fields, trackable )
                in
                List.foldl
                    (\( _, caseExpr ) acc -> analyzeFieldAccessesHelper paramName caseExpr acc)
                    ( exprFields, exprTrackable )
                    caseBlock.cases

            Expression.LambdaExpression lambda ->
                let
                    shadowsParam =
                        lambda.args
                            |> List.any
                                (\arg ->
                                    case extractPatternName arg of
                                        Just name ->
                                            name == paramName

                                        Nothing ->
                                            False
                                )
                in
                if shadowsParam then
                    ( fields, trackable )

                else
                    analyzeFieldAccessesHelper paramName lambda.expression ( fields, trackable )

            -- Pipe operators with accessor: param |> .field or .field <| param
            -- Also handles other operators by recursing into both sides
            Expression.OperatorApplication op _ leftExpr rightExpr ->
                case extractPipeAccessorField op paramName leftExpr rightExpr of
                    Just fieldName ->
                        ( Set.insert fieldName fields, trackable )

                    Nothing ->
                        let
                            ( leftFields, leftTrackable ) =
                                analyzeFieldAccessesHelper paramName leftExpr ( fields, trackable )
                        in
                        analyzeFieldAccessesHelper paramName rightExpr ( leftFields, leftTrackable )

            Expression.ParenthesizedExpression inner ->
                analyzeFieldAccessesHelper paramName inner ( fields, trackable )

            Expression.TupledExpression exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                    ( fields, trackable )
                    exprs

            Expression.ListExpr exprs ->
                List.foldl
                    (\e acc -> analyzeFieldAccessesHelper paramName e acc)
                    ( fields, trackable )
                    exprs

            Expression.RecordExpr recordSetters ->
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesHelper paramName valueExpr acc
                    )
                    ( fields, trackable )
                    recordSetters

            Expression.RecordUpdateExpression (Node _ varName) recordSetters ->
                let
                    ( updateFields, updateTrackable ) =
                        if varName == paramName then
                            ( fields, False )

                        else
                            ( fields, trackable )
                in
                List.foldl
                    (\(Node _ ( _, valueExpr )) acc ->
                        analyzeFieldAccessesHelper paramName valueExpr acc
                    )
                    ( updateFields, updateTrackable )
                    recordSetters

            Expression.Negation inner ->
                analyzeFieldAccessesHelper paramName inner ( fields, trackable )

            _ ->
                ( fields, trackable )


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
                        case Dict.get funcName helperFunctions of
                            Just analysis ->
                                if analysis.isTrackable then
                                    -- Known helper with trackable field usage!
                                    ( Set.union fields analysis.accessedFields, unresolved )

                                else
                                    -- Helper uses param in untrackable ways
                                    ( fields, True )

                            Nothing ->
                                -- Unknown function - can't track which fields it uses
                                ( fields, True )
            )
            ( Set.empty, False )


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
