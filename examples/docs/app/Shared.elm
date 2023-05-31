module Shared exposing (Data, Model, Msg, template)

import BackendTask exposing (BackendTask)
import DocsSection
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import TableOfContents
import UrlPath exposing (UrlPath)
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
        { path : UrlPath
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
                { path : UrlPath
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


subscriptions : UrlPath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : BackendTask FatalError Data
data =
    TableOfContents.backendTask DocsSection.all


view :
    Data
    ->
        { path : UrlPath
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
