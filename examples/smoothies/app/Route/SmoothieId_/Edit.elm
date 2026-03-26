module Route.SmoothieId_.Edit exposing (ActionData, Data, Model, Msg, route)

import Data.Smoothies as Smoothies exposing (Smoothie)
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Handler
import Form.Validation as Validation
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import MySession
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    { smoothieId : String }


type alias NewItem =
    { name : String
    , description : String
    , price : Int
    , imageUrl : String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
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
init app sharedModel =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app sharedModel msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    { smoothie : Smoothie
    }


type alias ActionData =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            Smoothies.find routeParams.smoothieId
                |> BackendTask.map
                    (\maybeSmoothie ->
                        maybeSmoothie
                            |> Maybe.map (Data >> Response.render)
                            |> Maybe.withDefault (Response.errorPage ErrorPage.NotFound)
                    )
                |> BackendTask.map (Tuple.pair session)
        )
        request


type Action
    = Delete
    | Edit EditInfo


type alias EditInfo =
    { name : String, description : String, price : Int, imageUrl : String }


deleteForm : Form.StyledHtmlForm String () data msg
deleteForm =
    Form.form
        { combine = Validation.succeed ()
        , view =
            \formState ->
                [ Html.button
                    [ Attr.style "color" "red"
                    ]
                    [ (if formState.submitting then
                        "Deleting..."

                       else
                        "Delete"
                      )
                        |> Html.text
                    ]
                ]
        }
        |> Form.hiddenKind ( "kind", "delete" ) "Required"


form : Form.StyledHtmlForm String EditInfo Data msg
form =
    Form.form
        (\name description price imageUrl ->
            { combine =
                Validation.succeed EditInfo
                    |> Validation.andMap name
                    |> Validation.andMap description
                    |> Validation.andMap price
                    |> Validation.andMap imageUrl
            , view =
                \formState ->
                    let
                        errorsView field =
                            (if formState.submitAttempted || True then
                                formState.errors
                                    |> Form.errorsForField field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]

                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> Form.FieldView.inputStyled []
                                    ]
                                , errorsView field
                                ]
                    in
                    [ fieldView "Name" name
                    , fieldView "Description" description
                    , fieldView "Price" price
                    , fieldView "Image" imageUrl
                    , Html.button []
                        [ Html.text
                            (if formState.submitting then
                                "Updating..."

                             else
                                "Update"
                            )
                        ]
                    ]
            }
        )
        |> Form.field "name"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> smoothie.name)
            )
        |> Form.field "description"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> smoothie.description)
            )
        |> Form.field "price"
            (Field.int { invalid = \_ -> "Invalid int" }
                |> Field.required "Required"
                |> Field.withMin 1 "Price must be at least $1"
                |> Field.withInitialValue (\{ smoothie } -> smoothie.price)
            )
        |> Form.field "imageUrl"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\{ smoothie } -> smoothie.unsplashImage)
            )
        |> Form.hiddenKind ( "kind", "edit" ) "Required"


formHandlers : Form.Handler.Handler String Action
formHandlers =
    Form.Handler.init (\() -> Delete) deleteForm
        |> Form.Handler.with Edit form


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            case request |> Request.formData formHandlers of
                Just ( _, Form.Valid (Edit okParsed) ) ->
                    Smoothies.update routeParams.smoothieId okParsed
                        |> BackendTask.map
                            (\_ ->
                                ( session
                                , Route.redirectTo Route.Index
                                )
                            )

                Just ( _, Form.Valid Delete ) ->
                    Smoothies.delete routeParams.smoothieId
                        |> BackendTask.map
                            (\_ ->
                                ( session
                                , Route.redirectTo Route.Index
                                )
                            )

                _ ->
                    BackendTask.succeed
                        ( session, Response.render {} )
        )
        request


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Update Item"
    , body =
        [ Html.h2 [] [ Html.text "Update item" ]
        , form
            |> Pages.Form.renderStyledHtml
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                (Form.options "form"
                    |> Form.withInput app.data
                )
                app
        , deleteForm
            |> Pages.Form.renderStyledHtml []
                (Form.options "delete-form")
                app
        ]
    }
