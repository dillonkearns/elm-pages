module Pages.Review.TaintTracking exposing
    ( TaintStatus(..)
    , Nonempty(..)
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
    case ( a, b ) of
        ( Pure, Pure ) ->
            Pure

        _ ->
            Tainted



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
            List.map (analyzeExpressionTaint context) exprs
                |> List.foldl combineTaint Pure

        -- Operators - taint propagates from operands
        Expression.OperatorApplication _ _ left right ->
            combineTaint
                (analyzeExpressionTaint context left)
                (analyzeExpressionTaint context right)

        -- If-then-else - taint propagates from all branches and condition
        Expression.IfBlock cond thenBranch elseBranch ->
            combineTaint (analyzeExpressionTaint context cond)
                (combineTaint
                    (analyzeExpressionTaint context thenBranch)
                    (analyzeExpressionTaint context elseBranch)
                )

        -- Tuple - taint propagates from all elements
        Expression.TupledExpression exprs ->
            List.map (analyzeExpressionTaint context) exprs
                |> List.foldl combineTaint Pure

        -- List - taint propagates from all elements
        Expression.ListExpr exprs ->
            List.map (analyzeExpressionTaint context) exprs
                |> List.foldl combineTaint Pure

        -- Parenthesized - just unwrap
        Expression.ParenthesizedExpression expr ->
            analyzeExpressionTaint context expr

        -- Record - taint propagates from all field values
        Expression.RecordExpr fields ->
            List.map (\(Node _ ( _, fieldExpr )) -> analyzeExpressionTaint context fieldExpr) fields
                |> List.foldl combineTaint Pure

        -- Record update - taint from base record and updated fields
        Expression.RecordUpdateExpression (Node _ recordName) fields ->
            let
                baseTaint =
                    if context.modelParamName == Just recordName then
                        Tainted

                    else
                        lookupBinding recordName context.bindings
                            |> Maybe.withDefault Pure

                fieldsTaint =
                    List.map (\(Node _ ( _, fieldExpr )) -> analyzeExpressionTaint context fieldExpr) fields
                        |> List.foldl combineTaint Pure
            in
            combineTaint baseTaint fieldsTaint

        -- Lambda - analyze the body with current context
        -- Since Elm disallows shadowing, lambda params can't hide tainted values
        Expression.LambdaExpression lambda ->
            analyzeExpressionTaint context lambda.expression

        -- Let expression - analyze the body
        -- (bindings should be tracked externally via visitors)
        Expression.LetExpression letBlock ->
            analyzeExpressionTaint context letBlock.expression

        -- Case expression - analyze expression and all branches
        Expression.CaseExpression caseBlock ->
            let
                exprTaint =
                    analyzeExpressionTaint context caseBlock.expression

                branchTaints =
                    List.map (\( _, branchExpr ) -> analyzeExpressionTaint context branchExpr) caseBlock.cases
                        |> List.foldl combineTaint Pure
            in
            combineTaint exprTaint branchTaints

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
