module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
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
