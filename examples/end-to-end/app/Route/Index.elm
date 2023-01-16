module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import BackendTask.Port
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
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
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    , portGreeting : String
    }


data : BackendTask FatalError Data
data =
    BackendTask.map2 Data
        (BackendTask.File.rawFile "greeting.txt" |> BackendTask.throw)
        (BackendTask.Port.get "hello" (Encode.string "Jane") Decode.string |> BackendTask.throw)


head :
    StaticPayload Data ActionData RouteParams
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
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , div [] [ text <| "Greeting: " ++ static.data.greeting ]
        , div [] [ text <| "Greeting: " ++ static.data.portGreeting ]
        , div []
            [ a [ Attr.href "/test/response-headers" ] [ text "/test/response-headers" ]
            , a [ Attr.href "/test/basic-auth" ] [ text "/test/basic-auth" ]
            ]
        ]
    }
