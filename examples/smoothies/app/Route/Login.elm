module Route.Login exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


userIdMap =
    Dict.fromList
        [ ( "dillon", "2500fcdc-737b-4126-96c2-b3aae64cb5c4" )
        , ( "jane", "a4808f52-d3b0-47b2-a03f-3a56f334865a" )
        ]


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action =
            \_ ->
                MySession.withSession
                    (Request.expectFormPost (\{ field } -> field "userId"))
                    (\username session ->
                        let
                            maybeUserId : Maybe String
                            maybeUserId =
                                userIdMap |> Dict.get username
                        in
                        case maybeUserId of
                            Just userId ->
                                ( session
                                    |> Result.withDefault Nothing
                                    |> Maybe.withDefault Session.empty
                                    |> Session.insert "userId" userId
                                    |> Session.withFlash "message" ("Welcome " ++ username ++ "!")
                                , Route.redirectTo Route.Index
                                )
                                    |> DataSource.succeed

                            Nothing ->
                                ( session
                                    |> Result.withDefault Nothing
                                    |> Maybe.withDefault Session.empty
                                    |> Session.withFlash "message" ("Couldn't find username " ++ username)
                                , Route.redirectTo Route.Login
                                )
                                    |> DataSource.succeed
                    )
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Request =
    { cookies : Dict String String
    , maybeFormData : Maybe (Dict String ( String, List String ))
    }


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    MySession.withSession
        (Request.succeed ())
        (\() session ->
            case session of
                Ok (Just okSession) ->
                    ( okSession
                    , okSession
                        |> Session.get "userId"
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


type alias Data =
    { username : Maybe String
    }


type alias ActionData =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Login"
    , body =
        [ Html.p []
            [ Html.text
                (case static.data.username of
                    Just username ->
                        "Hello! You are already logged in."

                    Nothing ->
                        "You aren't logged in yet."
                )
            ]
        , Html.form
            [ Attr.method "post"
            , Attr.action "/login"
            ]
            [ Html.label [] [ Html.input [ Attr.name "userId", Attr.type_ "text" ] [] ]
            , Html.button
                [ Attr.type_ "submit"
                ]
                [ Html.text "Login" ]
            ]
        ]
    }
