module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Data.Cart as Cart exposing (Cart)
import Data.Smoothies as Smoothie exposing (Smoothie)
import Data.User as User exposing (User)
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Form.Field as Field
import Form.Handler
import Form.Validation as Validation
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import Icon
import MySession
import Pages.ConcurrentSubmission
import Pages.Form
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatefulRoute)
import Seo.Common
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
    {}


type alias Data =
    { smoothies : List Smoothie
    , user : User
    , cart : Maybe Cart
    }


type alias ActionData =
    {}


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


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.Common.tags


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            BackendTask.map3 Data
                Smoothie.all
                (User.find userId)
                (Cart.get userId)
                |> BackendTask.map Response.render
                |> BackendTask.map (Tuple.pair session)
        )
        request


type Action
    = Signout
    | SetQuantity String Int


signoutForm : Form.StyledHtmlForm String () input msg
signoutForm =
    Form.form
        { combine = Validation.succeed ()
        , view =
            \formState ->
                [ Html.button [] [ Html.text "Sign out" ]
                ]
        }
        |> Form.hiddenKind ( "kind", "signout" ) "Expected signout"


setQuantityForm : Form.StyledHtmlForm String ( String, Int ) ( Int, QuantityChange, Smoothie ) msg
setQuantityForm =
    Form.form
        (\uuid quantity ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap uuid
                    |> Validation.andMap quantity
            , view =
                \formState ->
                    [ Html.button []
                        [ Html.text <|
                            case formState.input of
                                ( _, Decrement, _ ) ->
                                    "-"

                                ( _, Increment, _ ) ->
                                    "+"
                        ]
                    ]
            }
        )
        |> Form.hiddenKind ( "kind", "setQuantity" ) "Expected setQuantity"
        |> Form.hiddenField "itemId"
            (Field.text
                |> Field.required "Required"
                |> Field.withInitialValue (\( _, _, item ) -> item.id)
            )
        |> Form.hiddenField "quantity"
            (Field.int { invalid = \_ -> "Expected int" }
                |> Field.required "Required"
                |> Field.withInitialValue
                    (\( quantityInCart, quantityChange, _ ) ->
                        quantityInCart + toQuantity quantityChange
                    )
                |> Field.withMin 0 "Must be 0 or more"
            )


toQuantity : QuantityChange -> Int
toQuantity quantityChange =
    case quantityChange of
        Increment ->
            1

        Decrement ->
            -1


formHandlers : Form.Handler.Handler String Action
formHandlers =
    Form.Handler.init (\() -> Signout) signoutForm
        |> Form.Handler.with (\( id, qty ) -> SetQuantity id qty) setQuantityForm


action : RouteParams -> Request -> BackendTask FatalError (Response ActionData ErrorPage)
action routeParams request =
    MySession.expectSessionDataOrRedirect (Session.get "userId")
        (\userId session ->
            case request |> Request.formData formHandlers of
                Just ( _, Form.Valid Signout ) ->
                    BackendTask.succeed (Route.redirectTo Route.Login)
                        |> BackendTask.map (Tuple.pair Session.empty)

                Just ( _, Form.Valid (SetQuantity itemId quantity) ) ->
                    Cart.addItemToCart quantity userId itemId
                        |> BackendTask.map (\_ -> Response.render {})
                        |> BackendTask.map (Tuple.pair session)

                _ ->
                    BackendTask.succeed
                        ( session
                        , Response.errorPage (ErrorPage.internalError "Unexpected form data format.")
                        )
        )
        request


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Ctrl-R Smoothies"
    , body =
        let
            pendingItems : Dict String Int
            pendingItems =
                app.concurrentSubmissions
                    |> Dict.values
                    |> List.filterMap
                        (\pending ->
                            case Form.Handler.run pending.payload.fields formHandlers of
                                Form.Valid (SetQuantity itemId addAmount) ->
                                    Just ( itemId, addAmount )

                                _ ->
                                    Nothing
                        )
                    |> Dict.fromList

            cartWithPending : Dict String Cart.CartEntry
            cartWithPending =
                app.data.cart
                    |> Maybe.withDefault Dict.empty
                    |> Dict.map
                        (\itemId entry ->
                            { entry
                                | quantity = Dict.get itemId pendingItems |> Maybe.withDefault entry.quantity
                            }
                        )

            totals : { totalItems : Int, totalPrice : Int }
            totals =
                cartWithPending
                    |> Dict.foldl
                        (\_ { quantity, pricePerItem } soFar ->
                            { soFar
                                | totalItems = soFar.totalItems + quantity
                                , totalPrice = soFar.totalPrice + (quantity * pricePerItem)
                            }
                        )
                        { totalItems = 0, totalPrice = 0 }
        in
        [ Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!"
            , signoutForm
                |> Pages.Form.renderStyledHtml []
                    (Form.options "signout"
                        |> Pages.Form.withConcurrent
                    )
                    app
            ]
        , cartView totals
        , app.data.smoothies
            |> List.map
                (productView app
                    cartWithPending
                )
            |> Html.ul []
        ]
    }


cartView : { totalItems : Int, totalPrice : Int } -> Html msg
cartView totals =
    Html.button [ Attr.class "checkout" ]
        [ Html.span [ Attr.class "icon" ] [ Icon.cart |> Html.fromUnstyled ]
        , Html.text <| " Checkout (" ++ String.fromInt totals.totalItems ++ ") $" ++ String.fromInt totals.totalPrice
        ]


type QuantityChange
    = Increment
    | Decrement


productView : App Data ActionData RouteParams -> Dict String Cart.CartEntry -> Smoothie -> Html (PagesMsg Msg)
productView app cart item =
    let
        quantityInCart : Int
        quantityInCart =
            cart
                |> Dict.get item.id
                |> Maybe.map .quantity
                |> Maybe.withDefault 0
    in
    Html.li [ Attr.class "item" ]
        [ Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Route.SmoothieId___Edit { smoothieId = item.id } |> Route.link [] [ Html.text "Edit" |> Html.toUnstyled ] |> Html.fromUnstyled
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div
            []
            [ setQuantityForm
                |> Pages.Form.renderStyledHtml []
                    (Form.options "decrement-quantity"
                        |> Pages.Form.withConcurrent
                        |> Form.withInput ( quantityInCart, Decrement, item )
                    )
                    app
            , Html.p [] [ quantityInCart |> String.fromInt |> Html.text ]
            , setQuantityForm
                |> Pages.Form.renderStyledHtml []
                    (Form.options "increment-quantity"
                        |> Pages.Form.withConcurrent
                        |> Form.withInput ( quantityInCart, Increment, item )
                    )
                    app
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.unsplashImage ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
