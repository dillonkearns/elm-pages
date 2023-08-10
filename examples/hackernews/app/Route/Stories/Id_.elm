module Route.Stories.Id_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Keyed
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Story exposing (Entry(..), Item(..))
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { id : String }


route : StatefulRoute RouteParams Data ActionData Model Msg
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
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init static sharedModel =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
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
    { story : ( Item, String )
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.allowFatal
        (BackendTask.Http.getJson ("https://node-hnapi.herokuapp.com/item/" ++ routeParams.id)
            (Decode.map2 Tuple.pair
                Story.decoder
                (Decode.field "comments" (Decode.value |> Decode.map (Encode.encode 0)))
            )
            |> BackendTask.map
                (\story ->
                    Response.render
                        (Data story)
                )
        )


head :
    App Data ActionData RouteParams
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
        , title = static.data.story |> Tuple.first |> (\(Item common _) -> common.title)
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view static sharedModel model =
    { title = static.data.story |> Tuple.first |> (\(Item common _) -> common.title)
    , body =
        [ storyView static.data.story
        ]
    }


storyView : ( Item, String ) -> Html msg
storyView ( Item story entry, commentsJson ) =
    Html.div
        [ Attr.class "item-view"
        ]
        [ Html.div
            [ Attr.class "item-view-header"
            ]
            [ Html.a
                [ Attr.href story.url
                , Attr.target "_blank"
                , Attr.rel "noreferrer"
                ]
                [ Html.h1 []
                    [ Html.text story.title ]
                ]
            , Html.text " "
            , Story.domainView story.domain
            , Html.p
                [ Attr.class "meta"
                ]
                ((case entry of
                    Story { points, user } ->
                        [ Html.text <| (String.fromInt points ++ " points | ")
                        , Html.text "by "
                        , Html.a
                            [ Attr.href <|
                                "/users/"
                                    ++ user
                            ]
                            [ Html.text user
                            ]
                        ]

                    _ ->
                        []
                 )
                    ++ [ Html.text <| " " ++ story.time_ago ++ " ago" ]
                )
            ]
        , Html.div
            [ Attr.class "item-view-comments"
            ]
            [ Html.p
                [ Attr.class "item-view-comments-header"
                ]
                [ if story.comments_count > 0 then
                    Html.text <| String.fromInt story.comments_count ++ " comments"

                  else
                    Html.text "No comments yet."
                ]
            , Html.Keyed.ul
                [ Attr.class "comment-children"
                ]
                ((commentsJson
                    |> Decode.decodeString (Decode.list Decode.value)
                    |> Result.withDefault []
                 )
                    |> List.indexedMap
                        (\index comment ->
                            ( String.fromInt index, Html.node "news-comment" [ Attr.property "commentBody" comment ] [] )
                        )
                )
            ]
        ]
