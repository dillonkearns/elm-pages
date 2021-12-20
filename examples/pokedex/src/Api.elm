module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Html exposing (Html)
import Internal.ApiRoute
import Json.Encode
import OptimizedDecoder as Decode
import QueryParams
import Regex
import Route exposing (Route)
import Secrets
import ServerResponse


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ -- route1
      --, route2
      nonHybridRoute
    , noArgs
    , redirectRoute
    , serverRequestInfo
    ]


serverRequestInfo : ApiRoute ApiRoute.Response
serverRequestInfo =
    ApiRoute.succeed
        (serverRequestDataSource
            |> DataSource.map Debug.toString
            |> DataSource.map ServerResponse.stringBody
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "request"
        |> ApiRoute.singleServerless


redirectRoute : ApiRoute ApiRoute.Response
redirectRoute =
    ApiRoute.succeed
        (DataSource.succeed
            (ServerResponse.permanentRedirect "/")
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "redirect"
        |> ApiRoute.singleServerless


serverRequestDataSource =
    ServerRequest.init
        (\language method queryParams protocol allHeaders ->
            { language = language
            , method = method
            , queryParams = queryParams |> QueryParams.toDict
            , protocol = protocol
            , allHeaders = allHeaders
            }
        )
        |> ServerRequest.optionalHeader "accept-language"
        |> ServerRequest.withMethod
        |> ServerRequest.withQueryParams
        |> ServerRequest.withProtocol
        |> ServerRequest.withAllHeaders
        |> ServerRequest.toDataSource


noArgs : ApiRoute ApiRoute.Response
noArgs =
    ApiRoute.succeed
        (DataSource.Http.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)
            |> DataSource.map
                (\stars ->
                    Json.Encode.object
                        [ ( "repo", Json.Encode.string "elm-pages" )
                        , ( "stars", Json.Encode.int stars )
                        ]
                        |> ServerResponse.json
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "stars"
        |> ApiRoute.singleServerless


nonHybridRoute =
    ApiRoute.succeed
        (\repoName ->
            DataSource.Http.get
                (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
                (Decode.field "stargazers_count" Decode.int)
                |> DataSource.map
                    (\stars ->
                        Json.Encode.object
                            [ ( "repo", Json.Encode.string repoName )
                            , ( "stars", Json.Encode.int stars )
                            ]
                            |> Json.Encode.encode 2
                    )
        )
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.buildTimeRoutes
            (\route ->
                DataSource.succeed
                    [ route "elm-graphql"
                    ]
            )


route1 =
    ApiRoute.succeed
        (\repoName ->
            DataSource.Http.get
                (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
                (Decode.field "stargazers_count" Decode.int)
                |> DataSource.map
                    (\stars ->
                        Json.Encode.object
                            [ ( "repo", Json.Encode.string repoName )
                            , ( "stars", Json.Encode.int stars )
                            ]
                            |> Json.Encode.encode 2
                    )
        )
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.literal ".json"
        |> ApiRoute.buildTimeRoutes
            (\route ->
                DataSource.succeed
                    [ route "elm-graphql"
                    ]
            )


route2 : ApiRoute ApiRoute.Response
route2 =
    ApiRoute.succeed
        (DataSource.succeed route1Pattern)
        |> ApiRoute.literal "api-patterns.json"
        |> ApiRoute.single


route1Pattern : String
route1Pattern =
    case route1 of
        ----Internal.ApiRoute.ApiRouteBuilder String (List String -> a) (List String -> String) (List String -> constructor)
        --Internal.ApiRoute.ApiRouteBuilder pattern _ _ _ ->
        --    pattern
        --
        Internal.ApiRoute.ApiRoute record ->
            --record.regex
            --    |> Debug.toString
            record.pattern |> Debug.toString
