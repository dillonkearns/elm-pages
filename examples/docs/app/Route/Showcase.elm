module Route.Showcase exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Showcase
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


{-| Data type with ephemeral fields only.

  - `entries`: Used only inside View.freeze (ephemeral, DCE'd)

-}
type alias Data =
    { entries : List Showcase.Entry
    }


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask FatalError Data
data =
    Showcase.staticRequest
        |> BackendTask.map (\entries -> { entries = entries })


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app sharedModel =
    { title = "elm-pages blog"
    , body =
        [ div
            [ Attr.class "flex flex-col pt-8 px-4 lg:px-8 sm:py-20 sm:px-6"
            ]
            [ -- Frozen top section - no data needed
              View.freeze topSection

            -- Frozen entries - uses app.data.entries (ephemeral)
            , View.freeze (renderShowcaseEntries app.data.entries)
            ]
        ]
    }


{-| Render showcase entries as a frozen view.
This code is eliminated from the client bundle via DCE.
-}
renderShowcaseEntries : List Showcase.Entry -> Html Never
renderShowcaseEntries items =
    div
        [ Attr.class "pt-8 flex justify-around"
        ]
        [ showcaseEntries items ]


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "See some neat sites built using elm-pages! (Or submit yours!)"
        , locale = Nothing
        , title = "elm-pages sites showcase"
        }
        |> Seo.website


showcaseEntries : List Showcase.Entry -> Html msg
showcaseEntries items =
    ul
        [ Attr.attribute "role" "list"
        , Attr.class "grid grid-cols-2 gap-x-4 gap-y-8 w-full max-w-screen-lg sm:grid-cols-3 sm:gap-x-6 xl:gap-x-8"
        ]
        (items
            |> List.map showcaseItem
        )


showcaseItem : Showcase.Entry -> Html msg
showcaseItem item =
    li
        [ Attr.class "relative"
        ]
        [ div
            [ Attr.class "block aspect-w-10 aspect-h-7 rounded-lg bg-gray-100 overflow-hidden"
            ]
            [ a
                [ Attr.href item.liveUrl
                , Attr.target "_blank"
                , Attr.rel "noopener"
                ]
                [ img
                    [ Attr.src <| "https://image.thum.io/get/width/800/crop/800/" ++ item.screenshotUrl
                    , Attr.alt ""
                    , Attr.attribute "loading" "lazy"
                    , Attr.class "object-cover pointer-events-none"
                    ]
                    []
                ]
            ]
        , a
            [ Attr.href item.liveUrl
            , Attr.target "_blank"
            , Attr.rel "noopener"
            , Attr.class "mt-2 block text-sm font-medium text-gray-900 truncate"
            ]
            [ text item.displayName ]
        , a
            [ Attr.href item.authorUrl
            , Attr.target "_blank"
            , Attr.rel "noopener"
            , Attr.class "block text-sm font-medium text-gray-500"
            ]
            [ text item.authorName ]
        ]


topSection : Html Never
topSection =
    div
        []
        [ div
            [ Attr.class "max-w-2xl mx-auto text-center py-16 sm:py-20"
            ]
            [ h2
                [ Attr.class "text-3xl font-extrabold sm:text-4xl"
                ]
                [ span
                    [ Attr.class "block"
                    ]
                    [ text "elm-pages Showcase" ]
                ]
            , p
                [ Attr.class "mt-4 text-lg leading-6 text-gray-500"
                ]
                [ text "Check out some projects from the elm-pages community." ]
            , a
                [ Attr.href "https://airtable.com/shrPSenIW2EQqJ083"
                , Attr.target "_blank"
                , Attr.rel "noopener"
                , Attr.class "mt-8 w-full inline-flex items-center justify-center px-5 py-3 border border-transparent text-white font-medium rounded-md bg-blue-800 hover:bg-blue-600 sm:w-auto"
                ]
                [ text "Submit your site to the showcase" ]
            ]
        ]
