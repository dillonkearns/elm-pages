module Route.Profile exposing (ActionData, Data, Model, Msg, route)

import Data.User as User exposing (User)
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.FormState
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Transition
import Pages.Url
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data () ActionData Model Msg
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


init :
    Maybe PageUrl
    -> Shared.Model
    -> App Data () ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}
    , Effect.SetField
        { formId = "test"
        , name = "name"
        , value = "Testintg"
        }
    )


update :
    PageUrl
    -> Shared.Model
    -> App Data () ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    { user : User
    }


type alias ActionData =
    Result { fields : List ( String, String ), errors : Dict String (List String) } Action


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId () session ->
                User.selection userId
                    |> Request.Hasura.backendTask
                    |> BackendTask.map
                        (\user ->
                            user
                                |> Data
                                |> Response.render
                                |> Tuple.pair session
                        )
            )


type alias Action =
    { username : String
    , name : String
    }


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.skip "No action."


head :
    App Data () ActionData RouteParams
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
        , description = "Update your profile"
        , locale = Nothing
        , title = "Profile"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data () ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model app =
    { title = "Ctrl-R Smoothies"
    , body =
        [ Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!"
            , Html.form
                [ Attr.method "POST"
                , Pages.Msg.onSubmit
                ]
                [ Html.button [ Attr.name "kind", Attr.value "signout" ] [ Html.text "Sign out" ] ]
            ]
        , Route.Profile__Edit
            |> Route.link []
                [ Html.text <|
                    "Edit"
                ]
        , nameFormView app.data.user app.navigation
        , Html.pre []
            [ app.action
                |> Debug.toString
                |> Html.text
            ]
        ]
    }


nameFormView : User -> Maybe Pages.Transition.Transition -> Html (PagesMsg userMsg)
nameFormView user maybeTransition =
    Html.form
        (Pages.FormState.listeners "test"
            ++ [ Attr.method "POST"
               , Pages.Msg.onSubmit
               ]
        )
        [ Html.fieldset
            []
            [ Html.label []
                [ Html.text "Username: "
                , Html.input
                    [ Attr.name "username"
                    , Attr.readonly True
                    , Attr.value user.username
                    ]
                    []
                ]
            , Html.label []
                [ Html.text "Name: "
                , Html.input
                    [ Attr.name "name"
                    , Attr.readonly True
                    , Attr.value user.name
                    ]
                    []
                ]
            ]
        ]
