module Route.Test.BasicAuth exposing (ActionData, Data, Model, Msg, route)

import Base64
import DataSource exposing (DataSource)
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Head
import Html.Styled exposing (div, text)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
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


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


data : RouteParams -> Parser (DataSource Throwable (Response Data ErrorPage))
data routeParams =
    withBasicAuth
        (\{ username, password } ->
            (username == "asdf" && password == "qwer")
                |> DataSource.succeed
        )
        (Data "Login success!"
            |> Response.render
            |> DataSource.succeed
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
    -> View (Pages.Msg.Msg Msg)
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
    ({ username : String, password : String } -> DataSource error Bool)
    -> DataSource error (Response data errorPage)
    -> Parser (DataSource error (Response data errorPage))
withBasicAuth checkAuth successResponse =
    Request.optionalHeader "authorization"
        |> Request.map
            (\base64Auth ->
                case base64Auth |> Maybe.andThen parseAuth of
                    Just userPass ->
                        checkAuth userPass
                            |> DataSource.andThen
                                (\authSucceeded ->
                                    if authSucceeded then
                                        successResponse

                                    else
                                        requireBasicAuth |> DataSource.succeed
                                )

                    Nothing ->
                        requireBasicAuth
                            |> DataSource.succeed
            )


requireBasicAuth : Response data errorPage
requireBasicAuth =
    Response.emptyBody
        |> Response.withStatusCode 401
        |> Response.mapError never
        |> Response.withHeader "WWW-Authenticate" "Basic"
