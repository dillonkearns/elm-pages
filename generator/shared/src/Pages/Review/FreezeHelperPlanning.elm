module Pages.Review.FreezeHelperPlanning exposing
    ( FreezeKnowledge
    , FunctionId
    , computeTransitiveFreezeFunctions
    , findUnsupportedHelperFunctionValueArg
    , findUnsupportedLocalFunctionValueArg
    , functionContainsFreeze
    , helperCallNeedsFrozenId
    , isPartialHelperCall
    , letFunctionsWithDirectSeededHelperCalls
    , shouldSeedHelperCallIds
    )

{-| Shared planning utilities for frozen helper ID propagation.

Both StaticViewTransform and ServerDataTransform must make identical decisions
about which helper calls need frozen IDs and which call shapes are unsupported.
This module centralizes that logic.
-}

import Dict exposing (Dict)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Set exposing (Set)


type alias FunctionId =
    ( ModuleName, String )


type alias FreezeKnowledge =
    { freezeFunctions : Dict FunctionId Int
    , functionCalls : Dict FunctionId (Set FunctionId)
    , functionArities : Dict FunctionId Int
    }


type alias ShouldSeedConfig =
    { isRouteModule : ModuleName -> Bool
    , isSharedModule : ModuleName -> Bool
    , moduleName : ModuleName
    , currentFunctionName : Maybe String
    }


computeTransitiveFreezeFunctions :
    Dict FunctionId Int
    -> Dict FunctionId (Set FunctionId)
    -> Dict FunctionId Int
computeTransitiveFreezeFunctions directFreezeFunctions functionCalls =
    let
        directFreezeCallers =
            directFreezeFunctions
                |> Dict.filter (\_ count -> count > 0)
                |> Dict.keys
                |> Set.fromList

        transitiveFreezeCallers =
            fixedPointFreezeCallers directFreezeCallers functionCalls
    in
    Set.foldl
        (\functionId acc ->
            Dict.insert functionId
                (Dict.get functionId directFreezeFunctions |> Maybe.withDefault 1)
                acc
        )
        Dict.empty
        transitiveFreezeCallers


fixedPointFreezeCallers :
    Set FunctionId
    -> Dict FunctionId (Set FunctionId)
    -> Set FunctionId
fixedPointFreezeCallers currentFreezeCallers functionCalls =
    let
        callersReachingFreeze =
            Dict.foldl
                (\caller callees acc ->
                    if Set.member caller currentFreezeCallers then
                        acc

                    else if Set.isEmpty (Set.intersect callees currentFreezeCallers) then
                        acc

                    else
                        Set.insert caller acc
                )
                Set.empty
                functionCalls

        nextFreezeCallers =
            Set.union currentFreezeCallers callersReachingFreeze
    in
    if Set.size nextFreezeCallers == Set.size currentFreezeCallers then
        currentFreezeCallers

    else
        fixedPointFreezeCallers nextFreezeCallers functionCalls


functionContainsFreeze : FreezeKnowledge -> FunctionId -> Bool
functionContainsFreeze knowledge functionId =
    functionReachesFreeze Set.empty functionId knowledge


functionReachesFreeze : Set FunctionId -> FunctionId -> FreezeKnowledge -> Bool
functionReachesFreeze visited functionId knowledge =
    if Set.member functionId visited then
        False

    else if projectFreezeContains functionId knowledge then
        True

    else
        let
            nextVisited =
                Set.insert functionId visited

            callees =
                lookupProjectFunctionCallees functionId knowledge
        in
        if Set.isEmpty callees then
            False

        else
            Set.foldl
                (\callee reachesFreeze ->
                    reachesFreeze || functionReachesFreeze nextVisited callee knowledge
                )
                False
                callees


projectFreezeContains : FunctionId -> FreezeKnowledge -> Bool
projectFreezeContains functionId knowledge =
    Dict.keys knowledge.freezeFunctions
        |> List.any (\candidateId -> functionIdsMatch functionId candidateId)


lookupProjectFunctionCallees : FunctionId -> FreezeKnowledge -> Set FunctionId
lookupProjectFunctionCallees functionId knowledge =
    Dict.foldl
        (\candidateId callees acc ->
            if functionIdsMatch functionId candidateId then
                Set.union callees acc

            else
                acc
        )
        Set.empty
        knowledge.functionCalls


functionIdsMatch : FunctionId -> FunctionId -> Bool
functionIdsMatch ( targetModule, targetFunction ) ( candidateModule, candidateFunction ) =
    targetFunction == candidateFunction
        && moduleNamesMatch targetModule candidateModule


moduleNamesMatch : ModuleName -> ModuleName -> Bool
moduleNamesMatch targetModule candidateModule =
    targetModule == candidateModule
        || (isSingleSegment targetModule && moduleNameLastSegment targetModule == moduleNameLastSegment candidateModule)
        || (isSingleSegment candidateModule && moduleNameLastSegment targetModule == moduleNameLastSegment candidateModule)


