module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Glob as Glob exposing (Glob)
import Html exposing (Html)
import Json.Decode as Decode
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


globTest : Glob String -> Int -> ApiRoute ApiRoute.Response
globTest pattern testNumber =
    ApiRoute.succeed
        (Request.succeed
            (pattern
                |> Glob.toDataSource
                |> DataSource.map (String.join ",")
                |> DataSource.map Response.plainText
            )
        )
        |> ApiRoute.literal "glob-test"
        |> ApiRoute.slash
        |> ApiRoute.literal (String.fromInt testNumber)
        |> ApiRoute.serverRender


findBySplat : List String -> Glob String
findBySplat splat =
    if splat == [] then
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


globTests : List (ApiRoute ApiRoute.Response)
globTests =
    [ findBySplat []
    , findBySplat [ "foo" ]
    , findBySplat [ "bar" ]
    ]
        |> List.indexedMap
            (\index pattern ->
                globTest pattern (index + 1)
            )
