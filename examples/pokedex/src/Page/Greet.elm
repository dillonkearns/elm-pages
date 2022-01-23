module Page.Greet exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Server.Request as Request exposing (Request)
import Server.Response exposing (Response)
import Session exposing (Session)
import Shared
import Time
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


data : RouteParams -> Request.Request (DataSource (Server.Response.Response Data))
data routeParams =
    Request.oneOf
        [ Request.map2 (\a b -> Data a b Nothing)
            (Request.expectQueryParam "name")
            Request.requestTime
            |> Request.map
                (\requestData ->
                    requestData
                        |> Server.Response.render
                        |> Server.Response.withHeader
                            "x-greeting"
                            ("hello there " ++ requestData.username ++ "!")
                        |> DataSource.succeed
                )
        , MySession.withSession
            Request.requestTime
            (\requestTime session ->
                case session of
                    Ok (Just okSession) ->
                        let
                            username : String
                            username =
                                okSession
                                    |> Dict.get "name"
                                    |> Maybe.withDefault "NONAME"

                            flashMessage : Maybe String
                            flashMessage =
                                okSession
                                    |> Dict.get "message"
                        in
                        ( Session.noUpdates
                        , { username = username
                          , requestTime = requestTime
                          , flashMessage = flashMessage
                          }
                            |> Server.Response.render
                            |> Server.Response.withHeader
                                "x-greeting"
                                ("hello " ++ username ++ "!")
                        )
                            |> DataSource.succeed

                    _ ->
                        ( Session.noUpdates, Server.Response.temporaryRedirect "/login" )
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
    { username : String
    , requestTime : Time.Posix
    , flashMessage : Maybe String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Hello!"
    , body =
        [ static.data.flashMessage
            |> Maybe.map (\message -> flashView (Ok message))
            |> Maybe.withDefault (Html.p [] [ Html.text "No flash" ])
        , Html.text <| "Hello " ++ static.data.username ++ "!"
        , Html.text <| "Requested page at " ++ String.fromInt (Time.posixToMillis static.data.requestTime)
        , Html.div []
            [ Html.form
                [ Attr.method "post"
                , Attr.action "/api/logout"
                ]
                [ Html.button
                    [ Attr.type_ "submit"
                    ]
                    [ Html.text "Logout" ]
                ]
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
