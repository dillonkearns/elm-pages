module Route.Secret exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.succeed (Response.render {})
        }
        |> RouteBuilder.buildNoState { view = view }


type Data
    = LoggedIn LoggedInInfo
    | NotLoggedIn


type alias ActionData =
    {}


type alias LoggedInInfo =
    { username : String
    , secretNote : String
    }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    case request |> Request.cookie "username" of
        Just username ->
            username
                |> LoggedInInfo
                |> BackendTask.succeed
                |> BackendTask.andMap (BackendTask.File.rawFile "examples/pokedex/content/secret-note.txt" |> BackendTask.allowFatal)
                |> BackendTask.map LoggedIn
                |> BackendTask.map Response.render

        Nothing ->
            NotLoggedIn
                |> BackendTask.succeed
                |> BackendTask.map Response.render


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
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
    -> View (PagesMsg Msg)
view app shared =
    case app.data of
        LoggedIn loggedInInfo ->
            { title = "Secret"
            , body =
                [ Html.main_ [ Attr.style "max-width" "800px" ]
                    [ Html.h1 [] [ Html.text "This is a secret page" ]
                    , Html.p []
                        [ Html.text <| "Welcome, " ++ loggedInInfo.username ++ "!"
                        ]
                    , Html.p []
                        [ Html.text loggedInInfo.secretNote
                        ]
                    ]
                ]
            }

        NotLoggedIn ->
            { title = "Secret"
            , body =
                [ Html.main_ [ Attr.style "max-width" "800px" ]
                    [ Html.h1 [] [ Html.text "You're not logged in" ]
                    , Route.Login
                        |> Route.link
                            []
                            [ Html.text <| "Login" ]
                    ]
                ]
            }
