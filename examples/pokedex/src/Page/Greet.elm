module Page.Greet exposing (Data, Model, Msg, page)

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
import Time
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


data : ServerRequest.IsAvailable -> RouteParams -> DataSource (PageServerResponse Data)
data serverRequestKey routeParams =
    let
        serverReq : ServerRequest ( Maybe String, Time.Posix )
        serverReq =
            ServerRequest.init Tuple.pair
                |> ServerRequest.optionalHeader "cookie"
                |> ServerRequest.withRequestTime
    in
    serverReq
        |> ServerRequest.toDataSource serverRequestKey
        |> DataSource.andThen
            (\( cookies, requestTime ) ->
                case
                    cookies
                        |> Maybe.withDefault ""
                        |> CookieParser.parse
                        |> Dict.get "username"
                of
                    Just username ->
                        DataSource.succeed
                            (PageServerResponse.RenderPage { username = username, requestTime = requestTime })

                    Nothing ->
                        DataSource.succeed
                            (PageServerResponse.ServerResponse (ServerResponse.temporaryRedirect "/login"))
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
