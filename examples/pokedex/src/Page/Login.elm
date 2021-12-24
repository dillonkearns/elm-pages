module Page.Login exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.SetCookie as SetCookie
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
    Page.serverRender
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Request =
    { cookies : Dict String String
    , maybeFormData : Maybe (Dict String ( String, List String ))
    }


data : ServerRequest.IsAvailable -> RouteParams -> DataSource (PageServerResponse Data)
data serverRequestKey routeParams =
    ServerRequest.init Request
        |> ServerRequest.withCookies
        |> ServerRequest.withFormData
        |> ServerRequest.toDataSource serverRequestKey
        |> DataSource.andThen
            (\{ cookies, maybeFormData } ->
                case maybeFormData of
                    Just formData ->
                        let
                            username : String
                            username =
                                formData
                                    |> Dict.get "name"
                                    |> Maybe.map Tuple.first
                                    |> Maybe.withDefault ""
                        in
                        PageServerResponse.ServerResponse
                            ("/greet"
                                |> ServerResponse.temporaryRedirect
                                |> ServerResponse.withHeader "Set-Cookie"
                                    (SetCookie.setCookie "username" username
                                        |> SetCookie.httpOnly
                                        |> SetCookie.withPath "/"
                                        |> SetCookie.toString
                                    )
                            )
                            |> DataSource.succeed

                    Nothing ->
                        let
                            username : Maybe String
                            username =
                                cookies
                                    |> Dict.get "username"
                        in
                        username
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
            [ Html.label [] [ Html.input [ Attr.name "name", Attr.type_ "text" ] [] ]
            , Html.button
                [ Attr.type_ "submit"
                ]
                [ Html.text "Login" ]
            ]
        ]
    }
