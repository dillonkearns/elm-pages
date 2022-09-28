module DataSource.Internal.Request exposing (request)

{-| Build a `DataSource.Http` request (analogous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `DataSource.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [DataSource.Http.get](#get).
-}

import DataSource exposing (DataSource)
import DataSource.Http exposing (Body, Expect)


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> DataSource a
request { name, body, expect } =
    DataSource.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect
