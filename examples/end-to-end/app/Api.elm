module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import Html exposing (Html)
import Json.Decode as Decode
import Result.Extra
import Route exposing (Route)
import Server.Request as Request
import Server.Response as Response
import Test.Glob


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ greet
    , globTestRouteNew
    ]


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


globTestRouteNew : ApiRoute ApiRoute.Response
globTestRouteNew =
    ApiRoute.succeed
        (Request.succeed
            (Test.Glob.all
                |> DataSource.combine
                |> DataSource.map
                    (\testResults ->
                        case
                            testResults
                                |> Result.Extra.combine
                        of
                            Ok _ ->
                                Response.plainText
                                    ("Pass\n"
                                        ++ String.fromInt (List.length testResults)
                                        ++ " successful tests"
                                    )

                            Err error ->
                                ("Fail\n\n" ++ error)
                                    |> Response.plainText
                                    |> Response.withStatusCode 500
                    )
            )
        )
        |> ApiRoute.literal "tests"
        |> ApiRoute.serverRender
