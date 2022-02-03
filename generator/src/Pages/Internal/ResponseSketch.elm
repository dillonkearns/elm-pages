module Pages.Internal.ResponseSketch exposing (ResponseSketch(..))

import Pages.Internal.NotFoundReason exposing (NotFoundReason)


type ResponseSketch data shared
    = RenderPage data
    | HotUpdate data shared
    | Redirect String
    | NotFound { reason : NotFoundReason, path : List String }
