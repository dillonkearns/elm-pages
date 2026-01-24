module Route.Hashes exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.File
import BackendTask.Random
import BackendTask.Time
import DateFormat
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (a, div, h2, text)
import Html.Styled.Attributes as Attr exposing (href)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Random
import Route
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Shared
import Time
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    , portGreeting : String
    , randomTuple : ( Int, Float )
    , now : Time.Posix
    }


data : BackendTask FatalError Data
data =
    BackendTask.map4 Data
        (BackendTask.File.rawFile "greeting.txt" |> BackendTask.allowFatal)
        (BackendTask.Custom.run "hello" (Encode.string "Jane") Decode.string |> BackendTask.allowFatal)
        (BackendTask.Random.generate generator)
        BackendTask.Time.now


generator : Random.Generator ( Int, Float )
generator =
    Random.map2 Tuple.pair (Random.int 0 100) (Random.float 0 100)


head :
    App Data () ActionData RouteParams
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


link : List (Html.Styled.Attribute msg) -> List (Html.Styled.Html msg) -> Route.Route -> Html.Styled.Html msg
link attributes children route_ =
    Route.toLink (\anchorAttrs -> a (List.map Attr.fromUnstyled anchorAttrs ++ attributes) children) route_


myDiv : Html.Styled.Html msg
myDiv =
    div [] [ text <| "Hello" ]


heading : String -> Html.Styled.Html msg
heading id =
    h2
        [ Attr.name <| id
        , Attr.id <| id
        ]
        [ a
            [ Attr.href <| "#" ++ id ]
            [ text id ]
        ]


divider =
    div []
        (myDiv
            |> List.repeat 40
        )


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Hash navigation page"
    , body =
        [ heading "a"
        , divider
        , heading "b"
        , divider
        , heading "c"
        , divider
        , heading "d"
        , divider
        , Route.Hashes |> link [] [ text "Top of the page" ]
        ]
    }
