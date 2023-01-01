module Route.Index exposing (Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
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
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask Data
data =
    BackendTask.succeed Data


head :
    StaticPayload Data ActionData RouteParams
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
    -> StaticPayload Data ActionData RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "elm-pages is running"
    , body =
        [ Html.h1 [] [ Html.text "elm-pages is up and running!" ]
        , Html.h2 [] [ Html.text "Learn more" ]
        , Html.ul
            []
            [ Html.li []
                [ Html.a [ Attr.href "https://elm-pages.com/docs/" ] [ Html.text "Framework documentation" ]
                ]
            , Html.li
                []
                [ Html.a [ Attr.href "https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/" ] [ Html.text "Elm package documentation" ]
                ]
            ]
        ]
    }
