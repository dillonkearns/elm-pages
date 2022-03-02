module Page.Index exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.File
import DataSource.Port
import Head
import Head.Seo as Seo
import Html.Styled exposing (div, text)
import Json.Decode as Decode
import Json.Encode as Encode
import Page exposing (Page, PageWithState, StaticPayload)
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


page : Page RouteParams Data
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


type alias Data =
    { greeting : String
    , portGreeting : String
    }


data : DataSource Data
data =
    DataSource.map2 Data
        (DataSource.File.rawFile "greeting.txt")
        (DataSource.Port.get "hello" (Encode.string "Jane") Decode.string)


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
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , div [] [ text <| "Greeting: " ++ static.data.greeting ]
        , div [] [ text <| "Greeting: " ++ static.data.portGreeting ]
        ]
    }
