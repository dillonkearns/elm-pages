module Pages.RouteParamsTest exposing (..)

import Elm
import Elm.Annotation
import Elm.ToString
import Expect exposing (Expectation)
import Pages.Internal.RoutePattern as RoutePattern
import Test exposing (Test, describe, test)


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
            ]
        ]


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
        |> .body
