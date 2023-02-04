module Route.Posts.Slug_ exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask
import BackendTask.Custom
import Effect
import ErrorPage
import FatalError
import Head
import Html
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Markdown.Block exposing (Block)
import Markdown.Parser
import Markdown.Renderer
import Pages.Msg
import Pages.PageUrl
import Path
import Platform.Sub
import Post
import Route
import RouteBuilder
import Server.Request
import Server.Response
import Shared
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { slug : String }


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


init :
    Maybe Pages.PageUrl.PageUrl
    -> Shared.Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> ( Model, Effect.Effect Msg )
init pageUrl sharedModel app =
    ( {}, Effect.none )


update :
    Pages.PageUrl.PageUrl
    -> Shared.Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect.Effect msg )
update pageUrl sharedModel app msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    Maybe Pages.PageUrl.PageUrl
    -> RouteParams
    -> Path.Path
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Platform.Sub.none


type alias Data =
    { body : List Block
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
        (BackendTask.Custom.run "getPost"
            (Encode.string routeParams.slug)
            (Decode.nullable Post.decoder)
            |> BackendTask.allowFatal
            |> BackendTask.andThen
                (\maybePost ->
                    case maybePost of
                        Just post ->
                            let
                                parsed : Result String (List Block)
                                parsed =
                                    post.body
                                        |> Markdown.Parser.parse
                                        |> Result.mapError (\_ -> "Invalid markdown.")
                            in
                            parsed
                                |> Result.mapError FatalError.fromString
                                |> Result.map
                                    (\parsedMarkdown ->
                                        Server.Response.render
                                            { body = parsedMarkdown
                                            }
                                    )
                                |> BackendTask.fromResult

                        Nothing ->
                            Server.Response.errorPage ErrorPage.NotFound
                                |> BackendTask.succeed
                )
        )


head : RouteBuilder.StaticPayload Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    Maybe Pages.PageUrl.PageUrl
    -> Shared.Model
    -> Model
    -> RouteBuilder.StaticPayload Data ActionData RouteParams
    -> View.View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Posts.Slug_"
    , body =
        [ Html.text "Here is your generated page!!!"
        , Html.div []
            (app.data.body
                |> Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer
                |> Result.withDefault []
            )
        ]
    }


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.succeed (BackendTask.succeed (Server.Response.render {}))
