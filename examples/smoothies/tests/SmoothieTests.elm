module SmoothieTests exposing
    ( loginPageRendersTest
    , loginRedirectsTest
    , smoothieListTest
    , addToCartTest
    , optimisticCartTest
    , concurrentFetchersTest
    , staleFetcherDataReloadTest
    , signoutTest
    )

{-| Test suite for the Smoothies shopping cart example.

Showcases full-stack testing of:

  - Data loading via Hasura GraphQL (HTTP simulation)
  - Session auth via signed cookies
  - Form submission (add to cart, sign out)
  - Optimistic UI via concurrentSubmissions

View in browser: elm-pages test-view tests/SmoothieTests.elm

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Query as Query
import Test.Html.Selector as Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


hasuraUrl : String
hasuraUrl =
    "https://loyal-mammal-32.hasura.app/v1/graphql"


{-| GraphQL response for Data.User.login query.
Returns a user ID matching the credentials.
-}
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


{-| GraphQL response for Data.Smoothies.all (selection query).
-}
smoothiesResponse : Encode.Value
smoothiesResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "products"
                  , Encode.list identity
                        [ Encode.object
                            [ ( "name", Encode.string "Pink Berry" )
                            , ( "id", Encode.string "0fa12b1b-55d0-41a4-90a0-9253b76173d2" )
                            , ( "description", Encode.string "Strawberry base, sesame seeds, blueberries, and blackberries." )
                            , ( "price", Encode.int 8 )
                            , ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1506458961255-571f40df5aad" )
                            ]
                        , Encode.object
                            [ ( "name", Encode.string "Green Lime" )
                            , ( "id", Encode.string "e111f139-fd6c-4737-a611-9e0da45af6d3" )
                            , ( "description", Encode.string "Spinach, lime, and almond milk." )
                            , ( "price", Encode.int 7 )
                            , ( "unsplash_image_id", Encode.string "https://images.unsplash.com/flagged/photo-1557753478-b9fb74f39eb5" )
                            ]
                        , Encode.object
                            [ ( "name", Encode.string "Mango Lassi" )
                            , ( "id", Encode.string "64ed3101-49d5-4af1-be15-be83c6477e71" )
                            , ( "description", Encode.string "Fresh mango smoothie with coconut milk." )
                            , ( "price", Encode.int 10 )
                            , ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1619898804188-e7bad4bd2127" )
                            ]
                        , Encode.object
                            [ ( "name", Encode.string "The Kiwi" )
                            , ( "id", Encode.string "6a21dc4d-432f-40f3-866f-49aaa088c936" )
                            , ( "description", Encode.string "Kiwi with mint and cucumber juice." )
                            , ( "price", Encode.int 10 )
                            , ( "unsplash_image_id", Encode.string "https://images.unsplash.com/photo-1610970881699-44a5587cabec" )
                            ]
                        ]
                  )
                ]
          )
        ]


{-| GraphQL response for Data.User.find (users_by_pk query).
-}
userResponse : Encode.Value
userResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "users_by_pk"
                  , Encode.object
                        [ ( "name", Encode.string "Alice" )
                        , ( "username", Encode.string "alice@example.com" )
                        ]
                  )
                ]
          )
        ]


{-| GraphQL response for Data.Cart.get (empty cart).
-}
emptyCartResponse : Encode.Value
emptyCartResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "users_by_pk"
                  , Encode.object
                        [ ( "orders", Encode.list identity [] )
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


{-| GraphQL response for Cart.addItemToCart mutation.
-}
addToCartMutationResponse : Encode.Value
addToCartMutationResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "insert_order_one"
                  , Encode.object [ ( "id", Encode.string "order-1" ) ]
                  )
                ]
          )
        ]


{-| GraphQL response for Smoothies.find (used by addItemToCart to look up price).
-}
findSmoothieResponse : Encode.Value
findSmoothieResponse =
    Encode.object
        [ ( "data"
          , Encode.object
                [ ( "products_by_pk"
                  , Encode.object
                        [ ( "name", Encode.string "Pink Berry" )
                        , ( "id", Encode.string "0fa12b1b-55d0-41a4-90a0-9253b76173d2" )
                        , ( "description", Encode.string "Strawberry base" )
                        , ( "price", Encode.int 8 )
                        , ( "unsplash_image_id", Encode.string "photo.jpg" )
                        ]
                  )
                ]
          )
        ]


baseSetup =
    BackendTaskTest.init
        |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        |> BackendTaskTest.withEnv "SMOOTHIES_HASURA_SECRET" "test-hasura-secret"


{-| Helper: simulate the login action's HTTP (user lookup).
-}
simulateLogin =
    PagesProgram.simulateHttpPost hasuraUrl loginResponse


{-| Helper: simulate the 3 HTTP requests for Index data load
(smoothies, user, cart).
-}
simulateIndexData =
    simulateIndexDataWithCart (Encode.list identity [])


combinedDataResponse : Encode.Value -> Encode.Value
combinedDataResponse cartOrders =
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
                        [ ( "name", Encode.string "Alice" )
                        , ( "username", Encode.string "alice@example.com" )
                        , ( "orders", cartOrders )
                        ]
                  )
                ]
          )
        ]


simulateIndexDataWithCart cartOrders =
    -- BackendTask.map3 batches all 3 queries into a single Request with
    -- concatenated URLs. Each URL resolves from the same response.
    -- But env var lookups happen first (auto-resolve), then HTTP.
    -- With andThen, each BackendTask is: Env.expect -> andThen -> HTTP.
    -- andThen makes them sequential, so there are actually 3 separate HTTP requests.
    -- Provide the combined response for each (the decoder picks its fields).
    let
        resp =
            combinedDataResponse cartOrders
    in
    PagesProgram.simulateHttpPost hasuraUrl resp
        >> PagesProgram.simulateHttpPost hasuraUrl resp
        >> PagesProgram.simulateHttpPost hasuraUrl resp



