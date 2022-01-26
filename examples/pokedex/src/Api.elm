module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import DataSource exposing (DataSource)
import DataSource.Http
import Html exposing (Html)
import Json.Decode
import Json.Encode
import MySession
import Route exposing (Route)
import Secrets
import Server.Request
import Server.Response
import Server.SetCookie as SetCookie
import Session


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
            [ Server.Request.jsonBodyResult (Json.Decode.field "name" Json.Decode.string)
                |> Server.Request.map
                    (\result ->
                        case result of
                            Ok firstName ->
                                Server.Response.plainText
                                    ("Hello " ++ firstName)

                            Err decodeError ->
                                decodeError
                                    |> Json.Decode.errorToString
                                    |> Server.Response.plainText
                                    |> Server.Response.withStatusCode 400
                    )
            , Server.Request.succeed (Server.Response.plainText "Hello anonymous!")
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
            , Server.Request.expectJsonBody (Json.Decode.field "first" Json.Decode.string)
            , Server.Request.expectQueryParam "first"
            , Server.Request.expectMultiPartFormPost
                (\{ field, optionalField } ->
                    field "first"
                )
            ]
            |> Server.Request.map
                (\firstName ->
                    Server.Response.plainText ("Hello " ++ firstName)
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
                    Server.Response.json
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
                (Server.Response.temporaryRedirect "/")
            )
        )
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "redirect"
        |> ApiRoute.serverRender


noArgs : ApiRoute ApiRoute.Response
noArgs =
    ApiRoute.succeed
        (Server.Request.succeed
            (DataSource.Http.get
                (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> DataSource.map
                    (\stars ->
                        Json.Encode.object
                            [ ( "repo", Json.Encode.string "elm-pages" )
                            , ( "stars", Json.Encode.int stars )
                            ]
                            |> Server.Response.json
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
                (Json.Decode.field "stargazers_count" Json.Decode.int)
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
        (MySession.withSession
            (Server.Request.succeed ())
            (\() sessionResult ->
                DataSource.succeed
                    ( Session.empty
                    , Server.Response.temporaryRedirect "/login"
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
                    (Json.Decode.field "stargazers_count" Json.Decode.int)
                    |> DataSource.map
                        (\stars ->
                            Json.Encode.object
                                [ ( "repo", Json.Encode.string repoName )
                                , ( "stars", Json.Encode.int stars )
                                ]
                                |> Server.Response.json
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
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> DataSource.map
                    (\stars ->
                        Json.Encode.object
                            [ ( "repo", Json.Encode.string repoName )
                            , ( "stars", Json.Encode.int stars )
                            ]
                            |> Server.Response.json
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
                (Json.Decode.field "stargazers_count" Json.Decode.int)
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
