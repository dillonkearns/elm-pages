module Page.Greet exposing (Data, Model, Msg, page)

import CookieParser
import DataSource exposing (DataSource)
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Dict
import Head
import Head.Seo as Seo
import Html
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


data : ServerRequest.IsAvailable -> RouteParams -> DataSource (PageServerResponse Data)
data serverRequestKey routeParams =
    let
        serverReq : ServerRequest (Maybe String)
        serverReq =
            ServerRequest.init identity
                |> ServerRequest.optionalHeader "cookie"
    in
    serverReq
        |> ServerRequest.toDataSource serverRequestKey
        |> DataSource.andThen
            (\cookies ->
                --DataSource.succeed (PageServerResponse.ServerResponse (ServerResponse.temporaryRedirect "/"))
                --DataSource.succeed (PageServerResponse.ServerResponse (ServerResponse.stringBody (foo |> Maybe.withDefault "NOT FOUND")))
                case
                    cookies
                        |> Maybe.withDefault ""
                        |> CookieParser.parse
                        |> Dict.get "username"
                of
                    Just username ->
                        DataSource.succeed
                            (PageServerResponse.RenderPage { username = username })

                    --(PageServerResponse.ServerResponse
                    --    (ServerResponse.stringBody
                    --        "Alright, here's the secret! This is all running with elm-pages serverless :D"
                    --    )
                    --)
                    Nothing ->
                        DataSource.succeed
                            (PageServerResponse.ServerResponse (ServerResponse.temporaryRedirect "/login"))
            )



--DataSource.succeed (PageServerResponse.RenderPage {})


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
    { username : String }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Hello!"
    , body = [ Html.text <| "Hello " ++ static.data.username ++ "!" ]
    }
