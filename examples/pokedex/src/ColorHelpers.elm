module ColorHelpers exposing (..)

{-| This is an example to demo Netlify's on-demand builders, adapted from <https://github.com/netlify/example-every-color>.
-}

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Head.Seo as Seo
import Html
import Html.Attributes as Attr
import OptimizedDecoder as Decode
import Page exposing (Page, PageWithState, StaticPayload)
import PageServerResponse exposing (PageServerResponse)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Secrets
import Shared
import View exposing (View)


data : routeParams -> DataSource (PageServerResponse Data)
data _ =
    DataSource.Http.get (Secrets.succeed "https://elm-pages-pokedex.netlify.app/.netlify/functions/time")
        Decode.string
        |> DataSource.map Data
        |> DataSource.map PageServerResponse.render


head : (routeParams -> String) -> StaticPayload Data routeParams -> List Head.Tag
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
    -> StaticPayload Data routeParams
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
