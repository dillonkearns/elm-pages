module Route.Logout exposing (Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Dict
import Head
import Head.Seo as Seo
import MySession
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
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


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data))
data routeParams =
    Request.oneOf
        [ MySession.withSession
            (Request.expectFormPost (\_ -> Request.succeed ()))
            (\_ _ ->
                ( Session.empty
                    |> Session.withFlash "message" "You have been successfully logged out."
                , Response.temporaryRedirect "/login"
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


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    View.placeholder "Logout"
