module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html exposing (Html)
import MySession
import Pages.Manifest as Manifest
import Route exposing (Route)
import Server.Response
import Server.Session as Session


routes :
    BackendTask FatalError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ logout
    ]


logout : ApiRoute ApiRoute.Response
logout =
    ApiRoute.succeed
        (\request ->
            request
                |> MySession.withSession
                    (\session ->
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
