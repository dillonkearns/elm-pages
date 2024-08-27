module Pages.RouteParamsTest exposing (suite)

import Elm
import Elm.Annotation
import Elm.CodeGen
import Elm.Pretty
import Elm.ToString
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Pages.Internal.RoutePattern as RoutePattern
import Pretty
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "RouteParams"
        [ test "no dynamic segments" <|
            \() ->
                RoutePattern.fromModuleName [ "No", "Dynamic", "Segments" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just [])
        , test "single dynamic segments" <|
            \() ->
                RoutePattern.fromModuleName [ "User", "Id_" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just
                            [ ( "id", Elm.Annotation.string )
                            ]
                        )
        , test "two dynamic segments" <|
            \() ->
                RoutePattern.fromModuleName [ "UserId_", "ProductId_" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just
                            [ ( "userId", Elm.Annotation.string )
                            , ( "productId", Elm.Annotation.string )
                            ]
                        )
        , test "splat ending" <|
            \() ->
                RoutePattern.fromModuleName [ "UserName_", "RepoName_", "Blob", "SPLAT_" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just
                            [ ( "userName", Elm.Annotation.string )
                            , ( "repoName", Elm.Annotation.string )
                            , ( "splat"
                              , Elm.Annotation.tuple
                                    Elm.Annotation.string
                                    (Elm.Annotation.list Elm.Annotation.string)
                              )
                            ]
                        )
        , test "optional splat ending" <|
            \() ->
                RoutePattern.fromModuleName [ "SPLAT__" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just
                            [ ( "splat", Elm.Annotation.list Elm.Annotation.string )
                            ]
                        )
        , test "ending with optional segment" <|
            \() ->
                RoutePattern.fromModuleName [ "Docs", "Section__" ]
                    |> Maybe.map RoutePattern.toRouteParamsRecord
                    |> Expect.equal
                        (Just
                            [ ( "section", Elm.Annotation.maybe Elm.Annotation.string )
                            ]
                        )
        , describe "toRouteVariant"
            [ test "root route" <|
                \() ->
                    []
                        |> expectRouteDefinition
                            (Elm.variant "Index")
            , test "static-only route" <|
                \() ->
                    RoutePattern.fromModuleName [ "About" ]
                        |> Maybe.map RoutePattern.toVariant
                        |> Expect.equal
                            (Just (Elm.variant "About"))
            , test "dynamic param" <|
                \() ->
                    [ "User", "Id_" ]
                        |> expectRouteDefinition
                            (Elm.variantWith "User__Id_"
                                [ Elm.Annotation.record
                                    [ ( "id", Elm.Annotation.string )
                                    ]
                                ]
                            )
            , test "required splat" <|
                \() ->
                    [ "Username_", "Repo_", "Blob", "SPLAT_" ]
                        |> expectRouteDefinition
                            (Elm.variantWith "Username___Repo___Blob__SPLAT_"
                                [ Elm.Annotation.record
                                    [ ( "username", Elm.Annotation.string )
                                    , ( "repo", Elm.Annotation.string )
                                    , ( "splat"
                                      , Elm.Annotation.tuple
                                            Elm.Annotation.string
                                            (Elm.Annotation.list Elm.Annotation.string)
                                      )
                                    ]
                                ]
                            )
            , test "optional splat" <|
                \() ->
                    [ "SPLAT__" ]
                        |> expectRouteDefinition
                            (Elm.variantWith "SPLAT__"
                                [ Elm.Annotation.record
                                    [ ( "splat"
                                      , Elm.Annotation.list Elm.Annotation.string
                                      )
                                    ]
                                ]
                            )
            , test "optional param" <|
                \() ->
                    [ "Docs", "Section__" ]
                        |> expectRouteDefinition
                            (Elm.variantWith "Docs__Section__"
                                [ Elm.Annotation.record
                                    [ ( "section"
                                      , Elm.Annotation.maybe Elm.Annotation.string
                                      )
                                    ]
                                ]
                            )
            ]
        , describe "toCase"
            [ test "root route" <|
                \() ->
                    [ "Index" ]
                        |> testCaseGenerator
                            [ ( Elm.CodeGen.listPattern []
                              , Elm.CodeGen.val "Index"
                              )
                            ]
            , test "dynamic segment" <|
                \() ->
                    [ "User", "Id_" ]
                        |> testCaseGenerator
                            [ ( Elm.CodeGen.listPattern
                                    [ Elm.CodeGen.stringPattern "user"
                                    , Elm.CodeGen.varPattern "id"
                                    ]
                              , Elm.CodeGen.val "User__Id_ { id = id }"
                              )
                            ]
            , test "optional ending" <|
                \() ->
                    [ "Docs", "Section__" ]
                        |> testCaseGenerator
                            [ ( Elm.CodeGen.listPattern
                                    [ Elm.CodeGen.stringPattern "docs"
                                    , Elm.CodeGen.varPattern "section"
                                    ]
                              , Elm.CodeGen.val "Docs__Section__ { section = Just section }"
                              )
                            , ( Elm.CodeGen.listPattern
                                    [ Elm.CodeGen.stringPattern "docs"
                                    ]
                              , Elm.CodeGen.val "Docs__Section__ { section = Nothing }"
                              )
                            ]
            , test "required splat" <|
                \() ->
                    [ "Username_", "Repo_", "Blob", "SPLAT_" ]
                        |> testCaseGenerator
                            [ ( --Elm. """username :: repo :: "blob" :: splatFirst :: splatRest"""
                                --( Elm.CodeGen.unConsPattern
                                unconsPattern
                                    [ Elm.CodeGen.varPattern "username"
                                    , Elm.CodeGen.varPattern "repo"
                                    , Elm.CodeGen.stringPattern "blob"
                                    , Elm.CodeGen.varPattern "splatFirst"
                                    , Elm.CodeGen.varPattern "splatRest"
                                    ]
                              , Elm.CodeGen.val
                                    "Username___Repo___Blob__SPLAT_ { username = username, repo = repo, splat = ( splatFirst, splatRest ) }"
                              )
                            ]
            ]
        , fuzz routeModuleNameFuzzer "to/from module name" <|
            \moduleName ->
                moduleName
                    |> RoutePattern.fromModuleName
                    |> Maybe.map RoutePattern.toModuleName
                    |> Expect.equal (Just moduleName)
        ]


routeModuleNameFuzzer : Fuzzer (List String)
routeModuleNameFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant [ "Index" ]
        , Fuzz.constant [ "User", "Id_" ]
        , Fuzz.constant [ "Docs", "Section__" ]
        ]


