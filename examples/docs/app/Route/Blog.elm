module Route.Blog exposing (ActionData, Data, Model, Msg, route)

import Article
import BackendTask exposing (BackendTask)
import Date
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes as Attr
import Pages.Url
import Route exposing (Route)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import UrlPath
import View exposing (View)


type alias Msg =
    ()


{-| Data type with both persistent fields and ephemeral fields.

  - No persistent fields in this case (just unit)
  - `articles`: Used only inside View.freeze (ephemeral, DCE'd)

-}
type alias Data =
    { articles : List ( Route, Article.ArticleMetadata )
    }


type alias ActionData =
    {}


type alias RouteParams =
    {}


type alias Model =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState
            { view = view
            }


data : BackendTask FatalError Data
data =
    Article.allMetadata
        |> BackendTask.allowFatal
        |> BackendTask.map (\articles -> { articles = articles })


view :
    App Data ActionData {}
    -> Shared.Model
    -> View msg
view app shared =
    { title = "elm-pages blog"
    , body =
        [ div
            [ Attr.class "relative bg-gray-100 min-h-screen pt-16 pb-20 px-4 lg:pt-16 lg:pb-28 lg:px-8 sm:px-6"
            ]
            [ div
                [ Attr.class "absolute inset-0"
                ]
                [ div
                    [ Attr.class "h-1/3 sm:h-2/3"
                    ]
                    []
                ]
            , div
                [ Attr.class "relative max-w-7xl mx-auto"
                ]
                [ -- Frozen header - no data needed
                  View.freeze blogHeader

                -- Frozen blog cards - uses app.data.articles (ephemeral field)
                , View.freeze (renderBlogCards app.data.articles)
                ]
            ]
        ]
    }


{-| Render blog cards as a frozen view.
This code is eliminated from the client bundle via DCE.
-}
renderBlogCards : List ( Route, Article.ArticleMetadata ) -> Html Never
renderBlogCards articles =
    div
        [ Attr.class "mt-12 max-w-lg mx-auto grid gap-5 lg:grid-cols-3 lg:max-w-none"
        ]
        (articles
            |> List.map
                (\articleInfo ->
                    blogCard articleInfo
                )
        )


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
        , description = blogDescription
        , locale = Nothing
        , title = "elm-pages blog"
        }
        |> Seo.website


link : Route.Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route_ attrs children =
    Route.toLink
        (\anchorAttrs ->
            a
                (anchorAttrs ++ attrs)
                children
        )
        route_


blogCard : ( Route, Article.ArticleMetadata ) -> Html msg
blogCard ( route_, info ) =
    link route_
        [ Attr.class "flex flex-col rounded-lg shadow-lg overflow-hidden"
        ]
        [ div
            [ Attr.class "flex-1 bg-white p-6 flex flex-col justify-between"
            ]
            [ div
                [ Attr.class "flex-1"
                ]
                [ span
                    [ Attr.class "block mt-2"
                    ]
                    [ p
                        [ Attr.class "text-xl font-semibold text-gray-900"
                        ]
                        [ text info.title ]
                    , p
                        [ Attr.class "mt-3 text-base text-gray-500"
                        ]
                        [ text info.description ]
                    ]
                ]
            , div
                [ Attr.class "mt-6 flex items-center"
                ]
                [ div
                    []
                    [ div
                        [ Attr.class "flex space-x-1 text-sm text-gray-400"
                        ]
                        [ time
                            [ Attr.datetime "2020-03-16"
                            ]
                            [ text (info.published |> Date.format "MMMM ddd, yyyy") ]
                        ]
                    ]
                ]
            ]
        ]


blogHeader : Html Never
blogHeader =
    div
        [ Attr.class "text-center"
        ]
        [ h2
            [ Attr.class "text-3xl tracking-tight font-extrabold text-gray-900 sm:text-4xl"
            ]
            [ text "Blog" ]
        , p
            [ Attr.class "mt-3 max-w-2xl mx-auto text-xl text-gray-500 sm:mt-4"
            ]
            [ text blogDescription ]
        ]


blogDescription : String
blogDescription =
    "The latest elm-pages news and articles."
