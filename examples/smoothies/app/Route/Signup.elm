module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action _ request =
    -- TODO: re-implement signup action with file-based data
    BackendTask.succeed (Response.render (ValidationErrors { errors = [ "Not implemented" ], fields = [] }))


validate : Session -> { first : String, email : String } -> ( Session, Response ActionData ErrorPage )
validate session { first, email } =
    if first /= "" && email /= "" then
        ( session
            |> Session.withFlash "message" ("Success! You're all signed up " ++ first)
        , Route.redirectTo Route.Signup
        )

    else
        ( session
        , ValidationErrors
            { errors = [ "Cannot be blank?" ]
            , fields =
                [ ( "first", first )
                , ( "email", email )
                ]
            }
            |> Response.render
        )


init :
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app sharedModel =
    ( {}
    , Effect.none
    )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app sharedModel msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    { flashMessage : Maybe (Result String String)
    }


type ActionData
    = Success { email : String, first : String }
    | ValidationErrors
        { errors : List String
        , fields : List ( String, String )
        }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    request
        |> MySession.withSession
            (\sessionResult ->
                let
                    session : Session
                    session =
                        sessionResult |> Result.withDefault Session.empty

                    flashMessage : Maybe String
                    flashMessage =
                        session |> Session.get "message"
                in
                ( Session.empty
                , Response.render
                    { flashMessage = flashMessage |> Maybe.map Ok }
                )
                    |> BackendTask.succeed
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Signup"
    , body =
        [ Html.p []
            [ case app.action of
                Just (Success { email, first }) ->
                    Html.text <| "Hello " ++ first ++ "!"

                Just (ValidationErrors { errors }) ->
                    errors
                        |> List.map (\error -> Html.li [] [ Html.text error ])
                        |> Html.ul []

                _ ->
                    Html.text ""
            ]
        , flashView app.data.flashMessage
        , Html.form
            [ Attr.method "POST"
            ]
            [ Html.label [] [ Html.text "First", Html.input [ Attr.name "first" ] [] ]
            , Html.label [] [ Html.text "Email", Html.input [ Attr.name "email" ] [] ]
            , Html.input [ Attr.type_ "submit", Attr.value "Signup" ] []
            ]
        ]
    }


flashView : Maybe (Result String String) -> Html msg
flashView message =
    Html.p
        [ Attr.style "background-color" "rgb(163 251 163)"
        ]
        [ Html.text <|
            case message of
                Nothing ->
                    ""

                Just (Ok okMessage) ->
                    okMessage

                Just (Err error) ->
                    "Something went wrong: " ++ error
        ]
