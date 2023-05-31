module Route.FormEvent exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { formAsString : Maybe String
    }


type Msg
    = OnSubmit --FormData


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
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app shared =
    ( { formAsString = Nothing }, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        OnSubmit ->
            --( { model | formAsString = Just (toString formAsString) }, Effect.none )
            ( model, Effect.none )



--toString : FormData -> String
--toString formAsString =
--    formAsString.fields
--        |> List.map (\( key, value ) -> key ++ "=" ++ value)
--        |> String.join "\n"
--


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : BackendTask FatalError Data
data =
    BackendTask.succeed {}


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
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
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
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


exampleForm : Html (PagesMsg Msg)
exampleForm =
    Html.form
        [--FormDecoder.formDataOnSubmit
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



--|> Html.map (OnSubmit >> PagesMsg.fromMsg)
