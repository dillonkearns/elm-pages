module Route.Escaping exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import Css exposing (..)
import Css.Global
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attr
import Html.Styled.Keyed as HtmlKeyed
import Html.Styled.Lazy as HtmlLazy
import Json.Encode
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    String


data : BackendTask FatalError Data
data =
    BackendTask.File.rawFile "unsafe-script-tag.txt"
        |> BackendTask.allowFatal


head :
    App Data () ActionData RouteParams
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


snapshotComment : String -> Html msg
snapshotComment comment =
    Html.text ("\n\n# " ++ comment ++ "\n")


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view static sharedModel =
    { title = ""
    , body =
        [ snapshotComment "label element with for attribute"
        , Html.label [ Attr.for "note" ] []
        , snapshotComment "CSS via elm-css"
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
            ]
        , snapshotComment "lazy and non-lazy versions render the same output"
        , Html.text static.data
        , HtmlLazy.lazy (.data >> text) static
        , snapshotComment "lazy nodes as direct children of keyed nodes"
        , [ 1 ]
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
        , snapshotComment "lazy nested within keyed nodes"
        , [ 1 ]
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
        , snapshotComment "invalid element name is skipped"
        , Html.node "<script>alert(0)</script>" [] []
        , snapshotComment "invalid attributes are skipped, both string and boolean"
        , Html.div
            [ Attr.attribute "before" "1"
            , Attr.attribute "><script>alert(0)</script>" ""
            , Attr.property "><script>alert(1)</script>" (Json.Encode.bool True)
            , Attr.attribute "onclick=\"alert(0)\" title" ""
            , Attr.attribute "after" "2"
            ]
            []
        , snapshotComment "attribute values are escaped"
        , Html.div [ Attr.title "\"'><script>true && alert(0)</script>" ] []
        , snapshotComment "class attribute values are escaped (it is special cased)"
        , Html.div [ Attr.class "\"'><script>true && alert(0)</script>" ] []
        , snapshotComment "style attribute values are escaped (it is special cased)"
        , Html.div [ Attr.style "display" ";\"'><script>true && alert(0)</script>" ] []
        , snapshotComment "attribute values cannot introduce another attribute"
        , Html.div [ Attr.title "\" onclick=\"alert(0)" ] []
        , snapshotComment "text is escaped"
        , Html.text "<script>true && alert(0)</script>"
        , snapshotComment "children of void elements are skipped"
        , Html.img [] [ Html.text "<script>true && alert(0)</script>" ]
        , snapshotComment "script tags are changed to p tags by the virtual-dom package"
        , Html.node "script" [] [ Html.text "0 < 1 && alert(0)" ]
        , snapshotComment "style tags are allowed, and contain raw text"
        , Html.node "style" [] [ Html.text "body > * { html & { display: none; } }" ]
        ]
    }
