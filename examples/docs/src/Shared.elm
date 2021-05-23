module Shared exposing (Data, Model, Msg, SharedMsg(..), template)

import Browser.Navigation
import DataSource
import DocsSection
import Html exposing (Html)
import Html.Styled
import Json.Decode
import Pages.Flags
import Path exposing (Path)
import SharedTemplate exposing (SharedTemplate)
import TableOfContents
import View exposing (View)
import View.Header


template : SharedTemplate Msg Model Data SharedMsg msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    , sharedMsg = SharedMsg
    }


type Msg
    = OnPageChange
        { path : Path
        , query : Maybe String
        , fragment : Maybe String
        }
    | ToggleMobileMenu
    | SharedMsg SharedMsg


type alias Data =
    TableOfContents.TableOfContents TableOfContents.Data


type SharedMsg
    = IncrementFromChild


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    , navigationKey : Maybe Browser.Navigation.Key
    }


init :
    Maybe Browser.Navigation.Key
    -> Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            }
    -> ( Model, Cmd Msg )
init navigationKey flags maybePagePath =
    let
        _ =
            case flags of
                Pages.Flags.PreRenderFlags ->
                    Nothing

                Pages.Flags.BrowserFlags browserFlags ->
                    browserFlags
                        |> Json.Decode.decodeValue Json.Decode.string
                        |> Result.toMaybe
    in
    ( { showMobileMenu = False
      , counter = 0
      , navigationKey = navigationKey
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Cmd.none )

        ToggleMobileMenu ->
            ( { model | showMobileMenu = not model.showMobileMenu }, Cmd.none )

        SharedMsg globalMsg ->
            case globalMsg of
                IncrementFromChild ->
                    ( { model | counter = model.counter + 1 }, Cmd.none )


subscriptions : Path -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : DataSource.DataSource Data
data =
    --DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
    --    (D.field "stargazers_count" D.int)
    TableOfContents.dataSource DocsSection.all


view :
    Data
    ->
        { path : Path
        , frontmatter : route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : Html msg, title : String }
view tableOfContents page model toMsg pageView =
    { body =
        ((View.Header.view ToggleMobileMenu 123 page.path
            |> Html.Styled.map toMsg
         )
            :: TableOfContents.view model.showMobileMenu False Nothing tableOfContents
            :: pageView.body
        )
            |> Html.Styled.div []
            |> Html.Styled.toUnstyled
    , title = pageView.title
    }
