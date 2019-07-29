module MarkParser exposing (document)

import Dict exposing (Dict)
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Html exposing (Html)
import Html.Attributes as Attr
import Index
import Mark
import Mark.Error
import Metadata exposing (Metadata)
import Pages.Parser exposing (PageOrPost)


normalizedUrl url =
    url
        |> String.split "#"
        |> List.head
        |> Maybe.withDefault ""


document :
    Dict String String
    -> List String
    -> List ( List String, Metadata msg )
    -> Mark.Document (PageOrPost (Metadata msg) (Element msg))
document imageAssets routes parsedMetadata =
    Pages.Parser.document
        (Metadata.metadata imageAssets)
        { imageAssets = imageAssets
        , routes = routes
        , indexView = parsedMetadata
        }
        (blocks { imageAssets = imageAssets, routes = routes, indexView = parsedMetadata })


blocks :
    Pages.Parser.AppData (Metadata msg)
    -> List (Mark.Block (Element msg))
blocks appData =
    let
        header : Mark.Block (Element msg)
        header =
            Mark.block "H1"
                (\children ->
                    Element.paragraph
                        [ Font.size 36
                        , Font.bold
                        , Font.center
                        , Font.family [ Font.typeface "Raleway" ]
                        ]
                        children
                )
                text

        h2 : Mark.Block (Element msg)
        h2 =
            Mark.block "H2"
                (\children ->
                    Element.paragraph
                        [ Font.size 24
                        , Font.semiBold
                        , Font.alignLeft
                        , Font.family [ Font.typeface "Raleway" ]
                        ]
                        children
                )
                text

        image : Mark.Block (Element msg)
        image =
            Mark.record "Image"
                (\src description ->
                    Element.image
                        [ Element.width (Element.fill |> Element.maximum 600)
                        , Element.centerX
                        ]
                        { src = src
                        , description = description
                        }
                        |> Element.el [ Element.centerX ]
                )
                |> Mark.field "src" (Pages.Parser.imageSrc appData.imageAssets)
                |> Mark.field "description" Mark.string
                |> Mark.toBlock

        text : Mark.Block (List (Element msg))
        text =
            Mark.textWith
                { view =
                    \styles string ->
                        viewText styles string
                , replacements = Mark.commonReplacements
                , inlines =
                    [ Mark.annotation "link"
                        (\texts url ->
                            Element.link []
                                { url = url
                                , label =
                                    Element.row
                                        [ Font.color
                                            (Element.rgb
                                                (17 / 255)
                                                (132 / 255)
                                                (206 / 255)
                                            )
                                        , Element.mouseOver
                                            [ Font.color
                                                (Element.rgb
                                                    (234 / 255)
                                                    (21 / 255)
                                                    (122 / 255)
                                                )
                                            ]
                                        , Element.htmlAttribute
                                            (Attr.style "display" "inline-flex")
                                        ]
                                        (List.map (applyTuple viewText) texts)
                                }
                        )
                        |> Mark.field "url"
                            (Mark.string
                                |> Mark.verify
                                    (\url ->
                                        if url |> String.startsWith "http" then
                                            Ok url

                                        else if List.member (normalizedUrl url) appData.routes then
                                            Ok url

                                        else
                                            Err
                                                { title = "Unknown relative URL " ++ url
                                                , message =
                                                    [ url
                                                    , "\nMust be one of\n"
                                                    , String.join "\n" appData.routes
                                                    ]
                                                }
                                    )
                            )
                    , Mark.verbatim "code"
                        (\str ->
                            Element.el
                                [ Element.Background.color
                                    (Element.rgba 0 0 0 0.04)
                                , Element.Border.rounded 2
                                , Element.paddingXY 5 3
                                , Font.size 16
                                , Font.color (Element.rgba255 210 40 130 1)
                                , Font.family [ Font.monospace ]
                                ]
                                (Element.text str)
                        )
                    ]
                }

        list : Mark.Block (Element msg)
        list =
            Mark.tree "List" renderList (Mark.map (Element.paragraph []) text)
    in
    [ header
    , h2
    , image
    , list
    , indexContent appData.indexView
    , code
    , Mark.map
        (Element.paragraph
            [ Element.spacing 15 ]
        )
        text
    ]


code =
    Mark.block "Code"
        (\codeSnippet ->
            Element.paragraph
                [ Element.Background.color (Element.rgb255 238 238 238)
                , Element.padding 12
                ]
                [ Element.text codeSnippet ]
        )
        Mark.string



{- Handle Text -}


{-| Render a text fragment.
-}
applyTuple : (a -> b -> c) -> ( a, b ) -> c
applyTuple fn ( one, two ) =
    fn one two


viewText : { a | bold : Bool, italic : Bool, strike : Bool } -> String -> Element msg
viewText styles string =
    Element.el (stylesFor styles) (Element.text string)


stylesFor : { a | bold : Bool, italic : Bool, strike : Bool } -> List (Element.Attribute b)
stylesFor styles =
    [ if styles.bold then
        Just Font.bold

      else
        Nothing
    , if styles.italic then
        Just Font.italic

      else
        Nothing
    , if styles.strike then
        Just Font.strike

      else
        Nothing
    ]
        |> List.filterMap identity



{- Handle Blocks -}


indexContent : List ( List String, Metadata msg ) -> Mark.Block (Element msg)
indexContent posts =
    Mark.record "IndexContent"
        (\postsPath -> Index.view posts)
        |> Mark.field "posts"
            (Mark.string
                |> Mark.verify
                    (\postDirectory ->
                        if postDirectory == "articles" then
                            Ok "articles"

                        else
                            Err
                                { title = "Could not find posts path `" ++ postDirectory ++ "`"
                                , message = "Must be one of " :: [ "articles" ]
                                }
                    )
            )
        |> Mark.toBlock



{- Handling bulleted and numbered lists -}
-- Note: we have to define this as a separate function because
-- `Items` and `Node` are a pair of mutually recursive data structures.
-- It's easiest to render them using two separate functions:
-- renderList and renderItem


renderList : Mark.Enumerated (Element msg) -> Element msg
renderList (Mark.Enumerated enum) =
    Element.column []
        (List.map (renderItem enum.icon) enum.items)


renderItem : Mark.Icon -> Mark.Item (Element msg) -> Element msg
renderItem icon (Mark.Item item) =
    Element.column [ Element.width Element.fill, Element.spacing 20 ]
        [ Element.row [ Element.width Element.fill, Element.spacing 10 ]
            [ Element.el [ Element.alignTop, Element.paddingEach { top = 0, right = 0, bottom = 0, left = 20 } ]
                (Element.text
                    (case icon of
                        Mark.Bullet ->
                            "•"

                        Mark.Number ->
                            (item.index |> Tuple.first |> (\n -> n + 1) |> String.fromInt)
                                ++ "."
                    )
                )
            , Element.row [ Element.width Element.fill ] item.content
            ]
        , renderList item.children
        ]
