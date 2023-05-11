module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import BackendTask exposing (BackendTask)
import BackendTask.Http
import FatalError exposing (FatalError)
import Html exposing (Html)
import Json.Decode
import Json.Encode
import MySession
import Pages.Manifest as Manifest
import Route exposing (Route)
import Server.Request
import Server.Response
import Server.Session as Session
import Site


routes :
    BackendTask FatalError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ --nonHybridRoute
      --, noArgs
      redirectRoute
    , repoStars

    --, repoStars2
    , logout

    --, greet
    , fileLength
    , BackendTask.succeed manifest |> Manifest.generator Site.canonicalUrl
    ]



--greet : ApiRoute ApiRoute.Response
--greet =
--    ApiRoute.succeed
--        (Server.Request.oneOf
--            [ Server.Request.expectFormPost
--                (\{ field, optionalField } ->
--                    field "first"
--                )
--            , Server.Request.expectJsonBody (Json.Decode.field "first" Json.Decode.string)
--            , Server.Request.expectQueryParam "first"
--            , Server.Request.expectMultiPartFormPost
--                (\{ field, optionalField } ->
--                    field "first"
--                )
--            ]
--            |> Server.Request.map
--                (\firstName ->
--                    Server.Response.plainText ("Hello " ++ firstName)
--                        |> BackendTask.succeed
--                )
--        )
--        |> ApiRoute.literal "api"
--        |> ApiRoute.slash
--        |> ApiRoute.literal "greet"
--        |> ApiRoute.serverRender


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
                        |> BackendTask.succeed
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
            (BackendTask.succeed
                (Route.redirectTo Route.Index)
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
            (BackendTask.Http.getJson
                "https://api.github.com/repos/dillonkearns/elm-pages"
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> BackendTask.allowFatal
                |> BackendTask.map
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
            BackendTask.Http.getJson
                ("https://api.github.com/repos/dillonkearns/" ++ repoName)
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> BackendTask.allowFatal
                |> BackendTask.map
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
                BackendTask.succeed
                    [ route "elm-graphql"
                    ]
            )


logout : ApiRoute ApiRoute.Response
logout =
    ApiRoute.succeed
        (Server.Request.succeed ()
            |> MySession.withSession
                (\() sessionResult ->
                    BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
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
                (BackendTask.Http.getJson
                    ("https://api.github.com/repos/dillonkearns/" ++ repoName)
                    (Json.Decode.field "stargazers_count" Json.Decode.int)
                    |> BackendTask.allowFatal
                    |> BackendTask.map
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
            BackendTask.Http.getJson
                ("https://api.github.com/repos/dillonkearns/" ++ repoName)
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> BackendTask.allowFatal
                |> BackendTask.map
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
                BackendTask.succeed
                    [ route "elm-graphql"
                    , route "elm-pages"
                    ]
            )


route1 =
    ApiRoute.succeed
        (\repoName ->
            BackendTask.Http.getJson
                ("https://api.github.com/repos/dillonkearns/" ++ repoName)
                (Json.Decode.field "stargazers_count" Json.Decode.int)
                |> BackendTask.allowFatal
                |> BackendTask.map
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


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Index |> Route.toPath
        , icons = []
        }
