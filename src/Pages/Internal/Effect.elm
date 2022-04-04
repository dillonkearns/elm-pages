module Pages.Internal.Effect exposing (Effect(..), RequestInfo, maybePerform)

import Http
import Url exposing (Url)


type Effect msg userEffect
    = ScrollToTop
    | NoEffect
    | BrowserLoadUrl String
    | BrowserPushUrl String
    | FetchPageData (Maybe RequestInfo) (Maybe String) (Result Http.Error Url -> msg)
    | Batch (List (Effect msg userEffect))
    | UserEffect userEffect


type alias RequestInfo =
    { contentType : String
    , body : String
    }


maybePerform performUserEffect effect =
    case effect of
        UserEffect userEffect ->
            performUserEffect userEffect
                |> Just

        _ ->
            Nothing
