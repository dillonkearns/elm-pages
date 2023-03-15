module Route.DarkMode exposing (..)

{-| -}

import BackendTask exposing (BackendTask)
import Css
import Effect
import ErrorPage
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Validation as Validation
import Form.Value as Value
import Head
import Html.Styled as Html
import Html.Styled.Attributes exposing (css)
import PagesMsg exposing (PagesMsg)
import Platform.Sub
import RouteBuilder
import Server.Request
import Server.Response
import Server.Session as Session
import Shared
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


init :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect.Effect Msg )
init app shared =
    ( {}, Effect.none )


update :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect.Effect Msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    routeParams
    -> path
    -> sharedModel
    -> model
    -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    { isDarkMode : Bool
    }


type alias ActionData =
    { formResponse : Form.Response String }


sessionOptions =
    { name = "darkMode"
    , secrets = BackendTask.succeed [ "test" ]
    , options = Nothing
    }


data :
    RouteParams
    -> Server.Request.Parser (BackendTask FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed ()
        |> Session.withSessionResult sessionOptions
            (\() sessionResult ->
                let
                    session : Session.Session
                    session =
                        sessionResult
                            |> Result.withDefault Session.empty

                    isDarkMode : Bool
                    isDarkMode =
                        (session |> Session.get "darkMode") == Just "dark"
                in
                BackendTask.succeed
                    ( session
                    , Server.Response.render
                        { isDarkMode = isDarkMode
                        }
                    )
            )


action :
    RouteParams
    -> Server.Request.Parser (BackendTask FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.formData
        (form
            |> Form.initCombined identity
        )
        |> Session.withSessionResult sessionOptions
            (\( response, formPost ) sessionResult ->
                let
                    setToDarkMode : Bool
                    setToDarkMode =
                        case formPost of
                            Ok ok ->
                                ok

                            Err _ ->
                                False

                    session : Session.Session
                    session =
                        sessionResult
                            |> Result.withDefault Session.empty
                in
                BackendTask.succeed
                    ( session
                        |> Session.insert "darkMode"
                            (if setToDarkMode then
                                "dark"

                             else
                                ""
                            )
                    , Server.Response.render (ActionData response)
                    )
            )


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


form : Form.StyledHtmlForm String Bool Bool Msg
form =
    Form.init
        (\darkMode ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap darkMode
            , view =
                \info ->
                    [ Html.button []
                        [ Html.text <|
                            if info.data then
                                "☀️ To Light Mode"

                            else
                                "️🌒 To Dark Mode"
                        ]
                    ]
            }
        )
        |> Form.hiddenField "darkMode"
            (Field.checkbox
                |> Field.withInitialValue (not >> Value.bool)
            )


view :
    RouteBuilder.App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View.View (PagesMsg Msg)
view app shared model =
    { title = "DarkMode"
    , body =
        [ Html.div
            [ css
                (if app.data.isDarkMode then
                    [ Css.color (Css.hex "aaa")
                    , Css.backgroundColor (Css.hex "000")
                    , Css.height (Css.vh 100)
                    ]

                 else
                    []
                )
            ]
            [ form
                |> Form.toDynamicFetcher
                |> Form.renderStyledHtml "dark-mode" [] (.formResponse >> Just) app app.data.isDarkMode
            , Html.text <|
                "Current mode: "
                    ++ (if app.data.isDarkMode then
                            "Dark Mode"

                        else
                            "Light Mode"
                       )
            ]
        ]
    }
