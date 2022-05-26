module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Api.Scalar exposing (Uuid(..))
import Data.Cart as Cart exposing (Cart)
import Data.Smoothies as Smoothie exposing (Smoothie)
import Data.User as User exposing (User)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.SelectionSet as SelectionSet
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Icon
import MySession
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Request.Hasura
import Route
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
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
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
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
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.Common.tags


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId requestTime session ->
                (SelectionSet.map3 Data
                    Smoothie.selection
                    (User.selection userId)
                    (Cart.selection userId)
                    |> Request.Hasura.dataSource requestTime
                    |> DataSource.map
                        Response.render
                )
                    |> DataSource.map (Tuple.pair session)
            )


type Action
    = Signout
    | SetQuantity Uuid Int


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    let
        formParser : Request.Parser Action
        formParser =
            Request.expectFormPost
                (\{ field } ->
                    Request.oneOf
                        [ field "signout" |> Request.map (\_ -> Signout)
                        , Request.map2
                            (\itemId quantityToSet ->
                                SetQuantity (Uuid itemId)
                                    (quantityToSet |> String.toInt |> Maybe.withDefault 1)
                            )
                            (field "itemId")
                            (field "setQuantity")
                        ]
                )
    in
    Request.map2 Tuple.pair
        formParser
        Request.requestTime
        |> MySession.expectSessionDataOrRedirect (Session.get "userId")
            (\userId ( parsedAction, requestTime ) session ->
                case parsedAction of
                    Signout ->
                        DataSource.succeed (Route.redirectTo Route.Login)
                            |> DataSource.map (Tuple.pair Session.empty)

                    SetQuantity itemId quantity ->
                        (Cart.addItemToCart quantity (Uuid userId) itemId
                            |> Request.Hasura.mutationDataSource requestTime
                            |> DataSource.map
                                (\_ -> Response.render {})
                        )
                            |> DataSource.map (Tuple.pair session)
            )


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model app =
    { title = "Ctrl-R Smoothies"
    , body =
        let
            pendingItems : Dict String Int
            pendingItems =
                app.fetchers
                    |> List.filterMap
                        (\pending ->
                            case pending.payload.fields of
                                [ ( "itemId", itemId ), ( "setQuantity", addAmount ) ] ->
                                    Just ( itemId, addAmount |> String.toInt |> Maybe.withDefault 0 )

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
            [ app.fetchers
                |> Debug.toString
                |> Html.text
            ]
        , Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!"
            , Html.form
                [ Attr.method "POST"
                , Pages.Msg.onSubmit
                ]
                [ Html.button [ Attr.name "signout", Attr.value "" ] [ Html.text "Sign out" ] ]
            ]
        , cartView totals
        , app.data.smoothies
            |> List.map
                (productView
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


productView : Dict String Cart.CartEntry -> Smoothie -> Html (Pages.Msg.Msg msg)
productView cart item =
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
            , Html.p [] [ Html.text item.description ]
            , Html.p [] [ "$" ++ String.fromInt item.price |> Html.text ]
            ]
        , Html.form
            [ Attr.method "POST"
            , Pages.Msg.fetcherOnSubmit
            ]
            [ Html.input
                [ Attr.type_ "hidden"
                , Attr.name "itemId"
                , Attr.value (uuidToString item.id)
                ]
                []
            , Html.button [] [ Html.text "-" ]
            , Html.p [] [ quantityInCart |> String.fromInt |> Html.text ]
            , Html.button
                [ Attr.name "setQuantity"
                , Attr.value (quantityInCart + 1 |> String.fromInt)
                ]
                [ Html.text "+" ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src (item.unsplashImage ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903") ]
                []
            ]
        ]
