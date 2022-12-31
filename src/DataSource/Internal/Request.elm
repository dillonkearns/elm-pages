module DataSource.Internal.Request exposing (request)

import DataSource exposing (DataSource)
import DataSource.Http exposing (Body, Expect)


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> DataSource error a
request ({ name, body, expect } as params) =
    -- elm-review: known-unoptimized-recursion
    DataSource.Http.uncachedRequest
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect
        |> DataSource.onError
            (\_ ->
                -- TODO avoid crash here, this should be handled as an internal error
                request params
            )
