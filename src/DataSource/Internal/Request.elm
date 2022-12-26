module DataSource.Internal.Request exposing (request)

import DataSource exposing (DataSource)
import DataSource.Http exposing (Body, Expect)


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> DataSource a
request { name, body, expect } =
    DataSource.Http.uncachedRequest
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect
