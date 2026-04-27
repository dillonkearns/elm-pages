module CoffeeFixtures exposing
    ( coffeeId, latteId, espressoId
    , baseSetup, hasuraUrl
    , loginResponse, signupResponse, addToCartMutationResponse
    , combinedDataResponse, indexFor
    , aliceWithEmptyCart, aliceWithLatte, aliceWithTwoLattes
    , bobIndexResponse
    )

{-| Pre-baked test fixtures for the Blendhaus Hasura responses.

Hide the JSON shape so the demo tests stay focused on flow.

-}

import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest


hasuraUrl : String
hasuraUrl =
    "https://loyal-mammal-32.hasura.app/v1/graphql"


baseSetup : BackendTaskTest.TestSetup
baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withEnv "HASURA_ADMIN_SECRET" "test-hasura-secret"



-- Stable, demo-friendly UUIDs


latteId : String
latteId =
    "10000000-0000-0000-0000-000000000001"


espressoId : String
espressoId =
    "10000000-0000-0000-0000-000000000002"


coffeeId : String
coffeeId =
    latteId



-- Auth fixtures


loginResponse : Encode.Value
loginResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "users"
                  , Encode.list identity
                        [ Encode.object [ ( "id", Encode.string "alice-user-id" ) ]
                        ]
                  )
                ]
          )
        ]


signupResponse : Encode.Value
signupResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "insert_users_one"
                  , Encode.object [ ( "id", Encode.string "new-user-id" ) ]
                  )
                ]
          )
        ]



-- Cart fixtures


addToCartMutationResponse : Encode.Value
addToCartMutationResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "insert_coffee_orders_one"
                  , Encode.object [ ( "id", Encode.string "order-1" ) ]
                  )
                ]
          )
        ]



-- Index data: { data: { coffees: [...], users_by_pk: { name, username, coffee_orders: [...] } } }


combinedDataResponse : Encode.Value -> Encode.Value
combinedDataResponse cartOrders =
    indexFor { name = "Alice", username = "alice@blendhaus.com" } cartOrders


indexFor : { name : String, username : String } -> Encode.Value -> Encode.Value
indexFor user cartOrders =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "coffees"
                  , Encode.list identity
                        [ coffeeRow latteId "Café Latte" "Double shot, steamed milk, microfoam" 6 "latte" "Espresso"
                        , coffeeRow espressoId "Espresso" "House blend, pulled short" 4 "espresso" "Espresso"
                        , coffeeRow "10000000-0000-0000-0000-000000000003" "Drip Coffee" "Daily roast, brewed by the cup" 4 "drip" "Brewed"
                        , coffeeRow "10000000-0000-0000-0000-000000000004" "Matcha Latte" "Ceremonial grade, whisked, oat milk" 7 "matcha" "Tea"
                        ]
                  )
                , ( "users_by_pk"
                  , Encode.object
                        [ ( "name", Encode.string user.name )
                        , ( "username", Encode.string user.username )
                        , ( "coffee_orders", cartOrders )
                        ]
                  )
                ]
          )
        ]


coffeeRow : String -> String -> String -> Int -> String -> String -> Encode.Value
coffeeRow id name tagline price variant section =
    Encode.object
        [ ( "id", Encode.string id )
        , ( "name", Encode.string name )
        , ( "tagline", Encode.string tagline )
        , ( "price", Encode.int price )
        , ( "variant", Encode.string variant )
        , ( "section", Encode.string section )
        ]



-- Convenience aliases — the cart-orders shape Hasura returns for the index data response.


aliceWithEmptyCart : Encode.Value
aliceWithEmptyCart =
    Encode.list identity []


aliceWithLatte : Encode.Value
aliceWithLatte =
    cartWith [ ( latteId, 6, 1 ) ]


aliceWithTwoLattes : Encode.Value
aliceWithTwoLattes =
    cartWith [ ( latteId, 6, 2 ) ]


cartWith : List ( String, Int, Int ) -> Encode.Value
cartWith items =
    Encode.list identity
        [ Encode.object
            [ ( "order_items"
              , Encode.list identity
                    (List.map
                        (\( id, price, qty ) ->
                            Encode.object
                                [ ( "coffee_id", Encode.string id )
                                , ( "quantity", Encode.int qty )
                                , ( "coffee", Encode.object [ ( "price", Encode.int price ) ] )
                                ]
                        )
                        items
                    )
              )
            ]
        ]


bobIndexResponse : Encode.Value
bobIndexResponse =
    indexFor { name = "Bob", username = "bob@blendhaus.com" }
        (Encode.list identity [])
