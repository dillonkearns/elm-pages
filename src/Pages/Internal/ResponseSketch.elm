module Pages.Internal.ResponseSketch exposing (ResponseSketch(..))

import Bytes exposing (Bytes)
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Path exposing (Path)


type ResponseSketch data action shared
    = RenderPage data (Maybe action)
    | HotUpdate data shared (Maybe action)
    | Redirect String
    | NotFound { reason : NotFoundReason, path : Path }
    | Action action
