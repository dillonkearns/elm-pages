module Page.Secret exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.File
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import Server.Request as Request
import Server.Response
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type Data
    = LoggedIn LoggedInInfo
    | NotLoggedIn


type alias LoggedInInfo =
    { username : String
    , secretNote : String
    }


data : RouteParams -> Request.Request (DataSource (PageServerResponse Data))
data routeParams =
    Request.oneOf
        [ Request.expectCookie "username"
            |> Request.map
                (\username ->
                    username
                        |> LoggedInInfo
                        |> DataSource.succeed
                        |> DataSource.andMap (DataSource.File.rawFile "examples/pokedex/content/secret-note.txt")
                        |> DataSource.map LoggedIn
                        |> DataSource.map PageServerResponse.render
                )
        , Request.succeed
            (NotLoggedIn
                |> DataSource.succeed
                |> DataSource.map PageServerResponse.render
             --"/login"
             --    |> ServerResponse.temporaryRedirect
             --    --|> ServerResponse.withStatusCode 404
             --    |> PageServerResponse.ServerResponse
             --    |> DataSource.succeed
            )
        ]


head :
    StaticPayload Data RouteParams
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
    -> StaticPayload Data RouteParams
    -> View Msg
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
                    , Route.link Route.Login
                        []
                        [ Html.text <| "Login" ]
                    ]
                ]
            }
