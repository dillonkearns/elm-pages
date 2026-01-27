module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Dict
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import MySession
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session exposing (Session)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp
    | GotResponse (Result Http.Error ActionData)


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


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action _ =
    MySession.withSession
        (Request.skip "TODO")
        --(Request.expectFormPost
        --    (\{ field } ->
        --        Request.map2 Tuple.pair
        --            (field "first")
        --            (field "email")
        --    )
        --)
        (\( first, email ) maybeSession ->
            let
                session : Session
                session =
                    maybeSession |> Result.toMaybe |> Maybe.andThen identity |> Maybe.withDefault Session.empty
            in
            validate session
                { email = email
                , first = first
                }
                |> BackendTask.succeed
        )


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
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , Effect.none
    )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        GotResponse result ->
            let
                _ =
                    Debug.log "GotResponse" result
            in
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
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


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    MySession.withSession
        (Request.succeed ())
        (\() sessionResult ->
            let
                session : Session
                session =
                    sessionResult |> Result.toMaybe |> Maybe.andThen identity |> Maybe.withDefault Session.empty

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
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = "Signup"
    , body =
        [ Html.p []
            [ case static.action of
                Just (Success { email, first }) ->
                    Html.text <| "Hello " ++ first ++ "!"

                Just (ValidationErrors { errors }) ->
                    errors
                        |> List.map (\error -> Html.li [] [ Html.text error ])
                        |> Html.ul []

                _ ->
                    Html.text ""
            ]
        , flashView static.data.flashMessage
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
