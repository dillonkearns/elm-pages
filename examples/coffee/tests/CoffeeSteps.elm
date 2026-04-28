module CoffeeSteps exposing
    ( login, simulateLogin, simulateIndexData, simulateIndexDataWithCart
    , addToCart
    )

{-| Pre-baked step lists used by the demo test suite.

Each function returns a `List Step` you can splice into a test. Keeping these
out of the suite file lets the suite read like prose: "log in, then look at
the index, then add to cart".

-}

import CoffeeFixtures exposing (hasuraUrl)
import Json.Encode as Encode
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram


{-| Fill in the login form and press the button. The HTTP simulation comes
afterwards so the test can show "what the action does on the server".
-}
login : List (PagesProgram.Step model msg)
login =
    [ PagesProgram.fillIn "login" "username" "alice@blendhaus.com"
    , PagesProgram.fillIn "login" "password" "password123"
    , PagesProgram.clickButton "Sign in"
    ]


{-| Simulate the password-hash port and the user-lookup HTTP response that
the login `action` needs.
-}
simulateLogin : List (PagesProgram.Step model msg)
simulateLogin =
    [ PagesProgram.simulateCustom "hashPassword" (Encode.string "hashed_password123")
    , PagesProgram.simulateHttpPost hasuraUrl CoffeeFixtures.loginResponse
    ]


{-| The Index `data` function makes three GraphQL requests
(coffees, user, cart). Resolve them with an empty cart.
-}
simulateIndexData : List (PagesProgram.Step model msg)
simulateIndexData =
    simulateIndexDataWithCart CoffeeFixtures.aliceWithEmptyCart


simulateIndexDataWithCart : Encode.Value -> List (PagesProgram.Step model msg)
simulateIndexDataWithCart cartOrders =
    let
        resp =
            CoffeeFixtures.combinedDataResponse cartOrders
    in
    [ PagesProgram.simulateHttpPost hasuraUrl resp
    , PagesProgram.simulateHttpPost hasuraUrl resp
    , PagesProgram.simulateHttpPost hasuraUrl resp
    ]


{-| Click "+" inside the product card whose name matches `coffeeName`.
-}
addToCart : String -> List (PagesProgram.Step model msg)
addToCart coffeeName =
    [ PagesProgram.withinFind
        [ Selector.tag "li", Selector.containing [ Selector.text coffeeName ] ]
        [ PagesProgram.clickButton "+" ]
    , PagesProgram.simulateHttpPost hasuraUrl CoffeeFixtures.addToCartMutationResponse
    ]
