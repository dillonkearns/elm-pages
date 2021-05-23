module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import Browser.Navigation
import Css.Global
import DataSource
import Html exposing (Html)
import Html.Styled
import Pages.Flags
import Pages.PagePath exposing (PagePath)
import SharedTemplate exposing (SharedTemplate)
import Tailwind.Utilities
import View exposing (View)


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
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        }
    | SharedMsg SharedMsg


type alias Data =
    ()


type SharedMsg
    = NoOp


type alias Model =
    { showMobileMenu : Bool
    }


init :
    Maybe Browser.Navigation.Key
    -> Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            }
    -> ( Model, Cmd Msg )
init _ flags maybePagePath =
    ( { showMobileMenu = False }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Cmd.none )

        SharedMsg globalMsg ->
            ( model, Cmd.none )


subscriptions : PagePath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : DataSource.DataSource Data
data =
    DataSource.succeed ()


view :
    Data
    ->
        { path : PagePath
        , frontmatter : route
        }
    -> Model
    -> (Msg -> msg)
    -> View Msg
    -> { body : Html msg, title : String }
view stars page model toMsg pageView =
    { body =
        Html.Styled.div []
            (Css.Global.global Tailwind.Utilities.globalStyles
                :: pageView.body
            )
            |> Html.Styled.toUnstyled
    , title = pageView.title
    }