unconsPattern : List Elm.CodeGen.Pattern -> Elm.CodeGen.Pattern
unconsPattern list =
    case list of
        [] ->
            Elm.CodeGen.listPattern []

        listFirst :: listRest ->
            List.foldl
                (\soFar item ->
                    soFar
                        |> Elm.CodeGen.unConsPattern item
                )
                listFirst
                listRest


testCaseGenerator : List ( Elm.CodeGen.Pattern, Elm.CodeGen.Expression ) -> List String -> Expectation
testCaseGenerator expected moduleName =
    RoutePattern.fromModuleName moduleName
        |> Maybe.map (RoutePattern.routeToBranch >> List.map toStringCase)
        |> Maybe.withDefault [ ( "<ERROR>", "<ERROR>" ) ]
        |> Expect.equal (expected |> List.map toStringCase)


toStringCase : ( Elm.CodeGen.Pattern, Elm.CodeGen.Expression ) -> ( String, String )
toStringCase branch =
    branch
        |> Tuple.mapBoth
            (Elm.Pretty.prettyPattern
                >> Pretty.pretty 120
            )
            (Elm.Pretty.prettyExpression
                >> Pretty.pretty 120
            )


expectRouteDefinition : Elm.Variant -> List String -> Expectation
expectRouteDefinition expected moduleName =
    RoutePattern.fromModuleName moduleName
        |> Maybe.map (RoutePattern.toVariant >> toString)
        |> Maybe.withDefault "<ERROR>"
        |> Expect.equal (expected |> toString)


toString : Elm.Variant -> String
toString variants =
    Elm.customType "Route" [ variants ]
        |> Elm.ToString.declaration
        |> List.map .body
        |> String.join "\n\n"
