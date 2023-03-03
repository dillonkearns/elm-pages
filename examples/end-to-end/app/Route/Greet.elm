module Route.Greet exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip ""
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , init = init
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            }


init :
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app shared =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


type alias Data =
    { username : String
    , requestTime : Time.Posix
    , flashMessage : Maybe String
    }


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.map2 (\a b -> Data a b Nothing)
            (Request.expectQueryParam "name")
            Request.requestTime
            |> Request.map
                (\requestData ->
                    requestData
                        |> Response.render
                        |> Response.withHeader
                            "x-greeting"
                            ("hello there " ++ requestData.username ++ "!")
                        |> BackendTask.succeed
                )
        , Request.requestTime
            |> MySession.expectSessionOrRedirect
                (\requestTime session ->
                    let
                        username : String
                        username =
                            session
                                |> Session.get "name"
                                |> Maybe.withDefault "NONAME"

                        flashMessage : Maybe String
                        flashMessage =
                            session
                                |> Session.get "message"
                    in
                    ( session
                    , { username = username
                      , requestTime = requestTime
                      , flashMessage = flashMessage
                      }
                        |> Response.render
                        |> Response.withHeader
                            "x-greeting"
                            ("hello " ++ username ++ "!")
                    )
                        |> BackendTask.succeed
                )
        ]


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
    { title = "Hello!"
    , body =
        [ app.data.flashMessage
            |> Maybe.map (\message -> flashView (Ok message))
            |> Maybe.withDefault (Html.p [] [ Html.text "No flash" ])
        , Html.text <| "Hello " ++ app.data.username ++ "!"
        , Html.text <| "Requested page at " ++ String.fromInt (Time.posixToMillis app.data.requestTime)
        , Html.div []
            [ Html.form
                -- TODO use client-side form submission
                -- TODO should there be a helper function to easily invoke a form submission to a different route?
                [ Attr.method "post"
                , Attr.action "/logout"
                , PagesMsg.onSubmit |> Attr.fromUnstyled
                ]
                [ Html.button [] [ Html.text "Logout" ] ]
            ]
        ]
    }


flashView : Result String String -> Html msg
flashView message =
    Html.p
        [ Attr.style "background-color" "rgb(163 251 163)"
        ]
        [ Html.text <|
            case message of
                Ok okMessage ->
                    okMessage

                Err error ->
                    "Something went wrong: " ++ error
        ]
