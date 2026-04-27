module SmoothieTests exposing (suite)

{-| Test suite for the Smoothies shopping cart example.

Showcases full-stack testing of:

  - Data loading via Hasura GraphQL (HTTP simulation)
  - Session auth via signed cookies
  - Form submission (add to cart, sign out)
  - Optimistic UI via concurrentSubmissions

View in browser: elm-pages dev, then open /\_tests

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest exposing (HttpError(..))
import Test.Html.Selector as PSelector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


suite : PagesProgram.Test
suite =
    PagesProgram.describe "Smoothies shopping cart"
        [ PagesProgram.describe "Auth"
            [ PagesProgram.test "signs in and lands on the smoothie list"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Pink Berry" ]
                       , PagesProgram.ensureViewHas [ PSelector.text "Green Lime" ]
                       , PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]
                       ]
                )
            , PagesProgram.test "signs out and redirects to /login"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]
                       , PagesProgram.clickButton "Sign out"
                       , PagesProgram.ensureBrowserUrl
                            (\url -> url |> Expect.equal "https://localhost:1234/login")
                       ]
                )
            , PagesProgram.test "signs up a new account and lands on the index"
                (TestApp.start "/signup" baseSetup)
                [ PagesProgram.ensureViewHas [ PSelector.text "Create an account" ]
                , PagesProgram.fillIn "signup" "name" "Bob"
                , PagesProgram.fillIn "signup" "username" "bob@example.com"
                , PagesProgram.fillIn "signup" "password" "secret123"
                , PagesProgram.clickButton "Sign Up"
                , PagesProgram.simulateCustom "hashPassword" (Encode.string "hashed_secret123")
                , PagesProgram.simulateHttpPost hasuraUrl signupMutationResponse
                , PagesProgram.simulateHttpPost hasuraUrl bobIndexResponse
                , PagesProgram.simulateHttpPost hasuraUrl bobIndexResponse
                , PagesProgram.simulateHttpPost hasuraUrl bobIndexResponse
                , PagesProgram.ensureBrowserUrl
                    (\url -> url |> Expect.equal "https://localhost:1234/")
                , PagesProgram.ensureViewHas [ PSelector.text "Welcome Bob!" ]
                ]
            ]
        , PagesProgram.describe "Cart"
            [ PagesProgram.test "adds an item to the cart"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (0)" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       ]
                    ++ simulateIndexDataWithCart oneItemOrders
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (1)" ] ]
                )
            , PagesProgram.test "shows optimistic cart updates on each click"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Pink Berry" ]
                       , PagesProgram.ensureViewHas [ PSelector.text "Checkout (0)" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       ]
                    ++ simulateIndexDataWithCart oneItemOrders
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (1)" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       ]
                    ++ simulateIndexDataWithCart twoItemOrders
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (2)" ] ]
                )
            , PagesProgram.test "handles concurrent fetcher submissions"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (0)" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.ensureViewHas [ PSelector.text "Checkout (2)" ]
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       ]
                    ++ simulateIndexDataWithCart twoItemOrders
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (2)" ] ]
                )
            , PagesProgram.test "skips stale data reloads from earlier fetchers"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.withinFind
                            [ PSelector.tag "li", PSelector.containing [ text "Pink Berry" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       , PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
                       ]
                    ++ simulateIndexDataWithCart twoItemOrders
                    ++ [ PagesProgram.ensureViewHas [ PSelector.text "Checkout (2)" ] ]
                )
            ]
        , PagesProgram.describe "Error pages"
            [ PagesProgram.test "renders the not-found page for unknown smoothies"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.navigateTo "/non-existent-smoothie-id/edit"
                       , PagesProgram.simulateHttpPost hasuraUrl
                            (Encode.object
                                [ ( "data"
                                  , Encode.object
                                        [ ( "products_by_pk", Encode.null )
                                        ]
                                  )
                                ]
                            )
                       , PagesProgram.ensureViewHas [ PSelector.text "Page not found" ]
                       , PagesProgram.ensureViewHas [ PSelector.text "our menu" ]
                       ]
                )
            , PagesProgram.test "renders the internal-error page on backend failure"
                (TestApp.start "/login" baseSetup)
                (loginSteps
                    ++ simulateLogin
                    ++ simulateIndexData
                    ++ [ PagesProgram.navigateTo "/some-smoothie-id/edit"
                       , PagesProgram.simulateHttpError "POST" hasuraUrl NetworkError
                       , PagesProgram.ensureViewHas [ PSelector.text "Something went wrong" ]
                       ]
                )
            ]
        ]



-- HELPERS


hasuraUrl : String
hasuraUrl =
    "https://loyal-mammal-32.hasura.app/v1/graphql"


baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withEnv "SMOOTHIES_HASURA_SECRET" "test-hasura-secret"


{-| Fill in the login form and submit.
-}
loginSteps =
    [ PagesProgram.fillIn "login" "username" "alice@example.com"
    , PagesProgram.fillIn "login" "password" "password123"
    , PagesProgram.clickButton "Login"
    ]


{-| Simulate the login action's custom port (password hashing) and HTTP (user lookup).
-}
simulateLogin =
    [ PagesProgram.simulateCustom "hashPassword" (Encode.string "hashed_password123")
    , PagesProgram.simulateHttpPost hasuraUrl loginResponse
    ]


{-| Simulate the 3 HTTP requests for Index data load (smoothies, user, cart) with empty cart.
-}
simulateIndexData =
    simulateIndexDataWithCart (Encode.list identity [])


simulateIndexDataWithCart cartOrders =
    let
        resp =
            combinedDataResponse cartOrders
    in
    [ PagesProgram.simulateHttpPost hasuraUrl resp
    , PagesProgram.simulateHttpPost hasuraUrl resp
    , PagesProgram.simulateHttpPost hasuraUrl resp
    ]



-- RESPONSE FIXTURES


loginResponse : Encode.Value
loginResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "users"
                  , Encode.list identity
                        [ Encode.object [ ( "id", Encode.string "user-1" ) ]
                        ]
                  )
                ]
          )
        ]


orderItemJson : Int -> Encode.Value
orderItemJson qty =
    Encode.object
        [ ( "order_items"
          , Encode.list identity
                [ Encode.object
                    [ ( "product_id", Encode.string "0fa12b1b-55d0-41a4-90a0-9253b76173d2" )
                    , ( "quantity", Encode.int qty )
                    , ( "product", Encode.object [ ( "price", Encode.int 8 ) ] )
                    ]
                ]
          )
        ]


oneItemOrders : Encode.Value
oneItemOrders =
    Encode.list identity [ orderItemJson 1 ]


twoItemOrders : Encode.Value
twoItemOrders =
    Encode.list identity [ orderItemJson 2 ]


addToCartMutationResponse : Encode.Value
addToCartMutationResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "insert_orders_one"
                  , Encode.object [ ( "id", Encode.string "order-1" ) ]
                  )
                ]
          )
        ]


combinedDataResponse : Encode.Value -> Encode.Value
combinedDataResponse =
    combinedDataResponseForUser { name = "Alice", username = "alice@example.com" }


combinedDataResponseForUser : { name : String, username : String } -> Encode.Value -> Encode.Value
combinedDataResponseForUser user cartOrders =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "products"
                  , Encode.list identity
                        [ Encode.object [ ( "name", Encode.string "Pink Berry" ), ( "id", Encode.string "0fa12b1b-55d0-41a4-90a0-9253b76173d2" ), ( "description", Encode.string "Strawberry base, sesame seeds, blueberries, and blackberries." ), ( "price", Encode.int 8 ), ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1506458961255-571f40df5aad" ) ]
                        , Encode.object [ ( "name", Encode.string "Green Lime" ), ( "id", Encode.string "e111f139-fd6c-4737-a611-9e0da45af6d3" ), ( "description", Encode.string "Spinach, lime, and almond milk." ), ( "price", Encode.int 7 ), ( "unsplash_image_id", Encode.string "https://images.unsplash.com/flagged/photo-1557753478-b9fb74f39eb5" ) ]
                        , Encode.object [ ( "name", Encode.string "Mango Lassi" ), ( "id", Encode.string "64ed3101-49d5-4af1-be15-be83c6477e71" ), ( "description", Encode.string "Fresh mango smoothie with coconut milk." ), ( "price", Encode.int 10 ), ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1619898804188-e7bad4bd2127" ) ]
                        , Encode.object [ ( "name", Encode.string "The Kiwi" ), ( "id", Encode.string "6a21dc4d-432f-40f3-866f-49aaa088c936" ), ( "description", Encode.string "Kiwi with mint and cucumber juice." ), ( "price", Encode.int 10 ), ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1610970881699-44a5587cabec" ) ]
                        ]
                  )
                , ( "users_by_pk"
                  , Encode.object
                        [ ( "name", Encode.string user.name )
                        , ( "username", Encode.string user.username )
                        , ( "orders", cartOrders )
                        ]
                  )
                ]
          )
        ]


signupMutationResponse : Encode.Value
signupMutationResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "insert_users_one"
                  , Encode.object [ ( "id", Encode.string "new-user-id" ) ]
                  )
                ]
          )
        ]


bobIndexResponse : Encode.Value
bobIndexResponse =
    combinedDataResponseForUser
        { name = "Bob", username = "bob@example.com" }
        (Encode.list identity [])
