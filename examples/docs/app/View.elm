module View exposing (View, map, Static, StaticOnlyData, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt, static, staticView, wrapStaticData, staticBackendTask)

{-|

@docs View, map, Static, StaticOnlyData, staticToHtml, htmlToStatic, embedStatic, renderStatic, adopt, static, staticView, wrapStaticData, staticBackendTask

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Html
import Html.Styled
import View.Static


{-| -}
type alias View msg =
    { title : String
    , body : List (Html.Styled.Html msg)
    }


{-| -}
map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.Styled.map fn) doc.body
    }


{-| Static content type - cannot produce messages (Html Never).
Used for content that is pre-rendered at build time and adopted by virtual-dom.
-}
type alias Static =
    Html.Styled.Html Never


{-| Convert Static content to plain Html for extraction at build time.
-}
staticToHtml : Static -> Html.Html Never
staticToHtml =
    Html.Styled.toUnstyled


{-| Convert plain Html to Static content for adoption at runtime.
-}
htmlToStatic : Html.Html Never -> Static
htmlToStatic =
    Html.Styled.fromUnstyled


{-| Embed static content into a View body.
Since Static is Html Never, it can safely become Html msg.
-}
embedStatic : Static -> Html.Styled.Html msg
embedStatic staticContent =
    Html.Styled.map never staticContent


{-| Render static content with a data-static attribute for extraction.
-}
renderStatic : String -> Static -> Html.Styled.Html msg
renderStatic id staticContent =
    staticContent
        |> staticToHtml
        |> View.Static.render id
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Adopt a static region by ID. This is used by the client-side code after
DCE transformation. On initial load, it adopts pre-rendered DOM. On SPA
navigation, it uses HTML from static-regions.json.
-}
adopt : String -> Static
adopt id =
    View.Static.adopt id
        |> Html.Styled.fromUnstyled


{-| Mark content as static for build-time rendering and client-side adoption.
-}
static : Static -> Html.Styled.Html msg
static content =
    content
        |> staticToHtml
        |> View.Static.static
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Opaque wrapper for data that should only be used in static regions.
-}
type alias StaticOnlyData a =
    View.Static.StaticOnlyData a


{-| Wrap data to mark it as static-only.
-}
wrapStaticData : a -> StaticOnlyData a
wrapStaticData =
    View.Static.wrap


{-| Render static content using static-only data.
-}
staticView : StaticOnlyData a -> (a -> Static) -> Html.Styled.Html msg
staticView staticOnlyData renderFn =
    View.Static.view staticOnlyData (\data -> staticToHtml (renderFn data))
        |> Html.Styled.fromUnstyled
        |> Html.Styled.map never


{-| Create a BackendTask that produces static-only data.
-}
staticBackendTask : BackendTask FatalError a -> BackendTask FatalError (StaticOnlyData a)
staticBackendTask =
    View.Static.backendTask
