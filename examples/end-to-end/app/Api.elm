module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import Html exposing (Html)
import Json.Decode as Decode
import Pages
import Random
import Route exposing (Route)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Test.Glob
import Test.Runner.Html
import Time


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    let
        html : Html Never -> Response data
        html htmlValue =
            { statusCode = 200
            , headers = [ ( "Content-Type", "text/html; charset=UTF-8" ) ]
            , body = Just (htmlToString htmlValue)
            , isBase64Encoded = False
            }
                |> Response.customResponse
    in
    [ greet
    , ApiRoute.succeed
        (Request.succeed
            (Test.Glob.all
                |> DataSource.map viewHtmlResults
                |> DataSource.map html
            )
        )
        |> ApiRoute.literal "tests"
        |> ApiRoute.serverRender
    ]


config : Test.Runner.Html.Config
config =
    Random.initialSeed (Pages.builtAt |> Time.posixToMillis)
        |> Test.Runner.Html.defaultConfig
        |> Test.Runner.Html.hidePassedTests


viewHtmlResults tests =
    Html.div []
        [ Html.h1 [] [ Html.text "My Test Suite" ]
        , Html.div [] [ Test.Runner.Html.viewResults config tests ]
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
