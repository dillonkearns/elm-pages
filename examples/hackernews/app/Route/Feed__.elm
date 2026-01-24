module Route.Feed__ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Http
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Story exposing (Item)
import Url.Builder
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { feed : Maybe String
    }


route : StatefulRoute RouteParams Data () ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "No action.")
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init static sharedModel =
    ( {}, Effect.none )


update :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update static sharedModel msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed []


type alias Data =
    { stories : List Item
    , currentPage : Int
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    let
        currentPage : Int
        currentPage =
            Request.queryParam "page" request
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

        getStories : BackendTask FatalError (List Item)
        getStories =
            BackendTask.Http.getJson getStoriesUrl
                (Story.decoder |> Json.Decode.list)
                |> BackendTask.allowFatal
    in
    BackendTask.map2 Data
        getStories
        (BackendTask.succeed currentPage)
        |> BackendTask.map Response.render


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages Hacker News"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
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
    App Data () ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view static sharedModel model =
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
