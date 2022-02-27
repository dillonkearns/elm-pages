module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Glob as Glob exposing (Glob)
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode as Encode
import List.NonEmpty
import Route exposing (Route)
import Server.Request as Request
import Server.Response as Response


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ greet
    ]
        ++ globTests


greet : ApiRoute ApiRoute.Response
greet =
    ApiRoute.succeed
        (Request.oneOf
            [ Request.expectFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            , Request.expectJsonBody (Decode.field "first" Decode.string)
            , Request.expectQueryParam "first"
            , Request.expectMultiPartFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            ]
            |> Request.map
                (\firstName ->
                    Response.plainText ("Hello " ++ firstName)
                        |> DataSource.succeed
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "greet"
        |> ApiRoute.serverRender


globTest : Glob Encode.Value -> Int -> ApiRoute ApiRoute.Response
globTest pattern testNumber =
    ApiRoute.succeed
        (Request.succeed
            (pattern
                |> Glob.toDataSource
                |> DataSource.map (Encode.list identity)
                |> DataSource.map Response.json
            )
        )
        |> ApiRoute.literal "glob-test"
        |> ApiRoute.slash
        |> ApiRoute.literal (String.fromInt testNumber)
        |> ApiRoute.serverRender



--findBySplat : List String -> Glob String


findBySplat splat =
    (if splat == [] then
        Glob.literal "content/index.md"

     else
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/")
            |> Glob.match (Glob.literal (String.join "/" splat))
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")
    )
        |> Glob.map Encode.string


globTests : List (ApiRoute ApiRoute.Response)
globTests =
    [ findBySplat []
    , findBySplat [ "foo" ]
    , findBySplat [ "bar" ]
    , Glob.succeed identity
        |> Glob.match (Glob.literal "glob-test-cases/content1/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.oneOf ( ( ".md", () ), [ ( "/", () ) ] ))
        |> Glob.match Glob.wildcard
        |> Glob.map Encode.string
    , Glob.succeed
        (\first second wildcardPart ->
            Encode.object
                [ ( "first", Encode.string first )
                , ( "second", Encode.string second )
                , ( "wildcard", Encode.string wildcardPart )
                ]
        )
        |> Glob.capture (Glob.literal "glob-test-cases/")
        |> Glob.capture (Glob.literal "content1/")
        |> Glob.capture Glob.wildcard
    , Glob.succeed
        (\first second ->
            Encode.object
                [ ( "first", Encode.string first )
                , ( "second", Encode.string second )
                ]
        )
        |> Glob.match (Glob.literal "glob-test-cases/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".")
        |> Glob.capture
            (Glob.oneOf
                ( ( "yml", "YAML" )
                , [ ( "json", "JSON" )
                  ]
                )
            )
    , Glob.succeed
        (\year month day slug ->
            Encode.object
                [ ( "year", Encode.int year )
                , ( "month", Encode.int month )
                , ( "day", Encode.int day )
                , ( "slug", Encode.string slug )
                ]
        )
        |> Glob.match (Glob.literal "glob-test-cases/")
        |> Glob.match (Glob.literal "archive/")
        |> Glob.capture Glob.int
        |> Glob.match (Glob.literal "/")
        |> Glob.capture Glob.int
        |> Glob.match (Glob.literal "/")
        |> Glob.capture Glob.int
        |> Glob.match (Glob.literal "/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
    , Glob.succeed (List.NonEmpty.toList >> Encode.list Encode.string)
        |> Glob.match (Glob.literal "glob-test-cases/at-least-one/")
        |> Glob.match Glob.wildcard
        |> Glob.match (Glob.literal ".")
        |> Glob.capture
            (Glob.atLeastOne
                ( ( "yml", "YAML" )
                , [ ( "json", "JSON" )
                  ]
                )
            )
    ]
        |> List.indexedMap
            (\index pattern ->
                globTest pattern (index + 1)
            )
