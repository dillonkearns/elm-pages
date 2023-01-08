module Route.Escaping exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import Css exposing (..)
import Css.Global
import Exception exposing (Throwable)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attr
import Html.Styled.Keyed as HtmlKeyed
import Html.Styled.Lazy as HtmlLazy
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    String


data : BackendTask Throwable Data
data =
    BackendTask.File.rawFile "unsafe-script-tag.txt"
        |> BackendTask.throw


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "These quotes should be escaped \"ESCAPE THIS\", and so should <CARETS>"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = ""
    , body =
        [ Html.label [ Attr.for "note" ] []
        , div []
            [ Css.Global.global
                [ Css.Global.typeSelector "div"
                    [ Css.Global.children
                        [ Css.Global.typeSelector "p"
                            [ fontSize (px 14)
                            , color (rgb 255 0 0)
                            ]
                        ]
                    ]
                ]
            , div []
                [ p []
                    [ text "Hello! 2 > 1"
                    ]
                ]
            ]

        -- lazy and non-lazy versions render the same output
        , Html.text static.data
        , HtmlLazy.lazy (.data >> text) static
        , -- lazy nodes as direct children of keyed nodes
          [ 1 ]
            |> List.indexedMap
                (\index _ ->
                    ( String.fromInt index
                    , HtmlLazy.lazy2
                        (\_ _ ->
                            li []
                                [ Html.text <|
                                    "This is number "
                                        ++ String.fromInt index
                                ]
                        )
                        ()
                        ()
                    )
                )
            |> HtmlKeyed.ul []
        , -- lazy nested within keyed nodes
          [ 1 ]
            |> List.indexedMap
                (\index _ ->
                    ( String.fromInt index
                    , div []
                        [ HtmlLazy.lazy2
                            (\_ _ ->
                                li []
                                    [ Html.text <|
                                        "This is nested number "
                                            ++ String.fromInt index
                                    ]
                            )
                            ()
                            ()
                        ]
                    )
                )
            |> HtmlKeyed.ul []
        ]
    }
