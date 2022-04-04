module Pages.Effect exposing (Effect, RequestInfo, batch, custom, fromCmd, map, none, submitPageData)

import Http
import Pages.Internal.Effect as Effect
import Url exposing (Url)


type alias Effect msg userEffect =
    Effect.Effect msg userEffect


batch : List (Effect msg userEffect) -> Effect msg userEffect
batch =
    Effect.Batch


none : Effect.Effect msg userEffect
none =
    Effect.NoEffect


fromCmd cmd =
    -- TODO
    Effect.NoEffect


map : ((msg -> mappedMsg) -> userEffect -> mappedUserEffect) -> (msg -> mappedMsg) -> Effect.Effect msg userEffect -> Effect.Effect mappedMsg mappedUserEffect
map mapFn mapMsg effect =
    case effect of
        Effect.UserEffect userEffect ->
            Effect.UserEffect <|
                mapFn mapMsg userEffect

        Effect.ScrollToTop ->
            Effect.ScrollToTop

        Effect.NoEffect ->
            Effect.NoEffect

        Effect.BrowserLoadUrl string ->
            Effect.BrowserLoadUrl string

        Effect.BrowserPushUrl string ->
            Effect.BrowserPushUrl string

        Effect.FetchPageData maybeRequestInfo url function ->
            Effect.FetchPageData maybeRequestInfo url (\thing -> thing |> function |> mapMsg)

        Effect.Batch effects ->
            effects
                |> List.map (map mapFn mapMsg)
                |> Effect.Batch


custom : userEffect -> Effect msg userEffect
custom =
    Effect.UserEffect


submitPageData : Maybe RequestInfo -> Maybe String -> (Result Http.Error Url -> msg) -> Effect msg userEffect
submitPageData =
    Effect.FetchPageData


type alias RequestInfo =
    { contentType : String
    , body : String
    }
