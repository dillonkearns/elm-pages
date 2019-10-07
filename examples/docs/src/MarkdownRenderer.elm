module MarkdownRenderer exposing (TableOfContents, view)

import Dotted
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Html exposing (Attribute, Html)
import Html.Attributes exposing (property)
import Html.Events exposing (on)
import Json.Encode as Encode exposing (Value)
import Markdown.Block
import Markdown.Html
import Markdown.Parser
import Oembed
import Pages
import Palette


buildToc : List Markdown.Block.Block -> TableOfContents
buildToc blocks =
    let
        headings =
            gatherHeadings blocks
    in
    headings
        |> List.map Tuple.second
        |> List.map
            (\styledList ->
                { anchorId = styledToString styledList
                , name = styledToString styledList |> rawTextToId
                , level = 1
                }
            )


styledToString : List Markdown.Block.Inline -> String
styledToString list =
    List.map .string list
        |> String.join "-"


gatherHeadings : List Markdown.Block.Block -> List ( Int, List Markdown.Block.Inline )
gatherHeadings blocks =
    List.filterMap
        (\block ->
            case block of
                Markdown.Block.Heading level content ->
                    Just ( level, content )

                _ ->
                    Nothing
        )
        blocks


type alias TableOfContents =
    List { anchorId : String, name : String, level : Int }


view : String -> Result String ( TableOfContents, List (Element msg) )
view markdown =
    case
        markdown
            |> Markdown.Parser.parse
    of
        Ok okAst ->
            case Markdown.Parser.render renderer okAst of
                Ok rendered ->
                    Ok ( buildToc okAst, rendered )

                Err errors ->
                    Err errors

        Err error ->
            Err (error |> List.map Markdown.Parser.deadEndToString |> String.join "\n")


renderer : Markdown.Parser.Renderer (Element msg)
renderer =
    { heading = heading
    , raw =
        Element.paragraph
            [ Element.spacing 15 ]
    , thematicBreak = Element.none
    , plain = Element.text
    , bold = \content -> Element.el [ Font.bold ] (Element.text content)
    , italic = \content -> Element.el [ Font.italic ] (Element.text content)
    , code = code
    , link =
        \link body ->
            -- Pages.isValidRoute link.destination
            --     |> Result.map
            --         (\() ->
            Element.link
                [ Element.htmlAttribute (Html.Attributes.style "display" "inline-flex")
                ]
                { url = link.destination
                , label =
                    Element.paragraph
                        [ Font.color Palette.color.primary
                        ]
                        body
                }
                |> Ok

    -- )
    , image =
        \image body ->
            -- Pages.isValidRoute image.src
            --     |> Result.map
            -- (\() ->
            Element.image [ Element.width Element.fill ] { src = image.src, description = body }
                |> Ok

    -- )
    , list =
        \items ->
            Element.column [ Element.spacing 15 ]
                (items
                    |> List.map
                        (\itemBlocks ->
                            Element.wrappedRow [ Element.spacing 5 ]
                                [ Element.el
                                    [ Element.alignTop ]
                                    (Element.text "•")
                                , itemBlocks
                                ]
                        )
                )
    , codeBlock = codeBlock
    , html =
        Markdown.Html.oneOf
            [ Markdown.Html.tag "Banner"
                (\children ->
                    Element.paragraph
                        [ Font.center
                        , Font.size 47
                        , Font.family [ Font.typeface "Montserrat" ]
                        , Font.color Palette.color.primary
                        ]
                        children
                )
            , Markdown.Html.tag "Boxes"
                (\children ->
                    children
                        |> List.indexedMap
                            (\index aBox ->
                                let
                                    isLast =
                                        index == (List.length children - 1)
                                in
                                [ Just aBox
                                , if isLast then
                                    Nothing

                                  else
                                    Just Dotted.lines
                                ]
                                    |> List.filterMap identity
                            )
                        |> List.concat
                        |> List.reverse
                        |> Element.column [ Element.centerX ]
                )
            , Markdown.Html.tag "Box"
                (\children ->
                    Element.textColumn
                        [ Element.centerX
                        , Font.center
                        , Element.padding 30
                        , Element.Border.shadow { offset = ( 2, 2 ), size = 3, blur = 3, color = Element.rgba255 40 80 80 0.1 }
                        , Element.spacing 15
                        ]
                        children
                )
            , Markdown.Html.tag "Values"
                (\children ->
                    Element.row
                        [ Element.spacing 30
                        , Element.htmlAttribute (Html.Attributes.style "flex-wrap" "wrap")
                        ]
                        children
                )
            , Markdown.Html.tag "Value"
                (\children ->
                    Element.column
                        [ Element.width Element.fill
                        , Element.padding 20
                        , Element.spacing 20
                        , Element.height Element.fill
                        , Element.centerX
                        ]
                        children
                )
            , Markdown.Html.tag "Oembed"
                (\url children ->
                    Oembed.view [] Nothing url
                        |> Maybe.map Element.html
                        |> Maybe.withDefault Element.none
                        |> Element.el [ Element.centerX ]
                )
                |> Markdown.Html.withAttribute "url"
            ]
    }


rawTextToId rawText =
    rawText
        |> String.toLower
        |> String.replace " " ""


heading : { level : Int, rawText : String, children : List (Element msg) } -> Element msg
heading { level, rawText, children } =
    Element.paragraph
        [ Font.size
            (case level of
                1 ->
                    36

                2 ->
                    24

                _ ->
                    20
            )
        , Font.bold
        , Font.family [ Font.typeface "Montserrat" ]
        , Element.Region.heading level
        , Element.htmlAttribute
            (Html.Attributes.attribute "name" (rawTextToId rawText))
        , Element.htmlAttribute
            (Html.Attributes.id (rawTextToId rawText))
        ]
        children


code : String -> Element msg
code snippet =
    Element.el
        [ Element.Background.color
            (Element.rgba 0 0 0 0.04)
        , Element.Border.rounded 2
        , Element.paddingXY 5 3
        , Font.family [ Font.monospace ]
        ]
        (Element.text snippet)


codeBlock : { body : String, language : Maybe String } -> Element msg
codeBlock details =
    Html.node "code-editor" [ editorValue details.body ] []
        |> Element.html
        |> Element.el [ Element.width Element.fill ]


editorValue : String -> Attribute msg
editorValue value =
    value
        |> String.trim
        |> Encode.string
        |> property "editorValue"
