module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.File
import BackendTask.Random
import BackendTask.Time
import DateFormat
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (a, div, text)
import Html.Styled.Attributes as Attr
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Random
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
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
    -> View (PagesMsg Msg)
view maybeUrl sharedModel app =
    { title = "Index page"
    , body =
        [ text "This is the index page."
        , div [] [ text <| "Greeting: " ++ app.data.greeting ]
        , div [] [ text <| "Greeting: " ++ app.data.portGreeting ]
        , div [] [ text <| "Random Data: " ++ Debug.toString app.data.randomTuple ]
        , div []
            [ text <|
                "Now: "
                    ++ DateFormat.format
                        [ DateFormat.monthNameFull
                        , DateFormat.text " "
                        , DateFormat.dayOfMonthSuffix
                        , DateFormat.text ", "
                        , DateFormat.yearNumber
                        , DateFormat.text " @ "
                        , DateFormat.hourFixed
                        , DateFormat.text ":"
                        , DateFormat.minuteFixed
                        , DateFormat.text ":"
                        , DateFormat.secondFixed
                        , DateFormat.amPmLowercase
                        , DateFormat.text " UTC"
                        ]
                        Time.utc
                        app.data.now
            ]
        , div []
            [ a [ Attr.href "/test/response-headers" ] [ text "/test/response-headers" ]
            , a [ Attr.href "/test/basic-auth" ] [ text "/test/basic-auth" ]
            ]
        ]
    }