isSingleSegment : ModuleName -> Bool
isSingleSegment moduleName =
    List.length moduleName == 1


moduleNameLastSegment : ModuleName -> Maybe String
moduleNameLastSegment moduleName =
    moduleName
        |> List.reverse
        |> List.head


helperCallNeedsFrozenId : FreezeKnowledge -> (Node Expression -> Maybe FunctionId) -> Node Expression -> Bool
helperCallNeedsFrozenId knowledge resolveCalledFunctionId functionNode =
    case resolveCalledFunctionId functionNode of
        Just functionId ->
            functionContainsFreeze knowledge functionId

        Nothing ->
            False


findUnsupportedHelperFunctionValueArg :
    FreezeKnowledge
    -> (Node Expression -> Maybe FunctionId)
    -> List (Node Expression)
    -> Maybe (Node Expression)
findUnsupportedHelperFunctionValueArg knowledge resolveCalledFunctionId args =
    args
        |> List.filter
            (\arg ->
                case Node.value (unwrapParenthesizedExpression arg) of
                    Expression.FunctionOrValue _ _ ->
                        helperCallNeedsFrozenId knowledge resolveCalledFunctionId arg

                    _ ->
                        False
            )
        |> List.head


letFunctionsWithDirectSeededHelperCalls :
    (Node Expression -> Bool)
    -> List (Node Expression.LetDeclaration)
    -> Set String
letFunctionsWithDirectSeededHelperCalls needsFrozenId declarations =
    declarations
        |> List.filterMap
            (\declaration ->
                case Node.value declaration of
                    Expression.LetFunction letFn ->
                        let
                            fnDecl =
                                Node.value letFn.declaration

                            fnName =
                                Node.value fnDecl.name
                        in
                        case extractDirectAppliedFunction fnDecl.expression of
                            Just functionNode ->
                                if needsFrozenId functionNode then
                                    Just fnName

                                else
                                    Nothing

                            Nothing ->
                                Nothing

                    Expression.LetDestructuring _ _ ->
                        Nothing
            )
        |> Set.fromList


findUnsupportedLocalFunctionValueArg :
    Set String
    -> List (Node Expression)
    -> Maybe (Node Expression)
findUnsupportedLocalFunctionValueArg localFunctionNames args =
    args
        |> List.filter
            (\arg ->
                case Node.value (unwrapParenthesizedExpression arg) of
                    Expression.FunctionOrValue [] functionName ->
                        Set.member functionName localFunctionNames

                    Expression.Application (firstExpr :: _) ->
                        case Node.value (unwrapParenthesizedExpression firstExpr) of
                            Expression.FunctionOrValue [] functionName ->
                                Set.member functionName localFunctionNames

                            _ ->
                                False

                    _ ->
                        False
            )
        |> List.head


extractDirectAppliedFunction : Node Expression -> Maybe (Node Expression)
extractDirectAppliedFunction expressionNode =
    case Node.value (unwrapParenthesizedExpression expressionNode) of
        Expression.Application (functionNode :: _) ->
            Just functionNode

        _ ->
            Nothing


isPartialHelperCall :
    FreezeKnowledge
    -> (Node Expression -> Maybe FunctionId)
    -> Node Expression
    -> List (Node Expression)
    -> Bool
isPartialHelperCall knowledge resolveCalledFunctionId functionNode args =
    case resolveCalledFunctionId functionNode |> Maybe.andThen (\functionId -> lookupProjectFunctionArity functionId knowledge) of
        Just requiredArgCount ->
            List.length args < requiredArgCount

        Nothing ->
            False


lookupProjectFunctionArity : FunctionId -> FreezeKnowledge -> Maybe Int
lookupProjectFunctionArity functionId knowledge =
    let
        matchingArities =
            Dict.foldl
                (\candidateId argCount acc ->
                    if functionIdsMatch functionId candidateId then
                        Set.insert argCount acc

                    else
                        acc
                )
                Set.empty
                knowledge.functionArities
    in
    case Set.toList matchingArities of
        [ uniqueArgCount ] ->
            Just uniqueArgCount

        _ ->
            Nothing


shouldSeedHelperCallIds : ShouldSeedConfig -> Bool
shouldSeedHelperCallIds config =
    case config.currentFunctionName of
        Nothing ->
            False

        Just functionName ->
            if config.isRouteModule config.moduleName || config.isSharedModule config.moduleName then
                functionName == "view"

            else
                True


unwrapParenthesizedExpression : Node Expression -> Node Expression
unwrapParenthesizedExpression node =
    case Node.value node of
        Expression.ParenthesizedExpression inner ->
            unwrapParenthesizedExpression inner

        _ ->
            node
