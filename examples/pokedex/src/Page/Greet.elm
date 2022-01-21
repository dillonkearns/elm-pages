module Page.Greet exposing (Data, Model, Msg, page)

import Codec exposing (Codec)
import DataSource exposing (DataSource)
import DataSource.Http
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Json.Decode
import Json.Encode
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Secrets as Secrets
import Pages.Url
import Server.Request as Request exposing (Request)
import Server.Response exposing (Response)
import Server.SetCookie as SetCookie
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


keys =
    { userId = ( "userId", Codec.int )
    }


withSession =
    Session.withSession
        { name = "mysession"
        , secrets =
            Secrets.succeed
                (\secret -> [ secret ])
                |> Secrets.with "SESSION_SECRET"
        , sameSite = "lax"
        }
        (OptimizedDecoder.field "name" OptimizedDecoder.string)


data : RouteParams -> Request.Request (DataSource (Server.Response.Response Data))
data routeParams =
    Request.oneOf
        [ Request.map2 Data
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
        , withSession
            Request.requestTime
            (\requestTime userIdResult ->
                let
                    username =
                        userIdResult
                            |> Result.withDefault "TODO username"
                in
                ( Session.noUpdates
                , { username = username
                  , requestTime = requestTime
                  }
                    |> Server.Response.render
                    |> Server.Response.withHeader
                        "x-greeting"
                        ("hello " ++ username ++ "!")
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
    { username : String
    , requestTime : Time.Posix
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Hello!"
    , body =
        [ Html.text <| "Hello " ++ static.data.username ++ "!"
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
