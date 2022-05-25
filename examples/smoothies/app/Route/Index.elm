module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Api.InputObject
import Api.Mutation
import Api.Object.Products
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Data.Cart as Cart exposing (Cart)
import Data.User as User exposing (User)
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
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
import Time
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


type alias Data =
    { smoothies : List Smoothie
    , cart : Maybe Cart
    , user : User
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


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.requestTime
        |> MySession.expectSessionOrRedirect
            (\requestTime session ->
                let
                    maybeUserId : Maybe String
                    maybeUserId =
                        session
                            |> Session.get "userId"
                in
                case maybeUserId of
                    Nothing ->
                        ( session, Route.redirectTo Route.Login )
                            |> DataSource.succeed

                    Just userId ->
                        Request.Hasura.dataSource (requestTime |> Time.posixToMillis |> String.fromInt)
                            (SelectionSet.map3 Data
                                smoothiesSelection
                                (Cart.selection userId)
                                (User.userSelection userId)
                            )
                            |> DataSource.map Response.render
                            |> DataSource.map (Tuple.pair session)
            )


type alias Smoothie =
    { name : String
    , id : Uuid
    , description : String
    , price : Int
    , unsplashImage : String
    }


smoothiesSelection : SelectionSet (List Smoothie) RootQuery
smoothiesSelection =
    Api.Query.products identity
        (SelectionSet.map5 Smoothie
            Api.Object.Products.name
            Api.Object.Products.id
            Api.Object.Products.description
            Api.Object.Products.price
            Api.Object.Products.unsplash_image_id
        )


type Action
    = SignOut
    | UpdateQuantity Uuid Int


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.requestTime
        |> Request.andThen
            (\requestTime ->
                Request.expectFormPost
                    (\{ field } ->
                        Request.oneOf
                            [ Request.map2
                                (\value itemId ->
                                    ( requestTime
                                    , UpdateQuantity (Uuid itemId) (value |> String.toInt |> Maybe.withDefault 1)
                                    )
                                )
                                (field "add")
                                (field "itemId")
                            , Request.map
                                (\_ ->
                                    ( requestTime
                                    , SignOut
                                    )
                                )
                                (field "signout")
                            ]
                    )
            )
        |> MySession.expectSessionOrRedirect
            (\( requestTime, action_ ) session ->
                let
                    userId : String
                    userId =
                        session
                            |> Session.get "userId"
                            |> Maybe.withDefault ""
                in
                case action_ of
                    SignOut ->
                        DataSource.succeed ( Session.empty, Response.temporaryRedirect "login" )

                    UpdateQuantity itemId quantity ->
                        addItemToCart quantity
                            (Uuid userId)
                            itemId
                            |> Request.Hasura.mutationDataSource (requestTime |> Time.posixToMillis |> String.fromInt)
                            |> DataSource.map
                                (\_ -> ( session, Response.render {} ))
            )


addItemToCart : Int -> Uuid -> Uuid -> SelectionSet (Maybe ()) Graphql.Operation.RootMutation
addItemToCart quantity userId itemId =
    Api.Mutation.insert_order_one identity
        { object =
            Api.InputObject.buildOrder_insert_input
                (\opt ->
                    { opt
                        | user_id = Present userId
                        , total = Present 0
                        , order_items =
                            Api.InputObject.buildOrder_item_arr_rel_insert_input
                                { data =
                                    [ Api.InputObject.buildOrder_item_insert_input
                                        (\itemOpts ->
                                            { itemOpts
                                                | product_id = Present itemId
                                                , quantity = Present quantity
                                            }
                                        )
                                    ]
                                }
                                identity
                                |> Present
                    }
                )
        }
        SelectionSet.empty


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.Common.tags


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

            pendingItems : Dict String Int
            pendingItems =
                app.fetchers
                    |> List.filterMap
                        (\pending ->
                            case pending.payload.fields of
                                [ ( "itemId", itemId ), ( "add", addAmount ) ] ->
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
        in
        [ Html.p []
            [ Html.text <| "Welcome " ++ app.data.user.name ++ "!"
            , Html.form
                [ Attr.method "POST"
                , Pages.Msg.onSubmit
                ]
                [ Html.button [ Attr.name "signout" ] [ Html.text "Sign out" ] ]
            ]
        , cartView totals
        , app.data.smoothies
            |> List.map
                (productView cartWithPending)
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
            , Attr.style "padding" "20px"
            , Pages.Msg.fetcherOnSubmit
            ]
            [ Html.input
                [ Attr.type_ "hidden"
                , Attr.name "itemId"
                , item.id |> uuidToString |> Attr.value
                ]
                []
            , Html.button
                [ Attr.type_ "submit"
                , Attr.name "add"
                , Attr.value
                    (quantityInCart - 1 |> String.fromInt)
                ]
                [ Html.text "-" ]
            , Html.p [] [ quantityInCart |> String.fromInt |> Html.text ]
            , Html.button
                [ Attr.type_ "submit"
                , Attr.name "add"
                , Attr.value
                    (quantityInCart + 1 |> String.fromInt)
                ]
                [ Html.text "+" ]
            ]
        , Html.div []
            [ Html.img
                [ Attr.src
                    (item.unsplashImage
                        ++ "?ixlib=rb-1.2.1&raw_url=true&q=80&fm=jpg&crop=entropy&cs=tinysrgb&auto=format&fit=crop&w=600&h=903"
                    )
                , Attr.width 150
                ]
                []
            ]
        ]
