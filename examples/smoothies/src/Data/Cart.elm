module Data.Cart exposing (Cart, CartEntry, addItemToCart, get)

import BackendTask exposing (BackendTask)
import BackendTask.Http
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


{-| Fetch the cart for a user from Hasura.
Uses a raw GraphQL query since the order/order\_item types
aren't in the current generated schema.
-}
get : String -> BackendTask FatalError (Maybe Cart)
get userId =
    Request.Hasura.graphqlRequest
        { query = """
            query GetCart($userId: uuid!) {
                users_by_pk(id: $userId) {
                    orders(where: {ordered: {_eq: false}}) {
                        order_items {
                            product_id
                            quantity
                            product { price }
                        }
                    }
                }
            }
        """
        , variables =
            [ ( "userId", Encode.string userId ) ]
        , decoder =
            Decode.field "data"
                (Decode.field "users_by_pk"
                    (Decode.nullable
                        (Decode.field "orders"
                            (Decode.list
                                (Decode.field "order_items"
                                    (Decode.list orderItemDecoder)
                                )
                            )
                            |> Decode.map (List.concat >> Dict.fromList)
                        )
                    )
                )
        }


orderItemDecoder : Decode.Decoder ( String, CartEntry )
orderItemDecoder =
    Decode.map3 (\productId quantity price -> ( productId, CartEntry quantity price ))
        (Decode.field "product_id" Decode.string)
        (Decode.field "quantity" Decode.int)
        (Decode.at [ "product", "price" ] Decode.int)


{-| Add an item to the cart via Hasura mutation.
-}
addItemToCart : Int -> String -> String -> BackendTask FatalError ()
addItemToCart quantity userId itemId =
    Request.Hasura.graphqlRequest
        { query = """
            mutation AddToCart($userId: uuid!, $itemId: uuid!, $quantity: Int!) {
                insert_order_one(object: {
                    user_id: $userId,
                    total: 0,
                    order_items: {
                        data: [{ product_id: $itemId, quantity: $quantity }]
                    }
                }) { id }
            }
        """
        , variables =
            [ ( "userId", Encode.string userId )
            , ( "itemId", Encode.string itemId )
            , ( "quantity", Encode.int quantity )
            ]
        , decoder = Decode.field "data" (Decode.succeed ())
        }
