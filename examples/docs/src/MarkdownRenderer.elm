module MarkdownRenderer exposing (TableOfContents, view)

import Dotted
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Input
import Element.Region
import Ellie
import Html
import Html.Attributes
import Markdown.Block as Block exposing (Block, Inline, ListItem(..), Task(..))
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer
import Oembed
import Palette
import SyntaxHighlight


buildToc : List Block -> TableOfContents
buildToc blocks =
    let
        headings =
            gatherHeadings blocks
    in
    headings
        |> List.map Tuple.second
        |> List.map
            (\styledList ->
                { anchorId = styledToString styledList |> rawTextToId
                , name = styledToString styledList
                , level = 1
                }
            )


type alias TableOfContents =
    List { anchorId : String, name : String, level : Int }


view : String -> Result String ( TableOfContents, List (Element msg) )
view markdown =
    case
        markdown
            |> Markdown.Parser.parse
    of
        Ok okAst ->
            case Markdown.Renderer.render renderer okAst of
                Ok rendered ->
                    Ok ( buildToc okAst, rendered )

                Err errors ->
                    Err errors

        Err error ->
            Err (error |> List.map Markdown.Parser.deadEndToString |> String.join "\n")


renderer : Markdown.Renderer.Renderer (Element msg)
renderer =
    { heading = heading
    , paragraph =
        Element.paragraph
            [ Element.spacing 15 ]
    , thematicBreak = Element.none
    , text = \value -> Element.paragraph [] [ Element.text value ]
    , strong = \content -> Element.paragraph [ Font.bold ] content
    , emphasis = \content -> Element.paragraph [ Font.italic ] content
    , codeSpan = code
    , link =
        \{ destination } body ->
            Element.newTabLink []
                { url = destination
                , label =
                    Element.paragraph
                        [ Font.color (Element.rgb255 0 0 255)
                        , Element.htmlAttribute (Html.Attributes.style "overflow-wrap" "break-word")
                        , Element.htmlAttribute (Html.Attributes.style "word-break" "break-word")
                        ]
                        body
                }
    , hardLineBreak = Html.br [] [] |> Element.html
    , image =
        \image ->
            case image.title of
                Just _ ->
                    Element.image [ Element.width Element.fill ] { src = image.src, description = image.alt }

                Nothing ->
                    Element.image [ Element.width Element.fill ] { src = image.src, description = image.alt }
    , blockQuote =
        \children ->
            Element.column
                [ Element.Border.widthEach { top = 0, right = 0, bottom = 0, left = 10 }
                , Element.padding 10
                , Element.Border.color (Element.rgb255 145 145 145)
                , Element.Background.color (Element.rgb255 245 245 245)
                ]
                children
    , unorderedList =
        \items ->
            Element.column [ Element.spacing 15 ]
                (items
                    |> List.map
                        (\(ListItem task children) ->
                            Element.paragraph [ Element.spacing 5 ]
                                [ Element.row
                                    [ Element.alignTop ]
                                    ((case task of
                                        IncompleteTask ->
                                            Element.Input.defaultCheckbox False

                                        CompletedTask ->
                                            Element.Input.defaultCheckbox True

                                        NoTask ->
                                            Element.text "•"
                                     )
                                        :: Element.text " "
                                        :: children
                                    )
                                ]
                        )
                )
    , orderedList =
        \startingIndex items ->
            Element.column [ Element.spacing 15 ]
                (items
                    |> List.indexedMap
                        (\index itemBlocks ->
                            Element.row [ Element.spacing 5 ]
                                [ Element.row [ Element.alignTop ]
                                    (Element.text (String.fromInt (index + startingIndex) ++ " ") :: itemBlocks)
                                ]
                        )
                )
    , codeBlock = codeBlock
    , table = Element.column []
    , tableHeader = Element.column []
    , tableBody = Element.column []
    , tableRow = Element.row []
    , tableHeaderCell =
        \_ children ->
            Element.paragraph [] children
    , tableCell = \_ -> Element.paragraph []
    , strikethrough = \content -> Element.paragraph [ Font.strike ] content
    , html =
        Markdown.Html.oneOf
            [ Markdown.Html.tag "banner"
                (\children ->
                    Element.paragraph
                        [ Font.center
                        , Font.size 47
                        , Font.family [ Font.typeface "Montserrat" ]
                        , Font.color Palette.color.primary
                        ]
                        children
                )
            , Markdown.Html.tag "boxes"
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
            , Markdown.Html.tag "box"
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
            , Markdown.Html.tag "values"
                (\children ->
                    Element.row
                        [ Element.spacing 30
                        , Element.htmlAttribute (Html.Attributes.style "flex-wrap" "wrap")
                        ]
                        children
                )
            , Markdown.Html.tag "value"
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
            , Markdown.Html.tag "oembed"
                (\url _ ->
                    Oembed.view [] Nothing url
                        |> Maybe.map Element.html
                        |> Maybe.withDefault Element.none
                        |> Element.el [ Element.centerX ]
                )
                |> Markdown.Html.withAttribute "url"
            , Markdown.Html.tag "ellie-output"
                (\ellieId _ ->
                    Ellie.outputTab ellieId
                )
                |> Markdown.Html.withAttribute "id"
            ]
    }


styledToString : List Inline -> String
styledToString inlines =
    --List.map .string list
    --|> String.join "-"
    -- TODO do I need to hyphenate?
    inlines
        |> Block.extractInlineText


gatherHeadings : List Block -> List ( Block.HeadingLevel, List Inline )
gatherHeadings blocks =
    List.filterMap
        (\block ->
            case block of
                Block.Heading level content ->
                    Just ( level, content )

                _ ->
                    Nothing
        )
        blocks


rawTextToId : String -> String
rawTextToId rawText =
    rawText
        |> String.split " "
        |> String.join "-"
        |> String.toLower


heading : { level : Block.HeadingLevel, rawText : String, children : List (Element msg) } -> Element msg
heading { level, rawText, children } =
    Element.paragraph
        [ Font.size
            (case level of
                Block.H1 ->
                    36

                Block.H2 ->
                    24

                _ ->
                    20
            )
        , Font.bold
        , Font.family [ Font.typeface "Montserrat" ]
        , Element.Region.heading (Block.headingLevelToInt level)
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
            (Element.rgba255 50 50 50 0.07)
        , Element.Border.rounded 2
        , Element.paddingXY 5 3
        , Font.family [ Font.typeface "Roboto Mono", Font.monospace ]
        ]
        (Element.text snippet)


codeBlock : { body : String, language : Maybe String } -> Element msg
codeBlock details =
    Element.paragraph [] [ Element.text details.body ]



-- TODO turn this back on - it's off for now to get more accurate performance benchmarks
--SyntaxHighlight.elm details.body
--    |> Result.map (SyntaxHighlight.toBlockHtml (Just 1))
--    |> Result.withDefault
--        (Html.pre [] [ Html.code [] [ Html.text details.body ] ])
--    |> Element.html
--    |> Element.el [ Element.width Element.fill ]
