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
import Markdown.Inlines
import Markdown.Parser
import Oembed
import Pages
import Palette


buildToc : List Markdown.Parser.Block -> TableOfContents
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
                , name = styledToString styledList
                , level = 1
                }
            )


styledToString : List Markdown.Inlines.StyledString -> String
styledToString list =
    List.map .string list
        |> String.join "-"


gatherHeadings : List Markdown.Parser.Block -> List ( Int, List Markdown.Inlines.StyledString )
gatherHeadings blocks =
    List.filterMap
        (\block ->
            case block of
                Markdown.Parser.Heading level content ->
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
            case Markdown.Parser.renderAst renderer (Ok okAst) of
                Ok rendered ->
                    Ok ( buildToc okAst, rendered )

                Err errors ->
                    Err errors

        Err error ->
            Err (error |> List.map Markdown.Parser.deadEndToString |> String.join "\n")


renderer =
    { heading = heading
    , raw =
        Element.paragraph
            [ Element.spacing 15 ]
    , thematicBreak = Element.none
    , plain = Element.text
    , bold = \content -> Element.row [ Font.bold ] [ Element.text content ]
    , italic = \content -> Element.row [ Font.italic ] [ Element.text content ]
    , code = code
    , link =
        \link body ->
            Pages.isValidRoute link.destination
                |> Result.map
                    (\() ->
                        Element.link
                            [ Font.color Palette.color.primary
                            ]
                            { url = link.destination, label = Element.text body }
                    )
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
                            Element.row [ Element.spacing 5 ]
                                [ Element.el
                                    [ Element.alignTop ]
                                    (Element.text "•")
                                , itemBlocks
                                ]
                        )
                )
    , codeBlock = codeBlock
    , htmlDecoder =
        Markdown.Parser.htmlOneOf
            [ Markdown.Parser.htmlTag "Banner"
                (\children ->
                    Element.paragraph
                        [ Font.center
                        , Font.size 47
                        , Font.family [ Font.typeface "Montserrat" ]
                        , Font.color Palette.color.primary
                        ]
                        children
                )
            , Markdown.Parser.htmlTag "Boxes"
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
            , Markdown.Parser.htmlTag "Box"
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
            , Markdown.Parser.htmlTag "Values"
                (\children ->
                    Element.row
                        [ Element.spacing 30
                        , Element.htmlAttribute (Html.Attributes.style "flex-wrap" "wrap")
                        ]
                        children
                )
            , Markdown.Parser.htmlTag "Value"
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
            , Markdown.Parser.htmlTag "Oembed"
                (\url children ->
                    Oembed.view [] Nothing url
                        |> Maybe.map Element.html
                        |> Maybe.withDefault Element.none
                        |> Element.el [ Element.centerX ]
                )
                |> Markdown.Parser.withAttribute "url"
            ]
    }


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
        , Font.family [ Font.typeface "Raleway" ]
        , Element.Region.heading level
        , Element.htmlAttribute
            (Html.Attributes.attribute "name" rawText)
        , Element.htmlAttribute
            (Html.Attributes.id rawText)
        ]
        children


code : String -> Element msg
code snippet =
    Element.el
        [ Element.Background.color
            (Element.rgba 0 0 0 0.04)
        , Element.Border.rounded 2
        , Element.paddingXY 5 3
        , Font.color (Element.rgba255 0 0 0 1)
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
