module Route.BasicAuth exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Base64
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html exposing (div, text)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "No action.")
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


type alias ActionData =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    request
        |> withBasicAuth
            (\{ username, password } ->
                (username == "asdf" && password == "qwer")
                    |> BackendTask.succeed
            )
            (Data "Login success!"
                |> Response.render
                |> BackendTask.succeed
            )


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head app =
    []


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Basic Auth Test"
    , body =
        [ text "Basic Auth Test"
        , div []
            [ text app.data.greeting
            ]
        ]
    }


parseAuth : String -> Maybe { username : String, password : String }
parseAuth base64Auth =
    case
        base64Auth
            |> String.dropLeft 6
            |> Base64.toString
            |> Maybe.map (String.split ":")
    of
        Just [ username, password ] ->
            Just
                { username = username
                , password = password
                }

        _ ->
            Nothing


withBasicAuth :
    ({ username : String, password : String } -> BackendTask error Bool)
    -> BackendTask error (Response data errorPage)
    -> Request
    -> BackendTask error (Response data errorPage)
withBasicAuth checkAuth successResponse request =
    case request |> Request.header "authorization" |> Maybe.andThen parseAuth of
        Just userPass ->
            checkAuth userPass
                |> BackendTask.andThen
                    (\authSucceeded ->
                        if authSucceeded then
                            successResponse

                        else
                            requireBasicAuth |> BackendTask.succeed
                    )

        Nothing ->
            requireBasicAuth
                |> BackendTask.succeed


requireBasicAuth : Response data errorPage
requireBasicAuth =
    Response.emptyBody
        |> Response.withStatusCode 401
        |> Response.mapError never
        |> Response.withHeader "WWW-Authenticate" "Basic"