-- TESTS


{-| 1. Login page renders correctly (no HTTP needed).
-}
loginPageRendersTest : TestApp.ProgramTest
loginPageRendersTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.ensureViewHas [ text "You aren't logged in yet." ]


{-| 2. Login form submission triggers redirect.
-}
loginRedirectsTest : TestApp.ProgramTest
loginRedirectsTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.ensureViewHas [ text "You aren't logged in yet." ]
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        -- Login action does HTTP POST to Hasura for user lookup
        |> simulateLogin
        -- Redirect to Index, which needs HTTP for data (smoothies + user).
        |> simulateIndexData
        -- Should have redirected away from /login
        |> PagesProgram.ensureBrowserUrl
            (\url ->
                if String.contains "/login" url then
                    Expect.fail ("Should have redirected away from /login, but still at: " ++ url)

                else
                    Expect.pass
            )


{-| 3. Full login -> smoothie list with data from Hasura.
-}
smoothieListTest : TestApp.ProgramTest
smoothieListTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        |> PagesProgram.ensureViewHas [ text "Pink Berry" ]
        |> PagesProgram.ensureViewHas [ text "Green Lime" ]
        |> PagesProgram.ensureViewHas [ text "Welcome Alice!" ]


{-| 4. Add to cart: form submission updates cart total.
-}
addToCartTest : TestApp.ProgramTest
addToCartTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        |> PagesProgram.ensureViewHas [ text "Checkout (0)" ]
        -- Click "+" on Pink Berry
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        -- Fetcher action: addItemToCart mutation (HTTP)
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        -- Data reload after fetcher complete (combined response with updated cart)
        |> simulateIndexDataWithCart oneItemOrders
        |> PagesProgram.ensureViewHas [ text "Checkout (1)" ]


{-| 5. THE SHOWCASE TEST: Optimistic UI via concurrentSubmissions.

Click "+" multiple times, verify each click is reflected immediately.
-}
optimisticCartTest : TestApp.ProgramTest
optimisticCartTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        |> PagesProgram.ensureViewHas [ text "Pink Berry" ]
        |> PagesProgram.ensureViewHas [ text "Checkout (0)" ]
        -- Click "+" on Pink Berry
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        |> simulateIndexDataWithCart oneItemOrders
        |> PagesProgram.ensureViewHas [ text "Checkout (1)" ]
        -- Click "+" again
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        |> simulateIndexDataWithCart twoItemOrders
        |> PagesProgram.ensureViewHas [ text "Checkout (2)" ]


{-| Concurrent fetchers: Click "+" twice before resolving either.
Verify the optimistic UI reflects both pending submissions.
-}
concurrentFetchersTest : TestApp.ProgramTest
concurrentFetchersTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        |> PagesProgram.ensureViewHas [ text "Checkout (0)" ]
        -- Click "+" on Pink Berry (triggers fetcher HTTP, but don't resolve)
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        -- Click "+" again immediately, before resolving the first.
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        -- Both fetchers pending. Optimistic UI shows Checkout (2) immediately!
        -- (Second click sees optimistic qty=1, computes 1+1=2)
        |> PagesProgram.ensureViewHas [ text "Checkout (2)" ]
        -- Resolve both fetcher mutations. The first triggers a stale data
        -- reload; the second's mutation response causes the stale resolver to
        -- fail (wrong format) and falls back to fetcher 2, which triggers a
        -- fresh data reload. Only ONE data reload round needed.
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        -- Server confirms 2 items. No intermediate "Checkout (1)" step!
        |> PagesProgram.ensureViewHas [ text "Checkout (2)" ]


{-| Stale data reload cancellation: when two fetchers complete in sequence,
the first data reload is stale and should be cancelled. Only the second
data reload should be needed.

Currently this test requires TWO data reload rounds (one per fetcher).
Once CancelRequest handling is implemented in the test framework, it
should only need ONE data reload round (the second, which supersedes the first).
-}
staleFetcherDataReloadTest : TestApp.ProgramTest
staleFetcherDataReloadTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        -- Click "+" twice
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        |> PagesProgram.within
            (Query.find [ Selector.tag "li", Selector.containing [ text "Pink Berry" ] ])
            (PagesProgram.clickButton "+")
        -- First simulateHttpPost: the stale data reload (dr1) can't use the
        -- mutation response (wrong format), so it falls back to fetcher 2.
        -- Fetcher 2 resolves, triggering a fresh data reload (dr2).
        -- Net effect: one call resolves both the stale dr1 AND fetcher 2.
        -- Both mutations resolved in 2 sims (second via stale fallback).
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        |> PagesProgram.simulateHttpPost hasuraUrl addToCartMutationResponse
        -- One data reload round.
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        |> PagesProgram.simulateHttpPost hasuraUrl (combinedDataResponse twoItemOrders)
        -- Stale cancellation: 2 mutations + 5 data = 7 sims (vs 2+6=8 without).
        |> PagesProgram.ensureViewHas [ text "Checkout (2)" ]


{-| 6. Sign out clears session and redirects to login.
-}
signoutTest : TestApp.ProgramTest
signoutTest =
    TestApp.start "/login" baseSetup
        |> PagesProgram.fillIn "login" "username" "alice@example.com"
        |> PagesProgram.fillIn "login" "password" "password123"
        |> PagesProgram.clickButton "Login"
        |> simulateLogin
        |> simulateIndexData
        |> PagesProgram.ensureViewHas [ text "Welcome Alice!" ]
        -- Click "Sign out"
        |> PagesProgram.clickButton "Sign out"
        -- Should redirect to /login
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/login")
