module DataSource.Internal.Request exposing (request)

import DataSource exposing (DataSource)
import DataSource.Http exposing (Body, Expect)
import Pages.StaticHttpRequest


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> DataSource error a
request { name, body, expect } =
    DataSource.Http.uncachedRequest
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect
        |> DataSource.onError (\_ -> Debug.todo "TODO - unhandled")
