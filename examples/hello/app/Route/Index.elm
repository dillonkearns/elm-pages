module Route.Index exposing (Data, Model, Msg, route)

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Json.Decode as Decode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    { message : String
    }


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed Data
        |> DataSource.andMap
            (DataSource.Http.get "https://example.com/message"
                (Decode.field "message" Decode.string)
            )


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> Path.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Welcome to elm-pages!"
        , locale = Nothing
        , title = "elm-pages is running"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "elm-pages is running"
    , body =
        [ Html.h1 [] [ Html.text "elm-pages is up and running!" ]
        , Html.p []
            [ Html.text <| "The message is: " ++ static.data.message
            ]
        ]
    }
