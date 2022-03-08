module Route.Login exposing (Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import MySession
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Request =
    { cookies : Dict String String
    , maybeFormData : Maybe (Dict String ( String, List String ))
    }


data : RouteParams -> Request.Parser (DataSource (Server.Response.Response Data))
data routeParams =
    Request.oneOf
        [ MySession.withSession
            (Request.expectFormPost (\{ field } -> field "name"))
            (\name session ->
                ( session
                    |> Result.withDefault Nothing
                    |> Maybe.withDefault Session.empty
                    |> Session.insert "name" name
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
                        ( okSession
                        , okSession
                            |> Session.get "name"
                            |> Data
                            |> Server.Response.render
                        )
                            |> DataSource.succeed

                    _ ->
                        ( Session.empty
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
