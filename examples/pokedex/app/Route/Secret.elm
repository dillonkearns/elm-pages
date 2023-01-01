module Route.Secret exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
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


type Data
    = LoggedIn LoggedInInfo
    | NotLoggedIn


type alias ActionData =
    {}


type alias LoggedInInfo =
    { username : String
    , secretNote : String
    }


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectCookie "username"
            |> Request.map
                (\username ->
                    username
                        |> LoggedInInfo
                        |> BackendTask.succeed
                        |> BackendTask.andMap (BackendTask.File.rawFile "examples/pokedex/content/secret-note.txt")
                        |> BackendTask.map LoggedIn
                        |> BackendTask.map Response.render
                )
        , Request.succeed
            (NotLoggedIn
                |> BackendTask.succeed
                |> BackendTask.map Response.render
             --"/login"
             --    |> ServerResponse.temporaryRedirect
             --    --|> ServerResponse.withStatusCode 404
             --    |> PageServerResponse.ServerResponse
             --    |> BackendTask.succeed
            )
        ]


head :
    StaticPayload Data ActionData RouteParams
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
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    case static.data of
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
