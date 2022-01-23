module Page.Login exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import MySession
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Secrets
import Server.Request as Request
import Server.Response
import Session
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


type alias Request =
    { cookies : Dict String String
    , maybeFormData : Maybe (Dict String ( String, List String ))
    }


data : RouteParams -> Request.Request (DataSource (Server.Response.Response Data))
data routeParams =
    Request.oneOf
        [ MySession.withSession
            (Request.expectFormPost (\{ field } -> field "name"))
            (\name session ->
                ( Session.oneUpdate "name" name
                    |> Session.withFlash "message" ("Welcome " ++ name ++ "!")
                , "/greet"
                    |> Server.Response.temporaryRedirect
                )
                    |> DataSource.succeed
            )
        , MySession.withSession
            (Request.succeed ())
            (\() session ->
                case session of
                    Ok (Just okSession) ->
                        ( Session.oneUpdate "name"
                            (okSession
                                |> Dict.get "name"
                                |> Maybe.withDefault "error"
                            )
                        , okSession
                            |> Dict.get "name"
                            |> Data
                            |> Server.Response.render
                        )
                            |> DataSource.succeed

                    _ ->
                        ( Session.noUpdates
                        , { username = Nothing }
                            |> Server.Response.render
                        )
                            |> DataSource.succeed
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
