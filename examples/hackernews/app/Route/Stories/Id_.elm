module Route.Stories.Id_ exposing (Data, Model, Msg, route)

import DataSource exposing (DataSource)
import DataSource.Http
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Story exposing (Story)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { id : String }


route : StatefulRoute RouteParams Data Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
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
    -> StaticPayload Data RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
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


pages : DataSource (List RouteParams)
pages =
    DataSource.succeed []


type alias Data =
    { story : Story
    }


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed
        (DataSource.Http.get ("https://node-hnapi.herokuapp.com/item/" ++ routeParams.id)
            Story.decoder
            |> DataSource.map
                (\story ->
                    Response.render
                        (Data story)
                )
        )


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
    -> Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    { title = "Story"
    , body =
        [ storyView static.data.story
        ]
    }


storyView : Story -> Html msg
storyView story =
    Html.div
        [ Attr.class "item-view"
        ]
        [ Html.div
            [ Attr.class "item-view-header"
            ]
            [ Html.a
                [ Attr.href (story.url |> Maybe.withDefault "")
                , Attr.target "_blank"
                , Attr.rel "noreferrer"
                ]
                [ Html.h1 []
                    [ Html.text story.title ]
                ]
            , Html.text " ("
            , Html.span
                [ Attr.class "host"
                ]
                [ Html.text story.domain ]
            , Html.text ")"
            , Html.p
                [ Attr.class "meta"
                ]
                [ Html.text <| String.fromInt story.points ++ " points | by "
                , Html.a
                    [ Attr.href <| "/users/" ++ story.user
                    ]
                    [ Html.text story.user
                    ]
                , Html.text <| " " ++ story.time_ago ++ " ago"
                ]
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
            , Html.ul
                [ Attr.class "comment-children"
                ]
                []
            ]
        ]
