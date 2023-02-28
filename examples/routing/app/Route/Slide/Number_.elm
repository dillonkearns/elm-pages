module Route.Slide.Number_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import Browser.Events
import Browser.Navigation
import Effect
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html
import Html.Styled.Attributes exposing (css)
import Json.Decode as Decode
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StaticPayload)
import Shared
import Tailwind.Utilities as Tw
import View exposing (View)


type alias Model =
    ()


type Msg
    = OnKeyPress (Maybe Direction)


type alias RouteParams =
    { number : String }


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.preRender
        { head = head
        , pages =
            List.range 1 3
                |> List.map String.fromInt
                |> List.map RouteParams
                |> BackendTask.succeed
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , init = \_ _ staticPayload -> ( (), Effect.none )
            , update =
                \_ sharedModel static msg model ->
                    case msg of
                        OnKeyPress (Just direction) ->
                            ( model
                            , Effect.none
                            )

                        _ ->
                            ( model, Effect.none )
            , subscriptions =
                \maybePageUrl routeParams path sharedModel model ->
                    Browser.Events.onKeyDown keyDecoder |> Sub.map OnKeyPress
            }


type Direction
    = Left
    | Right


keyDecoder : Decode.Decoder (Maybe Direction)
keyDecoder =
    Decode.map toDirection (Decode.field "key" Decode.string)


toDirection : String -> Maybe Direction
toDirection string =
    case string of
        "ArrowLeft" ->
            Just Left

        "ArrowRight" ->
            Just Right

        _ ->
            Nothing


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    BackendTask.map Data
        (slideBody routeParams)


slideBody : RouteParams -> BackendTask FatalError String
slideBody route_ =
    BackendTask.File.bodyWithoutFrontmatter "slides.md"
        |> BackendTask.allowFatal


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


type alias Data =
    { body : String
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model static =
    { title = "TODO title"
    , body =
        [ Html.div
            [ css
                [ Tw.prose
                , Tw.max_w_lg
                , Tw.px_8
                , Tw.py_6
                ]
            ]
            ((static.data.body |> Html.text)
                :: [ Html.text static.routeParams.number ]
            )
        ]
    }
