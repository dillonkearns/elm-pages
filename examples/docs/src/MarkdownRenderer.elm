module MarkdownRenderer exposing (view)

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
import PagesNew
import Palette


addToc : List Markdown.Parser.Block -> List Markdown.Parser.Block
addToc blocks =
    let
        headings =
            gatherHeadings blocks

        toc =
            Markdown.Parser.ListBlock
                (headings
                    |> List.map Tuple.second
                    |> List.map
                        (\styledList ->
                            List.map
                                (\{ string, style } ->
                                    { string = string
                                    , style =
                                        { style
                                            | link =
                                                Just
                                                    { title = Nothing, destination = "#" ++ styledToString styledList }
                                        }
                                    }
                                )
                                styledList
                        )
                )
    in
    toc
        :: blocks


styledToString : List Markdown.Inlines.StyledString -> String
styledToString list =
    List.map .string list
        |> String.join "-"



-- list
-- ""


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


view : String -> Result String (List (Element msg))
view markdown =
    markdown
        |> Markdown.Parser.parse
        |> Result.map addToc
        |> Markdown.Parser.renderAst
            { heading = heading
            , raw =
                Element.paragraph
                    []

            -- TODO
            , thematicBreak = Element.none
            , plain = Element.text
            , bold = \content -> Element.row [ Font.bold ] [ Element.text content ]
            , italic = \content -> Element.row [ Font.italic ] [ Element.text content ]
            , code = code
            , link =
                \link body ->
                    PagesNew.isValidRoute link.destination
                        |> Result.map
                            (\() ->
                                Element.link [] { url = link.destination, label = Element.text body }
                            )
            , list =
                \items ->
                    Element.column [ Element.spacing 15 ]
                        (items
                            |> List.map
                                (\itemBlocks ->
                                    Element.row [ Element.spacing 5 ]
                                        [ Element.text "•", itemBlocks ]
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
                                |> Element.column [ Element.centerX ]
                        )
                    , Markdown.Parser.htmlTag "Box"
                        (\children ->
                            Element.column
                                [ Element.centerX
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



-- Element.column
--     [ Element.Background.color
--         (Element.rgba 0 0 0 0.04)
--     , Element.Border.rounded 2
--     , Element.padding 20
--     , Font.color (Element.rgba255 0 0 0 1)
--     , Font.family [ Font.monospace ]
--     , Element.width Element.fill
--     , Element.htmlAttribute (Html.Attributes.style "line-height" "1.4em")
--     , Element.htmlAttribute (Html.Attributes.style "white-space" "pre")
--     ]
--     [ Element.text details.body ]


editorValue : String -> Attribute msg
editorValue value =
    value
        |> String.trim
        |> Encode.string
        |> property "editorValue"
