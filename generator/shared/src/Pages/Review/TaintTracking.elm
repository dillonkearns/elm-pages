module Pages.Review.TaintTracking exposing
    ( TaintStatus(..)
    , Nonempty(..)
    , Bindings
    , TaintContext
    , combineTaint
    , nonemptyFromElement
    , nonemptyHead
    , nonemptyCons
    , nonemptyPop
    , nonemptyMapHead
    , extractBindingsFromPattern
    , analyzeExpressionTaint
    , lookupBinding
    , addBindingsToScope
    , emptyBindings
    )

{-| Shared taint tracking infrastructure for elm-review rules.

This module provides utilities for tracking whether values are "tainted" (derived from
runtime data like `model`) or "pure" (available at build time like `app.data`).

Elm disallows variable shadowing, which simplifies the analysis - we never need to
worry about local bindings hiding outer tainted values.

@docs TaintStatus, Nonempty, TaintContext
@docs combineTaint
@docs nonemptyFromElement, nonemptyHead, nonemptyCons, nonemptyPop, nonemptyMapHead
@docs extractBindingsFromPattern, analyzeExpressionTaint
@docs lookupBinding, addBindingsToScope, emptyBindings

-}

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)



-- NONEMPTY


{-| A non-empty list. Used for scope stacks which always have at least one element.
-}
type Nonempty a
    = Nonempty a (List a)


{-| Create a Nonempty with a single element.
-}
nonemptyFromElement : a -> Nonempty a
nonemptyFromElement a =
    Nonempty a []


{-| Get the head of the Nonempty.
-}
nonemptyHead : Nonempty a -> a
nonemptyHead (Nonempty a _) =
    a


{-| Add an element to the front of the Nonempty.
-}
nonemptyCons : a -> Nonempty a -> Nonempty a
nonemptyCons a (Nonempty head tail) =
    Nonempty a (head :: tail)


{-| Remove the first element from the Nonempty. Returns Nothing if only one element.
-}
nonemptyPop : Nonempty a -> Maybe (Nonempty a)
nonemptyPop (Nonempty _ tail) =
    case tail of
        [] ->
            Nothing

        h :: t ->
            Just (Nonempty h t)


{-| Transform the head element of the Nonempty.
-}
nonemptyMapHead : (a -> a) -> Nonempty a -> Nonempty a
nonemptyMapHead f (Nonempty head tail) =
    Nonempty (f head) tail



-- TAINT STATUS


{-| Tracks whether a value is pure (safe for freeze) or tainted (contains runtime data).
-}
type TaintStatus
    = Pure
    | Tainted


{-| Combine two taint statuses. If either is Tainted, result is Tainted.
-}
combineTaint : TaintStatus -> TaintStatus -> TaintStatus
combineTaint a b =
    case a of
        Tainted ->
            Tainted

        Pure ->
            b


{-| Short-circuit fold for taint analysis. Stops as soon as Tainted is found.
More efficient than `List.map f exprs |> List.foldl combineTaint Pure` because
it doesn't evaluate remaining expressions after finding Tainted.
-}
foldTaint : (a -> TaintStatus) -> List a -> TaintStatus
foldTaint f list =
    case list of
        [] ->
            Pure

        x :: xs ->
            case f x of
                Tainted ->
                    Tainted

                Pure ->
                    foldTaint f xs



-- BINDINGS


{-| A scope stack of variable bindings with their taint status.
-}
type alias Bindings =
    Nonempty (Dict String TaintStatus)


{-| Create an empty bindings scope stack.
-}
emptyBindings : Bindings
emptyBindings =
    nonemptyFromElement Dict.empty


{-| Look up a binding in the scope stack. Returns the taint status if found.
-}
lookupBinding : String -> Bindings -> Maybe TaintStatus
lookupBinding name (Nonempty head tail) =
    case Dict.get name head of
        Just status ->
            Just status

        Nothing ->
            case tail of
                [] ->
                    Nothing

                h :: t ->
                    lookupBinding name (Nonempty h t)


{-| Add bindings to the current (top) scope.
-}
addBindingsToScope : List ( String, TaintStatus ) -> Bindings -> Bindings
addBindingsToScope newBindings bindings =
    nonemptyMapHead
        (\scope -> List.foldl (\( name, status ) dict -> Dict.insert name status dict) scope newBindings)
        bindings



-- PATTERN EXTRACTION


{-| Extract variable bindings from a pattern, assigning the given taint status to each.
-}
extractBindingsFromPattern : TaintStatus -> Node Pattern -> List ( String, TaintStatus )
extractBindingsFromPattern taint node =
    case Node.value node of
        Pattern.VarPattern name ->
            [ ( name, taint ) ]

        Pattern.TuplePattern patterns ->
            List.concatMap (extractBindingsFromPattern taint) patterns

        Pattern.RecordPattern fields ->
            List.map (\(Node _ name) -> ( name, taint )) fields

        Pattern.UnConsPattern head tail ->
            extractBindingsFromPattern taint head ++ extractBindingsFromPattern taint tail

        Pattern.ListPattern patterns ->
            List.concatMap (extractBindingsFromPattern taint) patterns

        Pattern.NamedPattern _ patterns ->
            List.concatMap (extractBindingsFromPattern taint) patterns

        Pattern.AsPattern pattern (Node _ name) ->
            ( name, taint ) :: extractBindingsFromPattern taint pattern

        Pattern.ParenthesizedPattern pattern ->
            extractBindingsFromPattern taint pattern

        -- AllPattern, UnitPattern, CharPattern, StringPattern, IntPattern, HexPattern, FloatPattern
        -- These don't introduce bindings
        _ ->
            []



-- TAINT CONTEXT


