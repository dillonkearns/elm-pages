module CoffeeTests exposing (suite)

{-| Test suite for the Blendhaus shop.

Showcases full-stack testing of:

  - Data loading via Hasura GraphQL (HTTP simulation)
  - Session auth via signed cookies
  - Form submissions (sign-in, sign-up, sign-out, add-to-cart)
  - Optimistic UI via concurrentSubmissions

Each test reads as a story. Boilerplate (JSON shapes, login dance) lives in
[`CoffeeFixtures`](CoffeeFixtures) and [`CoffeeSteps`](CoffeeSteps).

View these tests with `elm-pages dev` open at <http://localhost:1234/_tests>.

-}

import CoffeeFixtures
import CoffeeSteps
import Expect
import Json.Encode
import Test.BackendTask exposing (HttpError(..))
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import TestApp


suite : PagesProgram.Test
suite =
    PagesProgram.describe "Blendhaus shop"
        [ PagesProgram.describe "Auth"
            [ PagesProgram.test "signs in and lands on the menu"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Café Latte" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Espresso" ]
                       , PagesProgram.ensureViewHas [ Selector.text "hi, Alice" ]
                       ]
                )
            , PagesProgram.test "signs out and is redirected to /login"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "hi, Alice" ]
                       , PagesProgram.clickButton "sign out"
                       , PagesProgram.ensureBrowserUrl
                            (\url -> url |> Expect.equal "https://localhost:1234/login")
                       ]
                )
            , PagesProgram.test "becomes a member and lands on the menu"
                (TestApp.start "/signup" CoffeeFixtures.baseSetup)
                [ PagesProgram.ensureViewHas [ Selector.text "Create an account" ]
                , PagesProgram.fillIn "signup" "name" "Bob"
                , PagesProgram.fillIn "signup" "username" "bob@blendhaus.com"
                , PagesProgram.fillIn "signup" "password" "secret123"
                , PagesProgram.clickButton "Sign Up"
                , PagesProgram.simulateCustom "hashPassword" (Json.Encode.string "hashed_secret123")
                , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.signupResponse
                , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.bobIndexResponse
                , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.bobIndexResponse
                , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.bobIndexResponse
                , PagesProgram.ensureBrowserUrl
                    (\url -> url |> Expect.equal "https://localhost:1234/")
                , PagesProgram.ensureViewHas [ Selector.text "hi, Bob" ]
                ]
            ]
        , PagesProgram.describe "Cart"
            [ PagesProgram.test "adds a Café Latte to the bag"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 0" ] ]
                    ++ CoffeeSteps.addToCart "Café Latte"
                    ++ CoffeeSteps.simulateIndexDataWithCart CoffeeFixtures.aliceWithLatte
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 1" ] ]
                )
            , PagesProgram.test "shows optimistic Bag count on each click"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 0" ] ]
                    ++ CoffeeSteps.addToCart "Café Latte"
                    ++ CoffeeSteps.simulateIndexDataWithCart CoffeeFixtures.aliceWithLatte
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 1" ] ]
                    ++ CoffeeSteps.addToCart "Café Latte"
                    ++ CoffeeSteps.simulateIndexDataWithCart CoffeeFixtures.aliceWithTwoLattes
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 2" ] ]
                )
            , PagesProgram.test "renders Bag · 2 immediately on two rapid clicks"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 0" ]
                       , PagesProgram.withinFind
                            [ Selector.tag "li", Selector.containing [ Selector.text "Café Latte" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.withinFind
                            [ Selector.tag "li", Selector.containing [ Selector.text "Café Latte" ] ]
                            [ PagesProgram.clickButton "+" ]
                       , PagesProgram.ensureViewHas [ Selector.text "Bag · 2" ]
                       , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.addToCartMutationResponse
                       , PagesProgram.simulateHttpPost CoffeeFixtures.hasuraUrl CoffeeFixtures.addToCartMutationResponse
                       ]
                    ++ CoffeeSteps.simulateIndexDataWithCart CoffeeFixtures.aliceWithTwoLattes
                    ++ [ PagesProgram.ensureViewHas [ Selector.text "Bag · 2" ] ]
                )
            ]
        , PagesProgram.describe "Error pages"
            [ PagesProgram.test "renders the not-found page for unknown URLs"
                (TestApp.start "/login" CoffeeFixtures.baseSetup)
                (CoffeeSteps.login
                    ++ CoffeeSteps.simulateLogin
                    ++ CoffeeSteps.simulateIndexData
                    ++ [ PagesProgram.navigateTo "/no-such-page"
                       , PagesProgram.ensureViewHas [ Selector.text "Page not found" ]
                       ]
                )
            ]
        ]
