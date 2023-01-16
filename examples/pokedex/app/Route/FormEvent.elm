module Route.FormEvent exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Form.FormData exposing (FormData)
import FormDecoder
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    { formAsString : Maybe String
    }


type Msg
    = OnSubmit FormData


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
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
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( { formAsString = Nothing }, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        OnSubmit formAsString ->
            ( { model | formAsString = Just (toString formAsString) }, Effect.none )


toString : FormData -> String
toString formAsString =
    formAsString.fields
        |> List.map (\( key, value ) -> key ++ "=" ++ value)
        |> String.join "\n"


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : BackendTask FatalError Data
data =
    BackendTask.succeed {}


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external ""
            , alt = ""
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = ""
        , locale = Nothing
        , title = "Test case for form event decoder"
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model static =
    { title = "Placeholder"
    , body =
        [ Html.p []
            [ (case model.formAsString of
                Nothing ->
                    "No submission received."

                Just string ->
                    string
              )
                |> Html.text
            ]
        , exampleForm
        ]
    }


exampleForm : Html (Pages.Msg.Msg Msg)
exampleForm =
    Html.form
        [ FormDecoder.formDataOnSubmit
        ]
        [ Html.div []
            [ Html.label []
                [ Html.text "First"
                , Html.input
                    [ Attr.name "first"
                    , Attr.type_ "text"
                    , Attr.value "my-first-name"
                    ]
                    []
                ]
            ]
        , Html.div []
            [ Html.label []
                [ Html.text "Last"
                , Html.input
                    [ Attr.name "last"
                    , Attr.type_ "text"
                    , Attr.value "my-last-name"
                    ]
                    []
                ]
            ]
        , Html.button
            [ Attr.type_ "submit"
            , Attr.name "my-button"
            , Attr.value "hello-from-button"
            ]
            [ Html.text "Submit" ]
        ]
        |> Html.map (OnSubmit >> Pages.Msg.UserMsg)
