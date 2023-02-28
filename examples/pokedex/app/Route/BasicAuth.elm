module Route.BasicAuth exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Base64
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html exposing (div, text)
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action"
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


type alias ActionData =
    {}


data : RouteParams -> Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    withBasicAuth
        (\{ username, password } ->
            (username == "asdf" && password == "qwer")
                |> BackendTask.succeed
        )
        (Data "Login success!"
            |> Response.render
            |> BackendTask.succeed
        )


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel static =
    { title = "Basic Auth Test"
    , body =
        [ text "Basic Auth Test"
        , div []
            [ text static.data.greeting
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
    -> BackendTask error (Response data ErrorPage)
    -> Parser (BackendTask error (Response data ErrorPage))
withBasicAuth checkAuth successResponse =
    Request.optionalHeader "authorization"
        |> Request.map
            (\base64Auth ->
                case base64Auth |> Maybe.andThen parseAuth of
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
            )


requireBasicAuth : Response data ErrorPage
requireBasicAuth =
    Response.emptyBody
        |> Response.withStatusCode 401
        |> Response.withHeader "WWW-Authenticate" "Basic"
        |> Response.mapError never
