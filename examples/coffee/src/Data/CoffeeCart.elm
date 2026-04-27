module Data.CoffeeCart exposing (Cart, CartEntry, addItemToCart, get)

{-| Coffee cart — read/write the `coffee_orders` + `coffee_order_items` tables.

The cart is the user's single open (`ordered = false`) coffee order. We model it
as a `Dict` keyed by coffee id so the view can do quick lookups.

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Request.Hasura


type alias Cart =
    Dict String CartEntry


type alias CartEntry =
    { quantity : Int
    , pricePerItem : Int
    }


get : String -> BackendTask FatalError (Maybe Cart)
get userId =
    Request.Hasura.graphqlRequest
        { query = """
            query GetCoffeeCart($userId: uuid!) {
                users_by_pk(id: $userId) {
                    coffee_orders(where: {ordered: {_eq: false}}) {
                        order_items {
                            coffee_id
                            quantity
                            coffee { price }
                        }
                    }
                }
            }
            """
        , variables = [ ( "userId", Encode.string userId ) ]
        , decoder =
            Decode.field "data"
                (Decode.field "users_by_pk"
                    (Decode.nullable
                        (Decode.field "coffee_orders"
                            (Decode.list
                                (Decode.field "order_items" (Decode.list orderItemDecoder))
                            )
                            |> Decode.map (List.concat >> Dict.fromList)
                        )
                    )
                )
        }


orderItemDecoder : Decode.Decoder ( String, CartEntry )
orderItemDecoder =
    Decode.map3 (\coffeeId quantity price -> ( coffeeId, CartEntry quantity price ))
        (Decode.field "coffee_id" Decode.string)
        (Decode.field "quantity" Decode.int)
        (Decode.at [ "coffee", "price" ] Decode.int)


addItemToCart : Int -> String -> String -> BackendTask FatalError ()
addItemToCart quantity userId coffeeId =
    Request.Hasura.graphqlRequest
        { query = """
            mutation AddToCoffeeCart($userId: uuid!, $coffeeId: uuid!, $quantity: Int!) {
                insert_coffee_orders_one(object: {
                    user_id: $userId,
                    total: 0,
                    order_items: {
                        data: [{ coffee_id: $coffeeId, quantity: $quantity }]
                    }
                }) { id }
            }
            """
        , variables =
            [ ( "userId", Encode.string userId )
            , ( "coffeeId", Encode.string coffeeId )
            , ( "quantity", Encode.int quantity )
            ]
        , decoder = Decode.field "data" (Decode.succeed ())
        }
