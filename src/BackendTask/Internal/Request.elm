module BackendTask.Internal.Request exposing (request)

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body, Expect)


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> BackendTask error a
request ({ name, body, expect } as params) =
    -- elm-review: known-unoptimized-recursion
    BackendTask.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect
        |> BackendTask.onError
            (\_ ->
                -- TODO avoid crash here, this should be handled as an internal error
                request params
            )