{-| Context needed for taint analysis.
-}
type alias TaintContext =
    { modelParamName : Maybe String
    , bindings : Bindings
    }


{-| Analyze the taint status of an expression.
Returns Tainted if the expression depends on model or other tainted bindings.
-}
analyzeExpressionTaint : TaintContext -> Node Expression -> TaintStatus
analyzeExpressionTaint context node =
    case Node.value node of
        -- Variable reference - check if it's model or a tainted binding
        Expression.FunctionOrValue [] name ->
            if context.modelParamName == Just name then
                Tainted

            else
                case lookupBinding name context.bindings of
                    Just status ->
                        status

                    Nothing ->
                        -- Unknown binding (could be top-level or imported) - assume pure
                        Pure

        -- Qualified reference - always pure (imported values)
        Expression.FunctionOrValue (_ :: _) _ ->
            Pure

        -- Record access - propagate taint from the record
        Expression.RecordAccess expr _ ->
            analyzeExpressionTaint context expr

        -- Record access function - pure by itself
        Expression.RecordAccessFunction _ ->
            Pure

        -- Application - taint propagates from function and arguments
        Expression.Application exprs ->
            foldTaint (analyzeExpressionTaint context) exprs

        -- Operators - taint propagates from operands (short-circuit)
        Expression.OperatorApplication _ _ left right ->
            case analyzeExpressionTaint context left of
                Tainted ->
                    Tainted

                Pure ->
                    analyzeExpressionTaint context right

        -- If-then-else - taint propagates from all branches and condition (short-circuit)
        Expression.IfBlock cond thenBranch elseBranch ->
            case analyzeExpressionTaint context cond of
                Tainted ->
                    Tainted

                Pure ->
                    case analyzeExpressionTaint context thenBranch of
                        Tainted ->
                            Tainted

                        Pure ->
                            analyzeExpressionTaint context elseBranch

        -- Tuple - taint propagates from all elements (short-circuit)
        Expression.TupledExpression exprs ->
            foldTaint (analyzeExpressionTaint context) exprs

        -- List - taint propagates from all elements (short-circuit)
        Expression.ListExpr exprs ->
            foldTaint (analyzeExpressionTaint context) exprs

        -- Parenthesized - just unwrap
        Expression.ParenthesizedExpression expr ->
            analyzeExpressionTaint context expr

        -- Record - taint propagates from all field values (short-circuit)
        Expression.RecordExpr fields ->
            foldTaint (\(Node _ ( _, fieldExpr )) -> analyzeExpressionTaint context fieldExpr) fields

        -- Record update - taint from base record and updated fields (short-circuit)
        Expression.RecordUpdateExpression (Node _ recordName) fields ->
            if context.modelParamName == Just recordName then
                Tainted

            else
                case lookupBinding recordName context.bindings of
                    Just Tainted ->
                        Tainted

                    _ ->
                        foldTaint (\(Node _ ( _, fieldExpr )) -> analyzeExpressionTaint context fieldExpr) fields

        -- Lambda - analyze the body with current context
        -- Since Elm disallows shadowing, lambda params can't hide tainted values
        Expression.LambdaExpression lambda ->
            analyzeExpressionTaint context lambda.expression

        -- Let expression - analyze the body with bindings tracked
        Expression.LetExpression letBlock ->
            let
                -- Process each let declaration to extract tainted bindings
                contextWithBindings =
                    List.foldl
                        (\declNode ctx ->
                            case Node.value declNode of
                                Expression.LetFunction letFn ->
                                    let
                                        fnDecl =
                                            Node.value letFn.declaration

                                        fnName =
                                            Node.value fnDecl.name

                                        -- For functions with no arguments, track as binding
                                        -- Functions with arguments are treated as pure (they're definitions)
                                        taint =
                                            case fnDecl.arguments of
                                                [] ->
                                                    analyzeExpressionTaint ctx fnDecl.expression

                                                _ ->
                                                    Pure
                                    in
                                    { ctx | bindings = addBindingsToScope [ ( fnName, taint ) ] ctx.bindings }

                                Expression.LetDestructuring pattern expr ->
                                    let
                                        exprTaint =
                                            analyzeExpressionTaint ctx expr

                                        newBindings =
                                            extractBindingsFromPattern exprTaint pattern
                                    in
                                    { ctx | bindings = addBindingsToScope newBindings ctx.bindings }
                        )
                        context
                        letBlock.declarations
            in
            analyzeExpressionTaint contextWithBindings letBlock.expression

        -- Case expression - analyze expression and all branches with pattern bindings (short-circuit)
        Expression.CaseExpression caseBlock ->
            let
                exprTaint =
                    analyzeExpressionTaint context caseBlock.expression
            in
            case exprTaint of
                Tainted ->
                    Tainted

                Pure ->
                    foldTaint
                        (\( pattern, branchExpr ) ->
                            let
                                -- Pattern bindings inherit taint from the case expression (Pure in this case)
                                patternBindings =
                                    extractBindingsFromPattern Pure pattern

                                branchContext =
                                    { context | bindings = addBindingsToScope patternBindings context.bindings }
                            in
                            analyzeExpressionTaint branchContext branchExpr
                        )
                        caseBlock.cases

        -- Negation - propagate from inner expression
        Expression.Negation expr ->
            analyzeExpressionTaint context expr

        -- Literals and other pure expressions
        Expression.UnitExpr ->
            Pure

        Expression.Integer _ ->
            Pure

        Expression.Hex _ ->
            Pure

        Expression.Floatable _ ->
            Pure

        Expression.Literal _ ->
            Pure

        Expression.CharLiteral _ ->
            Pure

        Expression.GLSLExpression _ ->
            Pure

        Expression.Operator _ ->
            Pure

        Expression.PrefixOperator _ ->
            Pure
