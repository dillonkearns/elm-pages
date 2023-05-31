module Route.Feed__ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Custom
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode exposing (Decoder)
import Json.Encode as Encode
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Story exposing (Item)
import Url.Builder
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { feed : Maybe String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


pages : BackendTask (List RouteParams)
pages =
    BackendTask.succeed []


type alias Data =
    { stories : List Item
    , currentPage : Int
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.queryParam "page"
        |> Request.map
            (\maybePage ->
                let
                    currentPage : Int
                    currentPage =
                        maybePage
                            |> Maybe.andThen String.toInt
                            |> Maybe.withDefault 1

                    feed : String
                    feed =
                        --const type = Astro.params.stories || "top";
                        case routeParams.feed |> Maybe.withDefault "top" of
                            "top" ->
                                "news"

                            "new" ->
                                "newest"

                            "show" ->
                                "show"

                            "ask" ->
                                "ask"

                            "job" ->
                                "jobs"

                            _ ->
                                "not-found"

                    getStoriesUrl : String
                    getStoriesUrl =
                        Url.Builder.crossOrigin "https://node-hnapi.herokuapp.com"
                            [ feed ]
                            [ Url.Builder.int "page" currentPage
                            ]

                    getStories : BackendTask (List Item)
                    getStories =
                        BackendTask.Http.get getStoriesUrl
                            (Story.decoder |> Json.Decode.list)
                in
                BackendTask.map2 Data
                    getStories
                    (BackendTask.succeed currentPage)
                    |> BackendTask.map Response.render
            )


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages Hacker News"
        , image =
            { url = [ "images", "icon-png.png" ] |> Path.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "A demo of elm-pages 3 server-rendered routes."
        , locale = Nothing
        , title = title static.routeParams
        }
        |> Seo.website


title : RouteParams -> String
title routeParams =
    (routeParams.feed
        |> Maybe.map (\feedName -> feedName ++ " | ")
        |> Maybe.withDefault ""
    )
        ++ "elm-pages Hacker News"


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = title static.routeParams
    , body =
        [ paginationView static.data.stories static.routeParams static.data.currentPage
        , Html.main_
            [ Attr.class "news-list" ]
            [ static.data.stories
                |> List.map Story.view
                |> Html.ul []
            ]
        ]
    }


paginationView : List Item -> RouteParams -> Int -> Html msg
paginationView stories routeParams page =
    Html.div [ Attr.class "news-view" ]
        [ Html.div [ Attr.class "news-list-nav" ]
            [ if page > 1 then
                Html.a
                    [ Attr.class "page-link"
                    , Attr.href <| (Route.Feed__ routeParams |> Route.toString) ++ "?page=" ++ String.fromInt (page - 1)
                    , Attr.attribute "aria-label" "Previous Page"
                    ]
                    [ Html.text "< prev" ]

              else
                Html.span
                    [ Attr.class "page-link disabled"
                    , Attr.attribute "aria-hidden" "true"
                    ]
                    [ Html.text "< prev" ]
            , Html.span [] [ Html.text <| "page " ++ String.fromInt page ]
            , if List.length stories > 28 then
                Html.a
                    [ Attr.class "page-link"
                    , Attr.href <| (Route.Feed__ routeParams |> Route.toString) ++ "?page=" ++ String.fromInt (page + 1)
                    , Attr.attribute "aria-label" "Next Page"
                    ]
                    [ Html.text "more >" ]

              else
                Html.span
                    [ Attr.class "page-link"
                    , Attr.attribute "aria-hidden" "true"
                    ]
                    [ Html.text "more >" ]
            ]
        ]
