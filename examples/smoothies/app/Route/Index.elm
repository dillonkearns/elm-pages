module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Cart as Cart exposing (Cart)
import Data.Smoothies as Smoothie exposing (Smoothie)
import Data.User as User exposing (User)
import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.Validation as Validation
import Form.Value
import Graphql.SelectionSet as SelectionSet
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Icon
import MySession
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, App)
import Seo.Common
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
    Maybe PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> App Data ActionData RouteParams
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


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.Common.tags


data : RouteParams -> Request.Parser (BackendTask (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId () session ->
                SelectionSet.map3 Data
                    Smoothie.selection
                    (User.selection userId)
                    (Cart.selection userId)
                    |> Request.Hasura.backendTask
                    |> BackendTask.map Response.render
                    |> BackendTask.map (Tuple.pair session)
            )


type Action
    = Signout
    | SetQuantity Uuid Int


signoutForm : Form.HtmlForm String () input Msg
signoutForm =
    Form.init
        { combine = Validation.succeed ()
        , view =
            \formState ->
                [ Html.button [] [ Html.text "Sign out" ]
                ]
        }
        |> Form.hiddenKind ( "kind", "signout" ) "Expected signout"


setQuantityForm : Form.HtmlForm String ( Uuid, Int ) ( Int, QuantityChange, Smoothie ) Msg
setQuantityForm =
    Form.init
        (\uuid quantity ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap (uuid |> Validation.map Uuid)
                    |> Validation.andMap quantity
            , view =
                \formState ->
                    [ Html.button []
                        [ Html.text <|
                            case formState.data of
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
                |> Field.withInitialValue (\( _, _, item ) -> Form.Value.string (uuidToString item.id))
            )
        |> Form.hiddenField "quantity"
            (Field.int { invalid = \_ -> "Expected int" }
                |> Field.required "Required"
                |> Field.withInitialValue
                    (\( quantityInCart, quantityChange, _ ) ->
                        (quantityInCart + toQuantity quantityChange)
                            |> Form.Value.int
                    )
                |> Field.withMin (Form.Value.int 0) "Must be 0 or more"
            )


toQuantity : QuantityChange -> Int
toQuantity quantityChange =
    case quantityChange of
        Increment ->
            1

        Decrement ->
            -1


oneOfParsers : Form.ServerForms String Action
oneOfParsers =
    signoutForm
        |> Form.initCombined (\() -> Signout)
        |> Form.combine (\( uuid, int ) -> SetQuantity uuid int) setQuantityForm


action : RouteParams -> Request.Parser (BackendTask (Response ActionData ErrorPage))
action routeParams =
    Request.formData oneOfParsers
        |> MySession.expectSessionDataOrRedirect (Session.get "userId" >> Maybe.map Uuid)
            (\userId parsedAction session ->
                case parsedAction of
                    Ok Signout ->
                        BackendTask.succeed (Route.redirectTo Route.Login)
                            |> BackendTask.map (Tuple.pair Session.empty)

                    Ok (SetQuantity itemId quantity) ->
                        (Cart.addItemToCart quantity userId itemId
                            |> Request.Hasura.mutationBackendTask
                            |> BackendTask.map
                                (\_ -> Response.render {})
                        )
                            |> BackendTask.map (Tuple.pair session)

                    Err error ->
                        BackendTask.succeed
                            ( session
                            , Response.errorPage (ErrorPage.internalError "Unexpected form data format.")
                            )
            )


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel model app =
    { title = "Ctrl-R Smoothies"
    , body =
        let
            pendingItems : Dict String Int
            pendingItems =
                app.concurrentSubmissions
                    |> Dict.values
                    |> List.filterMap
                        (\pending ->
                            case Form.runOneOfServerSide pending.payload.fields oneOfParsers of
                                ( Just (SetQuantity itemId addAmount), _ ) ->
                                    Just ( uuidToString itemId, addAmount )

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
        [ Html.pre []
            [ app.concurrentSubmissions
                |> Debug.toString
                |> Html.text
            ]
        , Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!"
            , signoutForm
                |> Form.toDynamicFetcher "signout"
                |> Form.renderHtml [] Nothing app ()
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
        [ Html.span [ Attr.class "icon" ] [ Icon.cart ]
        , Html.text <| " Checkout (" ++ String.fromInt totals.totalItems ++ ") $" ++ String.fromInt totals.totalPrice
        ]


uuidToString : Uuid -> String
uuidToString (Uuid id) =
    id


type QuantityChange
    = Increment
    | Decrement


productView : App Data ActionData RouteParams -> Dict String Cart.CartEntry -> Smoothie -> Html (PagesMsg Msg)
productView app cart item =
    let
        quantityInCart : Int
        quantityInCart =
            cart
                |> Dict.get (uuidToString item.id)
                |> Maybe.map .quantity
                |> Maybe.withDefault 0
    in
    Html.li [ Attr.class "item" ]
        [ Html.div []
            [ Html.h3 [] [ Html.text item.name ]
            , Route.SmoothieId___Edit { smoothieId = uuidToString item.id } |> Route.link [] [ Html.text "Edit" ]
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.div
            []
            [ setQuantityForm
                -- TODO should this be toStaticFetcher (don't need the formId here because there is no client-side state, only hidden form fields
                |> Form.toDynamicFetcher "increment-quantity"
                |> Form.renderHtml [] Nothing app ( quantityInCart, Decrement, item )
            , Html.p [] [ quantityInCart |> String.fromInt |> Html.text ]
            , setQuantityForm
                |> Form.toDynamicFetcher "decrement-quantity"
                |> Form.renderHtml [] Nothing app ( quantityInCart, Increment, item )
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.unsplashImage ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
