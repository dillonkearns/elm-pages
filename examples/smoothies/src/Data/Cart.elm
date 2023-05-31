module Data.Cart exposing (Cart, CartEntry, addItemToCart, selection)

import Api.InputObject
import Api.Mutation
import Api.Object.Order
import Api.Object.Order_item
import Api.Object.Products
import Api.Object.Users
import Api.Query
import Api.Scalar exposing (Uuid(..))
import Dict exposing (Dict)
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet)


type alias Cart =
    Dict String CartEntry


type alias CartEntry =
    { quantity : Int
    , pricePerItem : Int
    }


selection : String -> SelectionSet (Maybe (Dict String CartEntry)) RootQuery
selection userId =
    Api.Query.users_by_pk { id = Uuid userId }
        (Api.Object.Users.orders
            (\optionals ->
                { optionals
                    | where_ =
                        Api.InputObject.buildOrder_bool_exp
                            (\orderOptionals ->
                                { orderOptionals
                                    | ordered =
                                        Api.InputObject.buildBoolean_comparison_exp
                                            (\compareOptionals ->
                                                { compareOptionals
                                                    | eq_ = Present False
                                                }
                                            )
                                            |> Present
                                }
                            )
                            |> Present
                }
            )
            (Api.Object.Order.order_items identity
                (SelectionSet.map2 Tuple.pair
                    (Api.Object.Order_item.product_id |> SelectionSet.map uuidToString)
                    (SelectionSet.map2 CartEntry
                        Api.Object.Order_item.quantity
                        (Api.Object.Order_item.product Api.Object.Products.price)
                    )
                )
            )
        )
        |> SelectionSet.map (Maybe.map (List.concat >> Dict.fromList))


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


uuidToString : Uuid -> String
uuidToString (Uuid id) =
    id
