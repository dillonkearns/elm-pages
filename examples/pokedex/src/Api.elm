module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Html exposing (Html)
import Json.Decode
import Json.Encode
import OptimizedDecoder as Decode
import QueryParams
import Route exposing (Route)
import Secrets
import Server.Request
import Server.SetCookie as SetCookie
import ServerResponse


routes :
    DataSource (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ nonHybridRoute
    , noArgs
    , redirectRoute
    , repoStars
    , repoStars2
    , logout
    , greet
    , fileLength
    , jsonError
    ]


jsonError : ApiRoute ApiRoute.Response
jsonError =
    ApiRoute.succeed
        (Server.Request.oneOf
            [ Server.Request.jsonBodyResult (Decode.field "name" Decode.string)
                |> Server.Request.map
                    (\result ->
                        case result of
                            Ok firstName ->
                                ServerResponse.stringBody
                                    ("Hello " ++ firstName)

                            Err decodeError ->
                                decodeError
                                    |> Json.Decode.errorToString
                                    |> ServerResponse.stringBody
                                    |> ServerResponse.withStatusCode 400
                    )
            , Server.Request.succeed (ServerResponse.stringBody "Hello anonymous!")
            ]
            |> Server.Request.map DataSource.succeed
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "validate-json"
        |> ApiRoute.serverRender


greet : ApiRoute ApiRoute.Response
greet =
    ApiRoute.succeed
        (Server.Request.oneOf
            [ Server.Request.expectFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            , Server.Request.expectJsonBody (Decode.field "first" Decode.string)
            , Server.Request.expectQueryParam "first"
            , Server.Request.expectMultiPartFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            ]
            |> Server.Request.map
                (\firstName ->
                    ServerResponse.stringBody ("Hello " ++ firstName)
                        |> DataSource.succeed
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "greet"
        |> ApiRoute.serverRender


fileLength : ApiRoute ApiRoute.Response
fileLength =
    ApiRoute.succeed
        (Server.Request.expectMultiPartFormPost
            (\{ field, optionalField, fileField } ->
                fileField "file"
            )
            |> Server.Request.map
                (\file ->
                    ServerResponse.json
                        (Json.Encode.object
                            [ ( "File name: ", Json.Encode.string file.name )
                            , ( "Length", Json.Encode.int (String.length file.body) )
                            , ( "mime-type", Json.Encode.string file.mimeType )
                            , ( "First line"
                              , Json.Encode.string
                                    (file.body
                                        |> String.split "\n"
                                        |> List.head
                                        |> Maybe.withDefault ""
                                    )
                              )
                            ]
                        )
                        |> DataSource.succeed
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "file"
        |> ApiRoute.serverRender


redirectRoute : ApiRoute ApiRoute.Response
redirectRoute =
    ApiRoute.succeed
        (Server.Request.succeed
            (DataSource.succeed
                (ServerResponse.temporaryRedirect "/")
            )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "redirect"
        |> ApiRoute.serverRender


serverRequestDataSource isAvailable =
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
        |> ServerRequest.toDataSource isAvailable


noArgs : ApiRoute ApiRoute.Response
noArgs =
    ApiRoute.succeed
        (Server.Request.succeed
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
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "stars"
        |> ApiRoute.serverRender


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
        |> ApiRoute.preRender
            (\route ->
                DataSource.succeed
                    [ route "elm-graphql"
                    ]
            )


logout : ApiRoute ApiRoute.Response
logout =
    ApiRoute.succeed
        (Server.Request.succeed
            (DataSource.succeed
                (ServerResponse.stringBody "You are logged out"
                    |> ServerResponse.withHeader "Set-Cookie"
                        (SetCookie.setCookie "username" ""
                            |> SetCookie.httpOnly
                            |> SetCookie.withPath "/"
                            |> SetCookie.withImmediateExpiration
                            |> SetCookie.toString
                        )
                )
            )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "logout"
        |> ApiRoute.serverRender


repoStars : ApiRoute ApiRoute.Response
repoStars =
    ApiRoute.succeed
        (\repoName ->
            Server.Request.succeed
                (DataSource.Http.get
                    (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
                    (Decode.field "stargazers_count" Decode.int)
                    |> DataSource.map
                        (\stars ->
                            Json.Encode.object
                                [ ( "repo", Json.Encode.string repoName )
                                , ( "stars", Json.Encode.int stars )
                                ]
                                |> ServerResponse.json
                        )
                )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        --|> ApiRoute.literal ".json"
        |> ApiRoute.serverRender


repoStars2 : ApiRoute ApiRoute.Response
repoStars2 =
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
                            |> ServerResponse.json
                    )
        )
        |> ApiRoute.literal "api2"
        |> ApiRoute.slash
        |> ApiRoute.literal "repo"
        |> ApiRoute.slash
        |> ApiRoute.capture
        |> ApiRoute.preRenderWithFallback
            (\route ->
                DataSource.succeed
                    [ route "elm-graphql"
                    , route "elm-pages"
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
