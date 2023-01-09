module ColorHelpers exposing (..)

{-| This is an example to demo Netlify's on-demand builders, adapted from <https://github.com/netlify/example-every-color>.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import Json.Decode as Decode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StaticPayload)
import Server.Response
import Shared
import View exposing (View)


data : routeParams -> BackendTask Throwable (Server.Response.Response Data ErrorPage)
data _ =
    BackendTask.Http.getJson "https://elm-pages-pokedex.netlify.app/.netlify/functions/time"
        Decode.string
        |> BackendTask.throw
        |> BackendTask.map Data
        |> BackendTask.map Server.Response.render


head : (routeParams -> String) -> StaticPayload Data {} routeParams -> List Head.Tag
head toCssValue static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external ""
            , alt = ""
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = ""
        , locale = Nothing
        , title = toCssValue static.routeParams
        }
        |> Seo.website


type alias Data =
    { time : String }


view :
    (routeParams -> String)
    -> Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data {} routeParams
    -> View msg
view toCssVal maybeUrl sharedModel static =
    let
        cssVal : String
        cssVal =
            toCssVal static.routeParams
    in
    { title = "ColorHelpers: " ++ cssVal
    , body =
        [ Html.node "style"
            []
            [ Html.text <| "::root { --selected-color: " ++ cssVal ++ "} body { background-color: " ++ cssVal ++ "}"
            ]
        , Html.main_
            [ Attr.style "background-color" cssVal
            , Attr.class "color-app"
            ]
            [ Html.div
                [ Attr.class "content"
                ]
                [ Html.h1 []
                    [ Html.text <| "ColorHelpers: " ++ cssVal ]
                , Html.p []
                    [ Html.a
                        [ Attr.href "/"
                        ]
                        [ Html.text "← back to home" ]
                    ]
                , Html.p
                    [ Attr.class "timestamp"
                    ]
                    [ Html.text "Generated at:"
                    , Html.br []
                        []
                    , Html.text static.data.time
                    ]
                ]
            ]
        ]
    }
