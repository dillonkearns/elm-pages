module Page.Login exposing (Data, Model, Msg, page)

import CookieParser
import DataSource exposing (DataSource)
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Dict
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import ServerResponse
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.serverless
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Request =
    { cookie : Maybe String
    , body : Maybe String
    , method : ServerRequest.Method
    }


data : ServerRequest.IsAvailable -> RouteParams -> DataSource (PageServerResponse Data)
data serverRequestKey routeParams =
    let
        serverReq : ServerRequest Request
        serverReq =
            ServerRequest.init Request
                |> ServerRequest.optionalHeader "cookie"
                |> ServerRequest.withBody
                |> ServerRequest.withMethod
    in
    serverReq
        |> ServerRequest.toDataSource serverRequestKey
        |> DataSource.andThen
            (\{ cookie, body, method } ->
                --DataSource.succeed (PageServerResponse.ServerResponse (ServerResponse.temporaryRedirect "/"))
                --DataSource.succeed (PageServerResponse.ServerResponse (ServerResponse.stringBody (foo |> Maybe.withDefault "NOT FOUND")))
                case ( method, body ) of
                    ( ServerRequest.Post, Just justBody ) ->
                        let
                            username : String
                            username =
                                justBody |> String.split "=" |> List.reverse |> List.head |> Maybe.withDefault "???"
                        in
                        PageServerResponse.ServerResponse
                            (ServerResponse.temporaryRedirect "/greet"
                                |> ServerResponse.withHeader "Set-Cookie" ("username=" ++ username)
                            )
                            |> DataSource.succeed

                    _ ->
                        cookie
                            |> Maybe.withDefault ""
                            |> CookieParser.parse
                            |> Dict.get "username"
                            |> Data
                            |> PageServerResponse.RenderPage
                            |> DataSource.succeed
            )


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


type alias Data =
    { username : Maybe String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Login"
    , body =
        [ Html.p []
            [ Html.text
                (case static.data.username of
                    Just username ->
                        "Hello " ++ username ++ "!"

                    Nothing ->
                        "You aren't logged in yet."
                )
            ]
        , Html.form
            [ Attr.method "post"
            , Attr.action "/login"
            ]
            [ Html.label []
                [ Html.input
                    [ Attr.name "name"
                    , Attr.type_ "text"
                    ]
                    []
                ]
            , Html.button
                [ Attr.type_ "submit"
                ]
                [ Html.text "Login" ]
            ]
        ]
    }
