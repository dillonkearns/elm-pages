module Route.New exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Smoothies as Smoothies
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Dict.Extra
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView as FieldView
import Form.Validation as Validation
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import MySession
import Pages.FormState
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data () ActionData Model Msg
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
    Maybe PageUrl
    -> Shared.Model
    -> App Data () ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data () ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.succeed (BackendTask.succeed (Response.render Data))


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.formData (form |> Form.initCombined identity)
        |> MySession.expectSessionDataOrRedirect (Session.get "userId" >> Maybe.map Uuid)
            (\userId parsed session ->
                case parsed of
                    Ok okParsed ->
                        Smoothies.create okParsed
                            |> Request.Hasura.mutationBackendTask
                            |> BackendTask.map
                                (\_ ->
                                    ( session
                                    , Route.redirectTo Route.Index
                                    )
                                )

                    Err errors ->
                        BackendTask.succeed
                            -- TODO need to render errors here
                            ( session, Response.render {} )
            )


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head static =
    []


form : Form.HtmlForm String NewItem Data Msg
form =
    Form.init
        (\name description price imageUrl ->
            { combine =
                Validation.succeed NewItem
                    |> Validation.andMap name
                    |> Validation.andMap description
                    |> Validation.andMap price
                    |> Validation.andMap imageUrl
            , view =
                \info ->
                    let
                        errors field =
                            info.errors
                                |> Form.errorsForField field

                        errorsView field =
                            (--if field.status == Pages.FormState.Blurred then
                             -- TODO make field.status available through `Validation` type
                             if True then
                                errors field
                                    |> List.map (\error -> Html.li [] [ Html.text error ])

                             else
                                []
                            )
                                |> Html.ul [ Attr.style "color" "red" ]

                        fieldView label field =
                            Html.div []
                                [ Html.label []
                                    [ Html.text (label ++ " ")
                                    , field |> FieldView.input []
                                    ]
                                , errorsView field
                                ]
                    in
                    [ fieldView "Name" name
                    , fieldView "Description" description
                    , fieldView "Price" price
                    , fieldView "Image" imageUrl
                    , Html.button [] [ Html.text "Create" ]
                    ]
            }
        )
        |> Form.field "name" (Field.text |> Field.required "Required")
        |> Form.field "description"
            (Field.text
                |> Field.required "Required"
                |> Field.withClientValidation
                    (\description ->
                        ( Just description
                        , if (description |> String.length) < 5 then
                            [ "Description must be at last 5 characters"
                            ]

                          else
                            []
                        )
                    )
            )
        |> Form.field "price" (Field.int { invalid = \_ -> "Invalid int" } |> Field.required "Required")
        |> Form.field "imageUrl" (Field.text |> Field.required "Required")


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data () ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model app =
    let
        pendingCreation : Result (Dict String (List String)) NewItem
        pendingCreation =
            form
                |> Form.parse "form" app app.data
                |> parseIgnoreErrors
    in
    { title = "New Item"
    , body =
        [ Html.h2 [] [ Html.text "New item" ]
        , form
            |> Form.renderHtml "form"
                [ Attr.style "display" "flex"
                , Attr.style "flex-direction" "column"
                , Attr.style "gap" "20px"
                ]
                -- TODO pass in form response from ActionData
                Nothing
                app
                app.data
        , pendingCreation
            |> Debug.log "pendingCreation"
            |> Result.toMaybe
            |> Maybe.map pendingView
            |> Maybe.withDefault (Html.div [] [])
        ]
    }


type alias NewItem =
    { name : String, description : String, price : Int, imageUrl : String }


toResult : ( Maybe parsed, Dict String (List error) ) -> Result (Dict String (List error)) parsed
toResult ( maybeParsed, fieldErrors ) =
    let
        isEmptyDict : Bool
        isEmptyDict =
            if Dict.isEmpty fieldErrors then
                True

            else
                fieldErrors
                    |> Dict.Extra.any (\_ errors -> List.isEmpty errors)
    in
    case ( maybeParsed, isEmptyDict ) of
        ( Just parsed, True ) ->
            Ok parsed

        _ ->
            Err fieldErrors


parseIgnoreErrors : ( Maybe parsed, Dict String (List error) ) -> Result (Dict String (List error)) parsed
parseIgnoreErrors ( maybeParsed, fieldErrors ) =
    case maybeParsed of
        Just parsed ->
            Ok parsed

        _ ->
            Err fieldErrors


pendingView : NewItem -> Html (PagesMsg Msg)
pendingView item =
    Html.div [ Attr.class "item" ]
        [ Html.h2 [] [ Html.text "Preview" ]
        , Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.imageUrl ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
