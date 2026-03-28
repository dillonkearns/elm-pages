module RunTests exposing (suite)

import Test exposing (Test, describe, test)
import SmoothieTests
import Test.PagesProgram as PagesProgram


suite : Test
suite =
    describe "Smoothie Tests"
        [ test "loginPageRenders" (\() -> PagesProgram.done SmoothieTests.loginPageRendersTest)
        , test "loginRedirects" (\() -> PagesProgram.done SmoothieTests.loginRedirectsTest)
        , test "smoothieList" (\() -> PagesProgram.done SmoothieTests.smoothieListTest)
        , test "addToCart" (\() -> PagesProgram.done SmoothieTests.addToCartTest)
        , test "optimisticCart" (\() -> PagesProgram.done SmoothieTests.optimisticCartTest)
        , test "concurrentFetchers" (\() -> PagesProgram.done SmoothieTests.concurrentFetchersTest)
        , test "staleFetcherDataReload" (\() -> PagesProgram.done SmoothieTests.staleFetcherDataReloadTest)
        , test "signout" (\() -> PagesProgram.done SmoothieTests.signoutTest)
        ]
