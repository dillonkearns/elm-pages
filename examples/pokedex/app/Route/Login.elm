module Route.Login exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip ""
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { username : Maybe String
    , flashMessage : Maybe String
    }


form =
    Form.form
        (\bar ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap bar
            , view = ()
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.formData (form |> Form.Handler.init identity)
            |> Request.map (Tuple.mapSecond (Form.toResult >> Result.mapError (\_ -> "Error")))
            |> MySession.withSession
                (\( formResponse, nameResult ) session ->
                    (nameResult
                        |> unpack
                            (\_ ->
                                ( session
                                    |> Result.withDefault Session.empty
                                , Route.redirectTo Route.Greet
                                )
                            )
                            (\name ->
                                ( session
                                    |> Result.withDefault Session.empty
                                    |> Session.insert "name" name
                                    |> Session.withFlash "message" ("Welcome " ++ name ++ "!")
                                , Route.redirectTo Route.Greet
                                )
                            )
                    )
                        |> BackendTask.succeed
                )
        , Request.succeed ()
            |> MySession.withSession
                (\() session ->
                    case session of
                        Ok okSession ->
                            let
                                flashMessage : Maybe String
                                flashMessage =
                                    okSession
                                        |> Session.get "message"
                            in
                            ( okSession
                            , Data
                                (okSession |> Session.get "name")
                                flashMessage
                                |> Response.render
                            )
                                |> BackendTask.succeed

                        _ ->
                            ( Session.empty
                            , { username = Nothing, flashMessage = Nothing }
                                |> Response.render
                            )
                                |> BackendTask.succeed
                )
        ]


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
view app sharedModel =
    { title = "Login"
    , body =
        [ app.data.flashMessage
            |> Maybe.map (\message -> flashView (Ok message))
            |> Maybe.withDefault (Html.p [] [ Html.text "No flash" ])
        , Html.p []
            [ Html.text
                (case app.data.username of
                    Just username ->
                        "Hello " ++ username ++ "!"

                    Nothing ->
                        "You aren't logged in yet."
                )
            ]
        , Html.form
            [ Attr.method "post"
            ]
            [ Html.label
                [ Attr.attribute "htmlFor" "name"
                ]
                [ Html.text "Name"
                , Html.input
                    [ Attr.name "name"
                    , Attr.type_ "text"
                    , Attr.id "name"
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


unpack : (e -> b) -> (a -> b) -> Result e a -> b
unpack errFunc okFunc result =
    case result of
        Ok ok ->
            okFunc ok

        Err err ->
            errFunc err
