module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Page exposing (Page, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
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


page : Page RouteParams Data
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


data : DataSource Data
data =
    DataSource.succeed {}


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
