module Shared exposing (Data, Model, Msg, template)

import DataSource exposing (DataSource)
import DocsSection
import Effect exposing (Effect)
import Exception exposing (Throwable)
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import TableOfContents
import View exposing (View)
import View.Header


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type Msg
    = OnPageChange
        { path : Path
        , query : Maybe String
        , fragment : Maybe String
        }
    | ToggleMobileMenu
    | IncrementFromChild


type alias Data =
    TableOfContents.TableOfContents TableOfContents.Data


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    }


init :
    Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init flags maybePagePath =
    ( { showMobileMenu = False
      , counter = 0
      }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Effect.none )

        ToggleMobileMenu ->
            ( { model | showMobileMenu = not model.showMobileMenu }, Effect.none )

        IncrementFromChild ->
            ( { model | counter = model.counter + 1 }, Effect.none )


subscriptions : Path -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : DataSource Throwable Data
data =
    TableOfContents.dataSource DocsSection.all


view :
    Data
    ->
        { path : Path
        , route : Maybe Route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : List (Html msg), title : String }
view tableOfContents page model toMsg pageView =
    { body =
        [ ((View.Header.view ToggleMobileMenu 123 page.path
                |> Html.Styled.map toMsg
           )
            :: TableOfContents.view model.showMobileMenu False Nothing tableOfContents
            :: pageView.body
          )
            |> Html.Styled.div []
            |> Html.Styled.toUnstyled
        ]
    , title = pageView.title
    }
