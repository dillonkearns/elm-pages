module Page.FormEvent exposing (Data, Model, Msg, page)

import Browser.Navigation
import DataSource exposing (DataSource)
import FormDecoder
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import Shared
import View exposing (View)


type alias Model =
    { formAsString : Maybe String
    }


type Msg
    = OnSubmit (List ( String, String ))


type alias RouteParams =
    {}


page : PageWithState RouteParams Data Model Msg
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> ( Model, Cmd Msg )
init maybePageUrl sharedModel static =
    ( { formAsString = Nothing }, Cmd.none )


update :
    PageUrl
    -> Maybe Browser.Navigation.Key
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> Msg
    -> Model
    -> ( Model, Cmd Msg )
update pageUrl maybeNavigationKey sharedModel static msg model =
    case msg of
        OnSubmit formAsString ->
            ( { model | formAsString = Just (toString formAsString) }, Cmd.none )


toString : List ( String, String ) -> String
toString formAsString =
    formAsString
        |> List.map (\( key, value ) -> key ++ "=" ++ value)
        |> String.join "\n"


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


data : DataSource Data
data =
    DataSource.succeed {}


head :
    StaticPayload Data RouteParams
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
    -> StaticPayload Data RouteParams
    -> View Msg
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


exampleForm : Html Msg
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
        |> Html.map OnSubmit
